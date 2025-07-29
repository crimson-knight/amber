# Amber Schema API Implementation Plan

## Executive Summary

This document outlines the implementation plan for a new schema-based parameter validation and API documentation system for the Amber framework. The system will leverage Crystal's annotation feature to create a clean, declarative API that replaces the current parameter handling and validation system. This is a breaking change that will not maintain backward compatibility.

## Problem Statement

Current issues with Amber's parameter handling:
1. **Limited parameter parsing** - Only parses the outermost layer of JSON objects
2. **Weak validation API** - Only supports basic required/optional rules
3. **Monkey patching** - Modifies stdlib's HTTP::Request class
4. **No type safety** - Everything is string-based
5. **No API documentation** - No automatic OpenAPI spec generation
6. **Poor nested object support** - Complex payloads require manual parsing
7. **No content-type awareness** - Same validation regardless of input format

## Solution Overview

A comprehensive schema system that:
- Uses **annotations** for clean, readable controller definitions
- Provides **type-safe** parameter access with deep object parsing
- Supports **complex validation** rules including conditional requirements
- Generates **OpenAPI documentation** automatically from routes and annotations
- Handles **multiple content types** with format-specific validation
- Creates **state-based objects** for validated vs. invalid requests
- **Content-type aware** schemas that validate differently based on input format

## Architecture

### Core Components

#### 1. Annotation-Based Controller Definition

```crystal
# Annotations with proper key-value syntax
annotation Request
end

annotation Response
end

annotation QueryParam
end

annotation PathParam
end

class UsersController < ApplicationController
  # Route definition remains in router file
  # post "/users", UsersController, :create
  
  @[Request(schema: CreateUserSchema, content_type: "application/json")]
  @[Response(status: 201, schema: UserResponse)]
  @[Response(status: 422, schema: ValidationErrorResponse)]
  def create
    # NO direct params access - schema handles validation
    # The method receives a validated request object based on schema
    # This is injected by the framework after validation
    case request_data
    when CreateUserRequest # Success type from schema
      user = User.create!(
        email: request_data.email,
        password: request_data.password
      )
      respond_with UserResponse.new(user), status: 201
    when UserValidationError # Failure type from schema
      # This branch shouldn't be reached - framework handles validation errors
      respond_with request_data.to_response, status: 422
    end
  end
  
  # GET requests with query parameters
  @[QueryParam(name: "page", type: Int32, default: 1)]
  @[QueryParam(name: "per_page", type: Int32, default: 20, max: 100)]
  @[QueryParam(name: "q", type: String, as: "query")]
  @[Response(status: 200, schema: PaginatedResponse(UserResponse))]
  def index
    # Query params are validated and injected as typed object
    users = User.search(query: request_data.query)
                .page(request_data.page)
                .per(request_data.per_page)
    
    respond_with PaginatedResponse.new(users)
  end
  
  # Multiple content type support
  @[Request(schema: UpdateUserJSONSchema, content_type: "application/json")]
  @[Request(schema: UpdateUserFormSchema, content_type: "application/x-www-form-urlencoded")]
  @[Response(status: 200, schema: UserResponse)]
  def update
    # Schema selected based on Content-Type header
    # request_data is the validated object from appropriate schema
    user = User.find(request_data.id)
    user.update!(request_data.to_h)
    respond_with UserResponse.new(user)
  end
end
```

#### How Validation Works

The framework intercepts the request before the controller action:

1. **Schema Selection** - Based on Content-Type header and annotations
2. **Parse & Validate** - Schema parses raw request and validates
3. **Type Conversion** - Returns typed success or failure object
4. **Injection** - Framework injects validated object or returns error response
5. **Controller Execution** - Only runs if validation succeeds

```crystal
# This happens in the framework before your action
macro route(verb, path, controller, action)
  # Read annotations at compile time
  {% method_def = controller.resolve.methods.find { |m| m.name == action.id } %}
  {% request_annotations = method_def.annotations(Request) %}
  
  # Generate validation code
  handler = ->(context : HTTP::Server::Context) {
    # Select schema based on content type
    schema = select_schema(context, {{request_annotations}})
    
    # Validate request
    result = schema.validate(context.request)
    
    case result
    when Amber::Schema::Success
      # Inject validated data and call controller
      controller = {{controller}}.new(context, result.value)
      controller.{{action}}
    when Amber::Schema::Failure
      # Return error response without calling controller
      context.response.status_code = 422
      context.response.print result.error.to_json
    end
  }
end
```

#### 2. Content-Type Aware Schema System

```crystal
module Amber::Schema
  # Base schema class with content-type awareness
  abstract class Definition
    # Content type this schema handles
    macro content_type(type : String)
    
    # Field definitions
    macro field(name, type, **options)
    macro nested(name, schema_class)
    
    # Conditional validations
    macro when_field(field, value, &block)
    macro requires_together(*fields)
    macro requires_one_of(*fields)
    
    # Parameter source specifications
    macro from_query(**fields)
    macro from_path(**fields)
    macro from_body(**fields)
    macro from_header(**fields)
    
    # State transition definition
    macro validates_to(success_type, failure_type)
  end
end

# JSON Schema Example
class CreateUserJSONSchema < Amber::Schema::Definition
  content_type "application/json"
  
  field :email, String, required: true, format: :email
  field :password, String, required: true, min_length: 8
  field :profile, UserProfileSchema  # Nested JSON object
  
  when_field :account_type, "business" do
    field :company_name, String, required: true
    field :tax_id, String, required: true, format: :tax_id
  end
  
  validates_to CreateUserRequest, UserValidationError
end

# Form Data Schema Example (same endpoint, different format)
class CreateUserFormSchema < Amber::Schema::Definition
  content_type "application/x-www-form-urlencoded"
  
  # Form data comes in flat, so we handle nested data differently
  field :email, String, required: true, format: :email
  field :password, String, required: true, min_length: 8
  field :profile_name, String, as: "profile[name]"
  field :profile_bio, String?, as: "profile[bio]"
  
  # Form data uses different field names for business accounts
  when_field :account_type, "business" do
    field :company_name, String, required: true
    field :tax_id, String, required: true
  end
  
  validates_to CreateUserRequest, UserValidationError
  
  # Custom transform for form data to match JSON structure
  def transform_to_nested
    if profile_name || profile_bio
      self.profile = {
        name: profile_name,
        bio: profile_bio
      }
    end
  end
end

# XML Schema Example
class CreateUserXMLSchema < Amber::Schema::Definition
  content_type "application/xml"
  
  # XML has its own structure considerations
  field :email, String, required: true, xpath: "//user/email"
  field :password, String, required: true, xpath: "//user/password"
  field :profile, UserProfileSchema, xpath: "//user/profile"
  
  validates_to CreateUserRequest, UserValidationError
end
```

#### 3. State-Based Validation Results

```crystal
# Validated request state (immutable)
class CreateUserRequest < Amber::Schema::ValidatedRequest
  getter email : String
  getter password : String
  getter profile : UserProfile?
  
  def business_account? : Bool
    raw_data["account_type"] == "business"
  end
  
  def company_details : CompanyDetails?
    return nil unless business_account?
    CompanyDetails.new(
      name: raw_data["company_name"].as(String),
      tax_id: raw_data["tax_id"].as(String)
    )
  end
end

# Validation error state
class UserValidationError < Amber::Schema::ValidationError
  def to_response : ValidationErrorResponse
    ValidationErrorResponse.new(
      errors: errors,
      message: "User validation failed"
    )
  end
end
```

#### 4. Controller Base Class Updates

```crystal
module Amber::Controller
  class Base
    # Remove old params property
    # protected getter params : Amber::Validators::Params
    
    # Add validated request data
    protected getter request_data : Amber::Schema::ValidatedRequest
    
    def initialize(@context : HTTP::Server::Context, @request_data : Amber::Schema::ValidatedRequest)
      # Validated data is injected by framework
    end
  end
end

# The framework generates wrapper methods at compile time
macro generate_action_wrapper(controller, action)
  {% method_def = controller.resolve.methods.find { |m| m.name == action } %}
  {% request_ann = method_def.annotations(Request).first %}
  {% response_anns = method_def.annotations(Response) %}
  
  # Generate validation wrapper
  def {{action}}_with_validation(context : HTTP::Server::Context)
    {% if request_ann %}
      # Get schema class from annotation
      schema_class = {{request_ann[:schema]}}
      content_type = {{request_ann[:content_type] || "application/json"}}
      
      # Validate only if content type matches
      if context.request.headers["Content-Type"]?.try(&.starts_with?(content_type))
        result = schema_class.new.validate(context.request)
        
        case result
        when Amber::Schema::Success
          # Create controller with validated data
          controller = {{controller}}.new(context, result.value)
          controller.{{action}}
        when Amber::Schema::Failure
          # Auto-respond with validation error
          {% error_response = response_anns.find { |r| r[:status] == 422 } %}
          {% if error_response %}
            response_schema = {{error_response[:schema]}}.new(result.error)
            context.response.status_code = 422
            context.response.print response_schema.to_json
          {% else %}
            # Default error response
            context.response.status_code = 422
            context.response.print result.error.to_json
          {% end %}
        end
      else
        # Wrong content type
        context.response.status_code = 415
        context.response.print({error: "Unsupported Media Type"}.to_json)
      end
    {% else %}
      # No validation needed
      controller = {{controller}}.new(context, Amber::Schema::EmptyRequest.new)
      controller.{{action}}
    {% end %}
  end
end
```

### File Structure

```
src/amber/
├── schema/
│   ├── annotations.cr           # Schema-related annotations
│   ├── base.cr                  # Base classes
│   ├── definition.cr            # Schema definition DSL
│   ├── field.cr                 # Field metadata
│   ├── types.cr                 # Type definitions
│   ├── result.cr                # Success/Failure types
│   ├── errors.cr                # Error handling
│   ├── validators/              # Validation rules
│   │   ├── base.cr
│   │   ├── required.cr
│   │   ├── format.cr
│   │   ├── range.cr
│   │   ├── conditional.cr
│   │   └── custom.cr
│   ├── parsers/                 # Content type parsers
│   │   ├── base.cr
│   │   ├── json.cr
│   │   ├── xml.cr
│   │   ├── form.cr
│   │   ├── multipart.cr
│   │   ├── query.cr
│   │   └── request_parser.cr
│   └── response/                # Response schemas
│       ├── base.cr
│       └── serializer.cr
├── controller/
│   ├── annotations.cr           # Controller annotations
│   ├── base.cr                  # Modified base controller
│   ├── schema_integration.cr    # Schema validation integration
│   └── helpers/
│       └── schema_helpers.cr
├── openapi/
│   ├── generator.cr             # OpenAPI spec generator
│   ├── annotation_reader.cr     # Read annotations for docs
│   ├── schema_converter.cr      # Convert schemas to OpenAPI
│   └── spec_builder.cr
└── router/
    ├── schema_registry.cr       # Store schema metadata
    └── schema_middleware.cr     # Validation middleware
```

## Implementation Phases

### Phase 1: Core Schema System (Weeks 1-2)

**Goals:**
- Implement base schema classes and DSL
- Create field definition system with metadata
- Build basic validators (required, format, range)
- Implement state-based result types

**Deliverables:**
- `Amber::Schema::Definition` base class
- Field definition DSL
- Basic validation rules
- `ValidatedRequest` and `ValidationError` base classes

### Phase 2: Annotation System (Week 3)

**Goals:**
- Define all necessary annotations
- Create annotation readers for compile-time processing
- Integrate with router to store metadata

**Deliverables:**
- `@[Endpoint]`, `@[Request]`, `@[Response]` annotations
- `@[QueryParam]`, `@[PathParam]`, etc.
- Annotation processing macros

### Phase 3: Parser System (Week 4)

**Goals:**
- Implement content-type based parsers
- Support deep object parsing for JSON/XML
- Handle file uploads
- Implement type coercion

**Deliverables:**
- Parser interface and implementations
- Request parser coordinator
- Type coercion system

### Phase 4: Controller Integration (Weeks 5-6)

**Goals:**
- Modify base controller for schema support
- Implement validation middleware
- Create migration helpers
- Ensure backward compatibility

**Deliverables:**
- Updated `Controller::Base`
- Schema validation integration
- Migration guide and helpers

### Phase 5: OpenAPI Generation (Week 7)

**Goals:**
- Read routes from router to get paths and methods
- Read controller annotations to get schemas and responses
- Convert schemas to OpenAPI format
- Support conditional validations in docs
- Generate complete OpenAPI spec

**Deliverables:**
- OpenAPI generator that combines routes + annotations
- Route-based path and method detection
- Annotation-based schema documentation
- Conditional validation extensions

### Phase 6: Advanced Features (Week 8)

**Goals:**
- Complex conditional validations
- Response schemas and serialization
- Performance optimization
- Complete documentation

**Deliverables:**
- Full conditional validation DSL
- Response serialization
- Performance benchmarks
- Comprehensive documentation

## Key Design Decisions

### 1. Annotations Over Macros

Using annotations provides:
- **Natural syntax** - Methods look like regular Crystal code
- **Multiple annotations** - Can stack multiple annotations on one method
- **Compile-time access** - Can read at compile time for validation
- **IDE support** - Better tooling support

### 2. State-Based Types

Different classes for validated vs. invalid states:
- **Type safety** - Can't accidentally use invalid data
- **Clear intent** - Code shows whether data is validated
- **Immutability** - Validated data can't be modified

### 3. No Monkey Patching

Clean integration without modifying stdlib:
- **Compatibility** - Won't conflict with other libraries
- **Maintainability** - Easier to update with Crystal releases
- **Clarity** - Clear where functionality comes from

## Migration Strategy

### Breaking Change Notice

This is a **breaking change** that completely replaces the current parameter and validation system. The old `params.validation` API will be removed entirely.

### Migration Path

1. **Define schemas** for all endpoints that need validation
2. **Add annotations** to controller methods
3. **Update controller code** to use typed params
4. **Remove old validation code**
5. **Update tests** to work with new system

### Migration Example

```crystal
# OLD CODE - No longer supported
class UsersController < ApplicationController
  def create
    params.validation do
      required :email
      optional :name
    end
    
    if params.valid?
      User.create!(params.to_h)
    else
      # handle errors
    end
  end
end

# NEW CODE - Required migration

# Define the schema
class CreateUserSchema < Amber::Schema::Definition
  content_type "application/json"
  
  field :email, String, required: true, format: :email
  field :name, String?
  
  validates_to CreateUserRequest, UserValidationError
end

# Define the validated request type
class CreateUserRequest < Amber::Schema::ValidatedRequest
  getter email : String
  getter name : String?
end

# Define the validation error type
class UserValidationError < Amber::Schema::ValidationError
  # Custom error formatting if needed
end

# Controller uses validated data
class UsersController < ApplicationController
  @[Request(schema: CreateUserSchema)]
  @[Response(status: 201, schema: UserResponse)]
  @[Response(status: 422, schema: ValidationErrorResponse)]
  def create
    # NO params access - request_data is typed as CreateUserRequest
    # Validation already happened - this only runs if valid
    user = User.create!(
      email: request_data.email, 
      name: request_data.name
    )
    respond_with UserResponse.new(user), status: 201
  end
end
```

### Key Migration Considerations

1. **No params object** - All data comes through `request_data`
2. **Controller actions only run if valid** - Framework handles validation errors
3. **Type safety** - `request_data` is strongly typed based on schema
4. **Content-type aware** - Different schemas for different content types
5. **Automatic error responses** - 422 with validation errors sent automatically

### How It Works - Request Flow

```crystal
# 1. Request comes in
POST /users
Content-Type: application/json
{"email": "test@example.com", "name": ""}

# 2. Framework intercepts before controller
- Finds @[Request] annotation
- Selects CreateUserSchema based on content-type
- Parses and validates request

# 3a. If VALID - Controller executes
- request_data is CreateUserRequest (success type)
- Controller action runs normally
- Returns successful response

# 3b. If INVALID - Controller never executes
- Framework generates 422 response
- Uses ValidationErrorResponse from @[Response] annotation
- Controller action is never called
```

## Example Usage

### Simple REST API

```crystal
# Routes file (config/routes.cr)
Amber::Server.configure do
  routes :api do
    resources "/articles", ArticlesController, only: [:index, :create, :show, :update, :destroy]
  end
end

# Schema definitions
class CreateArticleSchema < Amber::Schema::Definition
  content_type "application/json"
  
  field :title, String, required: true, min_length: 5
  field :body, String, required: true, min_length: 20
  field :tags, Array(String), default: [] of String
  field :published, Bool, default: false
  
  validates_to ArticleData, ArticleValidationError
end

# Controller with annotations
class ArticlesController < ApplicationController
  @[Response(status: 200, schema: ArticleListResponse)]
  def index
    articles = Article.all
    respond_with ArticleListResponse.new(articles)
  end
  
  @[Request(schema: CreateArticleSchema, content_type: "application/json")]
  @[Response(status: 201, schema: ArticleResponse)]
  @[Response(status: 422, schema: ValidationErrorResponse)]
  def create
    # request_data is typed as ArticleData (validated)
    article = Article.create!(
      title: request_data.title,
      body: request_data.body,
      tags: request_data.tags,
      published: request_data.published
    )
    respond_with ArticleResponse.new(article), status: 201
  end
  
  @[PathParam(name: "id", type: UUID)]
  @[Request(schema: UpdateArticleSchema, content_type: "application/json")]
  @[Response(status: 200, schema: ArticleResponse)]
  def update
    # Path params come through request_data too
    article = Article.find(request_data.id)
    article.update!(
      title: request_data.title,
      body: request_data.body
    )
    respond_with ArticleResponse.new(article)
  end
end
```

### Complex Search Endpoint

```crystal
class ProductSearchSchema < Amber::Schema::Definition
  # No content type needed for query params
  from_query do
    field :q, String?, as: :query
    field :page, Int32, default: 1
    field :per_page, Int32, default: 20, max: 100
    field :price_min, Float64?
    field :price_max, Float64?
    field :categories, Array(String), delimiter: ","
    field :in_stock, Bool, default: true
  end
  
  from_header do
    field :api_version, String, key: "X-API-Version"
  end
  
  validate :price_range_valid
  
  validates_to ProductSearchRequest, SearchValidationError
end

# Routes file
get "/products/search", ProductsController, :search

# Controller
class ProductsController < ApplicationController
  @[Request(schema: ProductSearchSchema)]
  @[Response(status: 200, schema: ProductSearchResponse)]
  def search
    # request_data is typed as ProductSearchRequest
    products = Product.search(
      query: request_data.query,
      categories: request_data.categories,
      price_range: request_data.price_range
    )
    
    respond_with ProductSearchResponse.new(
      products: products,
      page: request_data.page,
      total: products.total_count
    )
  end
end
```

### File Upload

```crystal
class AvatarUploadSchema < Amber::Schema::Definition
  content_type "multipart/form-data"
  
  from_path do
    field :user_id, UUID
  end
  
  from_body do
    field :avatar, UploadedFile, required: true
    field :crop_data, CropParameters?
  end
  
  validate :file_size_under_5mb
  validate :allowed_image_type
  
  validates_to AvatarUploadRequest, UploadValidationError
end

# Routes file
post "/users/:user_id/avatar", UsersController, :upload_avatar

# Controller
class UsersController < ApplicationController
  @[Request(schema: AvatarUploadSchema, content_type: "multipart/form-data")]
  @[Response(status: 200, schema: AvatarResponse)]
  @[Response(status: 413, schema: ErrorResponse, description: "File too large")]
  def upload_avatar
    # request_data is typed as AvatarUploadRequest
    user = User.find(request_data.user_id)
    avatar = user.process_avatar(
      file: request_data.avatar,
      crop: request_data.crop_data
    )
    
    respond_with AvatarResponse.new(avatar)
  end
end
```

## OpenAPI Generation

The OpenAPI spec is generated at compile time by reading route definitions and controller annotations:

```crystal
module Amber::OpenAPI
  # This macro generates the OpenAPI spec at compile time
  macro generate_spec
    # Collect all controller classes
    {% controllers = [] of TypeNode %}
    {% for klass in Object.all_subclasses %}
      {% if klass < Amber::Controller::Base %}
        {% controllers << klass %}
      {% end %}
    {% end %}
    
    spec = {
      "openapi" => "3.1.0",
      "info" => {
        "title" => Amber.settings.name,
        "version" => "1.0.0"
      },
      "paths" => {} of String => Hash(String, Any)
    }
    
    # Process each controller
    {% for controller in controllers %}
      {% for method in controller.methods %}
        # Find matching route for this controller action
        route = find_route_for({{controller}}, {{method.name.stringify}})
        
        if route
          {% request_anns = method.annotations(Request) %}
          {% response_anns = method.annotations(Response) %}
          {% query_params = method.annotations(QueryParam) %}
          {% path_params = method.annotations(PathParam) %}
          
          path_item = spec["paths"][route.path] ||= {} of String => Any
          
          operation = {
            "operationId" => "{{controller.name}}#{{method.name}}",
            "parameters" => [] of Hash(String, Any),
            "responses" => {} of String => Any
          }
          
          # Add path parameters
          {% for param in path_params %}
            operation["parameters"] << {
              "name" => {{param[:name]}},
              "in" => "path",
              "required" => true,
              "schema" => {
                "type" => schema_type_for({{param[:type]}})
              }
            }
          {% end %}
          
          # Add query parameters
          {% for param in query_params %}
            operation["parameters"] << {
              "name" => {{param[:name]}},
              "in" => "query",
              "required" => {{!param[:default]}},
              "schema" => {
                "type" => schema_type_for({{param[:type]}}),
                {% if param[:default] %}
                  "default" => {{param[:default]}}
                {% end %}
              }
            }
          {% end %}
          
          # Add request body
          {% if request_anns.size > 0 %}
            operation["requestBody"] = {
              "required" => true,
              "content" => {} of String => Any
            }
            
            {% for request_ann in request_anns %}
              content_type = {{request_ann[:content_type] || "application/json"}}
              schema_class = {{request_ann[:schema]}}
              
              operation["requestBody"]["content"][content_type] = {
                "schema" => schema_to_openapi(schema_class)
              }
            {% end %}
          {% end %}
          
          # Add responses
          {% for response_ann in response_anns %}
            status = {{response_ann[:status]}}.to_s
            schema_class = {{response_ann[:schema]}}
            
            operation["responses"][status] = {
              "description" => {{response_ann[:description] || "Response"}},
              "content" => {
                "application/json" => {
                  "schema" => schema_to_openapi(schema_class)
                }
              }
            }
          {% end %}
          
          # Default error response if none specified
          {% if !response_anns.any? { |r| r[:status] == 422 } %}
            operation["responses"]["422"] = {
              "description" => "Validation Error",
              "content" => {
                "application/json" => {
                  "schema" => {
                    "$ref" => "#/components/schemas/ValidationError"
                  }
                }
              }
            }
          {% end %}
          
          path_item[route.method.downcase] = operation
        end
      {% end %}
    {% end %}
    
    spec
  end
  
  # Helper to convert Crystal types to OpenAPI types
  private def self.schema_type_for(crystal_type)
    case crystal_type
    when Int32 then "integer"
    when String then "string"
    when Bool then "boolean"
    when Float64 then "number"
    when UUID then {"type" => "string", "format" => "uuid"}
    else "string"
    end
  end
  
  # Convert schema class to OpenAPI schema
  private def self.schema_to_openapi(schema_class)
    # This would introspect the schema class fields
    # and generate appropriate OpenAPI schema
    {
      "type" => "object",
      "properties" => schema_class.openapi_properties,
      "required" => schema_class.required_fields
    }
  end
end

# Usage - generate spec file at compile time
File.write("openapi.json", Amber::OpenAPI.generate_spec.to_json)
```

## Performance Considerations

1. **Compile-time validation** - Schema structure validated at compile time
2. **Lazy parsing** - Only parse request body when needed
3. **Efficient type coercion** - Direct conversion without intermediate strings
4. **Pooled parsers** - Reuse parser instances
5. **Content-type based routing** - Select appropriate schema based on Content-Type header

## Testing Strategy

1. **Unit tests** - Each component tested in isolation
2. **Integration tests** - Full request/response cycle
3. **Performance benchmarks** - Compare with current system
4. **Migration tests** - Ensure backward compatibility

## Documentation Plan

1. **API Reference** - Full documentation of all classes/methods
2. **Migration Guide** - Step-by-step migration instructions
3. **Examples** - Common use cases and patterns
4. **OpenAPI Integration** - How to generate and use API docs

## Key Innovations

### 1. Schema-First Validation
- Define schemas that describe expected input
- Schemas handle parsing, validation, and type conversion
- Different schemas for different content types
- Validation happens before controller execution

### 2. No Direct Parameter Access
- No `params` object in controllers
- All data comes through typed `request_data` object
- Type safety throughout the application
- No string-based parameter access

### 3. Automatic Error Handling
- Controllers only execute if validation passes
- Framework automatically returns 422 for validation errors
- Error responses defined via annotations
- No manual validation checks needed

### 4. Compile-Time OpenAPI Generation
- Annotations are read at compile time via macros
- Routes provide paths and methods
- Annotations provide schemas and responses
- Complete API documentation generated automatically

### 5. Content-Type Awareness
- Different schemas for JSON, XML, forms, etc.
- Same endpoint can accept multiple formats
- Each format can have different validation rules
- Automatic content negotiation

## Success Metrics

1. **Type Safety** - 100% compile-time type checking
2. **Performance** - No more than 5% overhead vs current system
3. **Adoption** - Clear migration path with examples
4. **Documentation** - Complete OpenAPI spec generation
5. **Developer Experience** - Cleaner, more intuitive API

## Next Steps

1. Review and approve this plan
2. Set up development branch
3. Begin Phase 1 implementation
4. Create proof-of-concept with basic functionality
5. Gather feedback and iterate