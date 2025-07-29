I would like your help in drafting an upgrade to the Amber framework. This is a Crystal language web framework that is currently modeled after Rails and Pheonix.

There are 2 points of the request/response cycle that are currently exceedingly painful in the way that Amber works.

The request part problems:

Incoming requests with parameters. We have a simple params method that can be used to fetch simple params, but it is only one layer deep. So for example, when JSON requests come in, the params will parse only the outter most layer of object attributes. If there is a JSON attribute that has a nested object in it (of any kind other than basic primitives) it will just interpret the value as a string, which then needs further parsing in the controller action.
The validation API for Amber sucks. It basically needs to be entirely thrown out and reinvented.
In both of these cases we are relying on monkey patches to the std library from Crystal. The params is done by monkey patching the std library and it's HTTP::Request class. This is problematic and has caused problems when users try integrating with third party API's because of the way it modifies these objects.

For outgoing portion of the response cycle the problem is in ensuring a valid response is being sent and documenting what those responses are.

What I want from you is help in designing a new approach to define the params that are expected for each of the controller actions, their supported HTTP verb request types and validating payloads. I want something that will work both for validating incoming requests and the related/required values and have it also work for generating an OpenAPI spec to maintain the documentation for this. I think should should also be true for the outgoing responses.

I think this is entirely reasonable. The OpenAPI spec is limited in returning all the available params for a request and it's response, but I want to dig deeper into the detail and structure it in a way that the correct groupings and their associated impacts are documented. What I mean by this is that often times an end-point has a combination of parameters it expects and they may or may not rely on each other. Valid requests may require certain params be present and contain specific values. I want the new params library to have a way where we programmatically validate that but it also bubbles up and is made clear in our API specification. Please help me create this idea.

Edit

Engineered robust, declarative schema system for Crystal framework
8s






I love this idea! You're essentially looking to create a unified schema system that serves multiple purposes: validation, documentation, and type safety. This is a pattern that's proven very successful in modern frameworks like FastAPI and NestJS. Let me help you design a comprehensive solution for Amber.

Core Design Principles
Schema-First Approach: Define your API contract once, use it everywhere
Type-Safe: Leverage Crystal's type system
No Monkey Patching: Keep everything explicit and contained
Composable: Build complex schemas from simple ones
Self-Documenting: Generate OpenAPI specs automatically
Proposed Architecture
1. Schema Definition DSL
crystal
# Base schema module
module Amber::Schema
  abstract class Base
    macro field(name, type, **options)
      # Generate property with validation metadata
    end
    
    macro nested(name, schema_class)
      # Handle nested objects
    end
    
    macro variant(name, &block)
      # Handle conditional schemas
    end
  end
end

# Example usage
class CreateUserRequest < Amber::Schema::Base
  field :email, String, required: true, format: :email
  field :password, String, required: true, min_length: 8
  field :age, Int32, min: 18, max: 120
  field :preferences, UserPreferences, required: false
  
  nested :address, AddressSchema
  
  # Handle conditional requirements
  variant :with_company do
    field :company_name, String, required: true
    field :tax_id, String, required: true, format: :tax_id
  end
  
  # Custom validation rules
  validate :password_complexity
  validate :age_consent, if: ->(obj : self) { obj.age < 21 }
  
  private def password_complexity
    # Custom validation logic
  end
end

class AddressSchema < Amber::Schema::Base
  field :street, String, required: true
  field :city, String, required: true
  field :country, String, required: true, enum: Countries::ALL
  field :postal_code, String, format: :postal_code
end
2. Controller Integration
crystal
class UsersController < ApplicationController
  include Amber::Schema::Controller
  
  # Define endpoint with schema
  endpoint :create,
    method: :post,
    path: "/users",
    request: CreateUserRequest,
    responses: {
      201 => UserResponse,
      400 => ErrorResponse,
      422 => ValidationErrorResponse
    },
    description: "Create a new user account"
  
  def create
    # params is now typed and validated
    user = User.create!(
      email: params.email,
      password: params.password,
      age: params.age
    )
    
    respond_with UserResponse.new(user), status: 201
  end
  
  # Multiple parameter sources
  endpoint :update,
    method: :patch,
    path: "/users/:id",
    path_params: {id: UUID},
    query_params: UpdateUserQuery,
    body: UpdateUserBody,
    responses: {200 => UserResponse}
  
  def update
    # Access different param types
    user = User.find(path_params.id)
    user.update!(body_params.to_h)
    
    respond_with UserResponse.new(user)
  end
end
3. Complex Validation Rules
crystal
class OrderRequest < Amber::Schema::Base
  field :items, Array(OrderItem), required: true, min_items: 1
  field :shipping_method, String, enum: ["standard", "express", "overnight"]
  field :payment_method, String, enum: ["credit_card", "paypal", "bitcoin"]
  
  # Conditional fields based on payment method
  with_payment_method "credit_card" do
    field :card_number, String, required: true, format: :credit_card
    field :cvv, String, required: true, length: 3..4
    field :expiry, String, required: true, format: :card_expiry
  end
  
  with_payment_method "paypal" do
    field :paypal_email, String, required: true, format: :email
  end
  
  with_payment_method "bitcoin" do
    field :wallet_address, String, required: true, format: :bitcoin_address
  end
  
  # Cross-field validation
  validate :express_shipping_availability
  
  private def express_shipping_availability
    if shipping_method == "express"
      items.each do |item|
        errors.add(:shipping_method, "Item #{item.sku} not available for express shipping") unless item.express_eligible?
      end
    end
  end
end
4. OpenAPI Generation
crystal
module Amber::OpenAPI
  class Generator
    def self.generate(controllers : Array(Class))
      spec = {
        "openapi" => "3.1.0",
        "info" => config_info,
        "paths" => {} of String => Hash(String, Any)
      }
      
      controllers.each do |controller|
        controller.endpoints.each do |endpoint|
          path_item = spec["paths"][endpoint.path] ||= {} of String => Any
          
          path_item[endpoint.method.to_s.downcase] = {
            "summary" => endpoint.description,
            "parameters" => generate_parameters(endpoint),
            "requestBody" => generate_request_body(endpoint),
            "responses" => generate_responses(endpoint),
            "x-conditionals" => generate_conditionals(endpoint)
          }
        end
      end
      
      spec
    end
    
    private def self.generate_conditionals(endpoint)
      # Generate custom OpenAPI extensions for conditional requirements
      conditionals = [] of Hash(String, Any)
      
      endpoint.request_schema.variants.each do |variant|
        conditionals << {
          "when" => variant.condition.to_openapi,
          "then" => {
            "required" => variant.required_fields,
            "properties" => variant.properties_schema
          }
        }
      end
      
      conditionals
    end
  end
end
5. Response Schema and Serialization
crystal
class UserResponse < Amber::Schema::Response
  field :id, UUID
  field :email, String
  field :created_at, Time
  field :profile, ProfileResponse
  
  # Conditional inclusion
  field :admin_notes, String, if: ->(context) { context.current_user.admin? }
  
  # Computed fields
  field :full_name, String do |user|
    "#{user.first_name} #{user.last_name}"
  end
end

# In controller
def show
  user = User.find(params[:id])
  respond_with UserResponse.new(user, context: request_context)
end
6. Error Handling and Validation Responses
crystal
class ValidationErrorResponse < Amber::Schema::Response
  field :errors, Hash(String, Array(String))
  field :message, String, default: "Validation failed"
  
  def self.from_schema_errors(errors : Amber::Schema::Errors)
    new(errors: errors.to_h)
  end
end

# Automatic validation in controller
module Amber::Schema::Controller
  macro endpoint(name, **options)
    def {{name.id}}_with_validation
      schema = {{options[:request]}}.new(raw_params)
      
      if schema.valid?
        # Set typed params
        @params = schema
        {{name.id}}_without_validation
      else
        respond_with ValidationErrorResponse.from_schema_errors(schema.errors), 
                     status: 422
      end
    end
    
    alias_method :{{name.id}}_without_validation, :{{name.id}}
    alias_method :{{name.id}}, :{{name.id}}_with_validation
  end
end
7. Migration Path
To help with migration from the current system:

crystal
# Compatibility layer
module Amber::LegacyParams
  def params
    @legacy_params ||= begin
      if @params.is_a?(Amber::Schema::Base)
        # Convert schema to hash-like interface
        @params.to_legacy_params
      else
        # Fallback to old behavior
        super
      end
    end
  end
end
Key Benefits
Type Safety: Full compile-time type checking for params
No Monkey Patching: Everything is explicit and contained
Single Source of Truth: Schema definitions drive both validation and documentation
Complex Validations: Support for conditional fields, cross-field validation, and custom rules
Automatic Documentation: OpenAPI spec generation with full fidelity
Progressive Migration: Can coexist with current system
Implementation Phases
Phase 1: Core schema system with basic validations
Phase 2: Controller integration and request handling
Phase 3: OpenAPI generation
Phase 4: Response schemas and serialization
Phase 5: Advanced features (conditionals, variants)
This design gives you a powerful, flexible system that solves all the pain points you mentioned while providing a great developer experience. What aspects would you like me to elaborate on?




Retry
I'd like to improve the schema definition dsl a bit. One thing that I think is missing is the ability to say which params should be required together, and if there are specific values required to be present for the params to be valid together. There are plenty of times when I have payloads coming in that when a certain param is present, it's value dictates other param values that need to be present to be valid.

With this, I think we need a better way to tighly couple the valid and invalid responses.

Also, it's a little unclear how the schema object will manage the attributes from the schema once it's parsed and validated. Should the schema object be used directly? Should there be a value object that holds the validated request? Personally I like having namespaced objects that represent the state of things. The is like using Single Table Inheritance in a database to have the class represent the unique state of an object. I understand in this case we aren't using database backed schemas, but I think using different classes to represent the states would be a pattern worth following.

Edit

Reimagined schema validation with state-specific design approach.
4s



Excellent points! Let me redesign the DSL to better handle conditional requirements and state management. You're absolutely right about using different classes to represent states - it makes the code much clearer and safer.

Improved Schema Definition DSL
1. Enhanced Schema with Conditional Requirements
crystal
module Amber::Schema
  abstract class Definition
    # Define parameter dependencies
    macro requires_together(*fields, when_present: nil)
      # All fields must be present together
    end
    
    macro requires_one_of(*fields)
      # Exactly one of these fields must be present
    end
    
    macro when_field(field, value, &block)
      # Conditional requirements based on field values
    end
    
    macro when_present(field, &block)
      # Requirements when a field is present
    end
    
    # State transitions
    macro validates_to(success_type, failure_type = ValidationError)
      # Define what types this schema produces
    end
  end
end

# Example: Payment processing with complex conditionals
class PaymentRequestSchema < Amber::Schema::Definition
  field :amount, Float64, required: true, min: 0.01
  field :currency, String, required: true, enum: ["USD", "EUR", "GBP"]
  field :payment_type, String, required: true, enum: ["card", "bank_transfer", "wallet"]
  
  # Card-specific fields
  field :card_number, String, format: :credit_card
  field :card_cvv, String, length: 3..4
  field :card_expiry, String, format: :card_expiry
  field :card_save, Bool, default: false
  
  # Bank transfer fields
  field :account_number, String
  field :routing_number, String
  field :account_type, String, enum: ["checking", "savings"]
  
  # Digital wallet fields
  field :wallet_provider, String, enum: ["paypal", "apple_pay", "google_pay"]
  field :wallet_token, String
  
  # Conditional requirements based on payment type
  when_field :payment_type, "card" do
    requires :card_number, :card_cvv, :card_expiry
    
    when_field :card_save, true do
      field :customer_id, UUID, required: true
      field :card_nickname, String, max_length: 50
    end
  end
  
  when_field :payment_type, "bank_transfer" do
    requires :account_number, :routing_number, :account_type
    
    when_field :currency, "USD" do
      validates :routing_number, format: :us_routing_number
    end
    
    when_field :currency, "EUR" do
      field :iban, String, required: true, format: :iban
      field :swift_code, String, required: true
    end
  end
  
  when_field :payment_type, "wallet" do
    requires :wallet_provider, :wallet_token
    
    # Wallet-specific validations
    when_field :wallet_provider, "apple_pay" do
      validates :currency, in: ["USD", "EUR"] # Apple Pay limitation
    end
  end
  
  # Cross-field validations
  validate :high_value_payment_checks
  
  # Define state transitions
  validates_to PaymentRequest, PaymentValidationError
  
  private def high_value_payment_checks
    if amount > 10_000 && payment_type == "card"
      errors.add(:payment_type, "High value payments require bank transfer")
    end
  end
end
2. State Objects Pattern
crystal
# Base classes for different states
module Amber::Schema
  abstract class ValidatedRequest
    # Immutable, validated data
    getter raw_data : Hash(String, Any)
    
    def initialize(@raw_data : Hash(String, Any))
    end
  end
  
  abstract class ValidationError
    getter errors : Hash(String, Array(String))
    getter raw_data : Hash(String, Any)
    
    def initialize(@errors : Hash(String, Array(String)), @raw_data : Hash(String, Any))
    end
  end
end

# Concrete validated state
class PaymentRequest < Amber::Schema::ValidatedRequest
  getter amount : Float64
  getter currency : String
  getter payment_type : String
  
  # Type-safe accessors for conditional fields
  def card_details : CardDetails?
    return nil unless payment_type == "card"
    
    CardDetails.new(
      number: raw_data["card_number"].as(String),
      cvv: raw_data["card_cvv"].as(String),
      expiry: raw_data["card_expiry"].as(String),
      save: raw_data["card_save"]?.as?(Bool) || false
    )
  end
  
  def bank_details : BankDetails?
    return nil unless payment_type == "bank_transfer"
    
    BankDetails.new(
      account_number: raw_data["account_number"].as(String),
      routing_number: raw_data["routing_number"].as(String),
      account_type: raw_data["account_type"].as(String),
      iban: raw_data["iban"]?.as?(String),
      swift_code: raw_data["swift_code"]?.as?(String)
    )
  end
  
  struct CardDetails
    getter number : String
    getter cvv : String
    getter expiry : String
    getter save : Bool
  end
  
  struct BankDetails
    getter account_number : String
    getter routing_number : String
    getter account_type : String
    getter iban : String?
    getter swift_code : String?
  end
end

# Validation error state
class PaymentValidationError < Amber::Schema::ValidationError
  def payment_type_errors : Array(String)?
    errors["payment_type"]?
  end
  
  def has_card_errors? : Bool
    errors.keys.any? { |k| k.starts_with?("card_") }
  end
  
  def to_response : PaymentErrorResponse
    PaymentErrorResponse.new(
      message: "Payment validation failed",
      errors: errors,
      error_code: determine_error_code
    )
  end
  
  private def determine_error_code : String
    case
    when has_card_errors?
      "INVALID_CARD"
    when errors["amount"]?
      "INVALID_AMOUNT"
    else
      "VALIDATION_ERROR"
    end
  end
end
3. Controller Integration with Result Pattern
crystal
module Amber::Schema
  # Result type for validation
  abstract struct Result(T, E)
  end
  
  struct Success(T) < Result(T, Nil)
    getter value : T
    
    def initialize(@value : T)
    end
    
    def success? : Bool
      true
    end
  end
  
  struct Failure(E) < Result(Nil, E)
    getter error : E
    
    def initialize(@error : E)
    end
    
    def success? : Bool
      false
    end
  end
end

# Enhanced controller
class PaymentsController < ApplicationController
  endpoint :create,
    method: :post,
    path: "/payments",
    request: PaymentRequestSchema,
    responses: {
      201 => PaymentResponse,
      400 => PaymentErrorResponse,
      422 => PaymentValidationError
    }
  
  def create
    # Pattern match on validation result
    case result = validate_request(PaymentRequestSchema)
    when Success(PaymentRequest)
      process_payment(result.value)
    when Failure(PaymentValidationError)
      respond_with result.error.to_response, status: 422
    end
  end
  
  private def process_payment(request : PaymentRequest)
    payment = case request.payment_type
    when "card"
      process_card_payment(request, request.card_details.not_nil!)
    when "bank_transfer"
      process_bank_transfer(request, request.bank_details.not_nil!)
    when "wallet"
      process_wallet_payment(request)
    else
      raise "Unexpected payment type"
    end
    
    respond_with PaymentResponse.new(payment), status: 201
  end
end
4. Tightly Coupled Response Definitions
crystal
# Group related schemas together
module Payments
  # Request schema defines its response types
  class CreateRequest < Amber::Schema::Definition
    validates_to CreateSuccess, CreateFailure
    
    field :amount, Float64, required: true
    # ... other fields
  end
  
  class CreateSuccess < Amber::Schema::ValidatedRequest
    # Success state has typed accessors
    getter amount : Float64
    
    # Define the response this maps to
    responds_with SuccessResponse
  end
  
  class CreateFailure < Amber::Schema::ValidationError
    # Failure state has error helpers
    responds_with ErrorResponse
  end
  
  class SuccessResponse < Amber::Schema::Response
    field :id, UUID
    field :status, String
    field :amount, Float64
    field :created_at, Time
  end
  
  class ErrorResponse < Amber::Schema::Response
    field :errors, Hash(String, Array(String))
    field :error_code, String
    field :message, String
  end
end

# Usage in controller is now very clean
class PaymentsController < ApplicationController
  include Amber::Schema::Controller
  
  endpoint :create,
    schema: Payments::CreateRequest # All types are inferred
  
  def create
    validate Payments::CreateRequest do |payment|
      # payment is typed as Payments::CreateSuccess
      result = PaymentService.process(payment)
      
      # Automatically uses Payments::SuccessResponse
      respond_with_success(result)
    end
    # Validation failure automatically handled with Payments::ErrorResponse
  end
end
5. Advanced Conditional DSL Examples
crystal
class OrderRequestSchema < Amber::Schema::Definition
  field :items, Array(OrderItem), required: true
  field :shipping_address, Address
  field :billing_address, Address
  field :same_as_shipping, Bool, default: false
  field :gift, Bool, default: false
  field :express_shipping, Bool, default: false
  
  # Complex conditionals
  when_field :same_as_shipping, false do
    requires :billing_address
  end
  
  when_field :gift, true do
    field :gift_message, String, max_length: 200
    field :gift_wrap_type, String, enum: ["basic", "premium"]
    
    requires_one_of :gift_message, :gift_wrap_type
  end
  
  when_field :express_shipping, true do
    validate :express_eligible_items
    
    # Additional cost field appears
    field :express_surcharge_accepted, Bool, required: true
  end
  
  # Multi-field conditionals
  when_fields shipping_address: {country: "US"}, 
              express_shipping: true do
    field :shipping_insurance, Bool, required: true
  end
  
  validates_to ValidatedOrder, OrderValidationError
end

class ValidatedOrder < Amber::Schema::ValidatedRequest
  getter items : Array(OrderItem)
  getter shipping_address : Address
  
  def billing_address : Address
    if raw_data["same_as_shipping"]
      shipping_address
    else
      Address.from_raw(raw_data["billing_address"])
    end
  end
  
  def gift_details : GiftDetails?
    return nil unless raw_data["gift"]
    
    GiftDetails.new(
      message: raw_data["gift_message"]?.as?(String),
      wrap_type: raw_data["gift_wrap_type"]?.as?(String)
    )
  end
  
  def total_with_shipping : Float64
    base_total = items.sum(&.price)
    shipping_cost = express_shipping? ? 25.00 : 10.00
    base_total + shipping_cost
  end
  
  def express_shipping? : Bool
    raw_data["express_shipping"].as(Bool)
  end
end
6. OpenAPI Generation with Conditionals
crystal
module Amber::OpenAPI
  class Generator
    private def generate_schema(schema_class : Class)
      base_schema = {
        "type" => "object",
        "properties" => generate_properties(schema_class),
        "required" => schema_class.required_fields
      }
      
      # Add conditional requirements as OpenAPI 3.1 if/then/else
      if schema_class.has_conditionals?
        base_schema["allOf"] = generate_conditional_schemas(schema_class)
      end
      
      # Add discriminator for payment types, etc
      if schema_class.has_discriminator?
        base_schema["discriminator"] = {
          "propertyName" => schema_class.discriminator_field,
          "mapping" => schema_class.discriminator_mapping
        }
      end
      
      base_schema
    end
    
    private def generate_conditional_schemas(schema_class)
      schema_class.conditionals.map do |conditional|
        {
          "if" => {
            "properties" => {
              conditional.field => {"const" => conditional.value}
            }
          },
          "then" => {
            "properties" => conditional.then_properties,
            "required" => conditional.then_required
          }
        }
      end
    end
  end
end
This design gives you:

State-based Types: Different classes for validated vs invalid states
Complex Conditionals: Flexible DSL for expressing parameter dependencies
Type Safety: Validated requests have typed accessors
Coupled Responses: Schemas define their success/failure response types
Clean Controllers: Validation and response handling is largely automatic
Rich OpenAPI: Conditionals are properly documented
The key insight is treating validation as a state transition from raw data to either a validated request object or a validation error object, each with their own specific types and behaviors.




Retry
Okay this is great. Our next step is to determine how we handle the incoming data types. Not all data types are going to be parsed with this. JSON and XML make sense to support out of the box. What other common structured data request types should I expect to support? How could we map things like URL parameters into these parameter schemas? I know there will be GET requests for end points like the index and performing searches based on URL parameters provided, so how do we account for that?

Edit

Strategized robust data parsing across multiple request types
3s




Great question! Let's design a comprehensive system for handling different data sources and content types. Modern web APIs need to handle parameters from multiple sources, not just request bodies.

Parameter Sources and Content Types
1. Parameter Source Types
crystal
module Amber::Schema
  enum ParamSource
    Path      # /users/:id
    Query     # /users?page=1&sort=name
    Body      # Request body (JSON, XML, etc)
    Header    # X-Api-Key: abc123
    Cookie    # session_id=xyz
    Form      # application/x-www-form-urlencoded
    Multipart # multipart/form-data (file uploads)
  end
  
  # Base parser interface
  abstract class Parser
    abstract def parse(raw_data : String | IO) : Hash(String, Any)
    abstract def content_type : String
  end
end
2. Content Type Parsers
crystal
module Amber::Schema::Parsers
  class JSONParser < Parser
    def parse(raw_data : String | IO) : Hash(String, Any)
      JSON.parse(raw_data.is_a?(IO) ? raw_data.gets_to_end : raw_data).as_h
    rescue JSON::ParseException => e
      raise ParseError.new("Invalid JSON: #{e.message}")
    end
    
    def content_type : String
      "application/json"
    end
  end
  
  class XMLParser < Parser
    def parse(raw_data : String | IO) : Hash(String, Any)
      xml = XML.parse(raw_data.is_a?(IO) ? raw_data.gets_to_end : raw_data)
      xml_to_hash(xml.root.not_nil!)
    end
    
    def content_type : String
      "application/xml"
    end
    
    private def xml_to_hash(node : XML::Node) : Hash(String, Any)
      # Convert XML to nested hash structure
    end
  end
  
  class FormParser < Parser
    def parse(raw_data : String | IO) : Hash(String, Any)
      params = {} of String => Any
      URI::Params.parse(raw_data.to_s) do |key, value|
        # Handle nested params like user[name]=John
        set_nested_param(params, key, value)
      end
      params
    end
    
    def content_type : String
      "application/x-www-form-urlencoded"
    end
  end
  
  class MultipartParser < Parser
    def parse(raw_data : String | IO) : Hash(String, Any)
      # Parse multipart data, handle file uploads
      HTTP::FormData.parse(raw_data) do |part|
        # Process each part
      end
    end
    
    def content_type : String
      "multipart/form-data"
    end
  end
  
  # Additional parsers
  class CSVParser < Parser
    # For bulk operations
  end
  
  class ProtobufParser < Parser
    # For efficient binary data
  end
  
  class MessagePackParser < Parser
    # For efficient binary JSON-like data
  end
end
3. Schema with Multiple Sources
crystal
module Amber::Schema
  abstract class Definition
    # Specify which sources to pull params from
    macro from_path(**fields)
      # Define path parameters
    end
    
    macro from_query(**fields)
      # Define query parameters
    end
    
    macro from_body(**fields)
      # Define body parameters
    end
    
    macro from_header(**fields)
      # Define header parameters
    end
    
    macro from_any(*sources, **fields)
      # Allow param from multiple sources
    end
  end
end

# Example: Search endpoint with multiple param sources
class UserSearchSchema < Amber::Schema::Definition
  # Query parameters for filtering
  from_query do
    field :q, String, as: :query # renamed from 'q' to 'query'
    field :page, Int32, default: 1, min: 1
    field :per_page, Int32, default: 20, min: 1, max: 100
    field :sort, String, enum: ["name", "created_at", "email"], default: "name"
    field :order, String, enum: ["asc", "desc"], default: "asc"
    
    # Array parameters from query string
    field :tags, Array(String), delimiter: ","  # ?tags=ruby,crystal,web
    field :status, Array(String), repeated: true # ?status[]=active&status[]=pending
    
    # Date range filtering
    field :created_after, Time?, format: :iso8601
    field :created_before, Time?, format: :iso8601
    
    # Nested query params
    field :filters, SearchFilters
  end
  
  # Headers for API versioning/auth
  from_header do
    field :api_version, String, key: "X-API-Version", default: "v1"
    field :include, Array(String), key: "X-Include", delimiter: ","
  end
  
  validates_to UserSearchRequest, SearchValidationError
  
  # Custom validations
  validate :date_range_validity
  
  private def date_range_validity
    if created_after && created_before && created_after > created_before
      errors.add(:created_after, "must be before created_before")
    end
  end
end

# Nested query params structure
class SearchFilters < Amber::Schema::Definition
  field :role, String?, enum: ["admin", "user", "guest"]
  field :verified, Bool?
  field :country, String?, format: :iso_country_code
  
  # Handle both filters[role]=admin and filters.role=admin
  accepts_formats [:brackets, :dots]
end
4. Complex GET Request Examples
crystal
# Advanced search with faceted filtering
class ProductSearchSchema < Amber::Schema::Definition
  from_path do
    field :category_slug, String
  end
  
  from_query do
    # Basic search
    field :q, String?, as: :query
    
    # Pagination
    field :page, Int32, default: 1
    field :limit, Int32, default: 20, max: 100
    
    # Price range (multiple formats supported)
    field :price_min, Float64?
    field :price_max, Float64?
    field :price_range, String?, format: /\d+\.?\d*-\d+\.?\d*/ # "10.00-50.00"
    
    # Faceted filtering
    field :brand, Array(String), repeated: true
    field :color, Array(String), repeated: true
    field :size, Array(String), repeated: true
    
    # Complex nested filtering
    field :specs, Hash(String, String) # ?specs[cpu]=i7&specs[ram]=16GB
    
    # Geolocation
    field :near, String? # "lat,lng"
    field :radius, Float64?, default: 10.0 # km
    
    # Sorting with multiple fields
    field :sort, Array(SortField), delimiter: ","
  end
  
  # Parse complex sort parameter
  class SortField < Amber::Schema::ValueObject
    getter field : String
    getter direction : String
    
    def self.from_string(value : String) : SortField
      if value.starts_with?("-")
        new(value[1..], "desc")
      else
        new(value, "asc")
      end
    end
  end
  
  validates_to ProductSearchRequest, SearchValidationError
  
  validate :price_range_consistency
  
  private def price_range_consistency
    if price_range
      min, max = price_range.split("-").map(&.to_f)
      self.price_min ||= min
      self.price_max ||= max
    end
    
    if price_min && price_max && price_min > price_max
      errors.add(:price_min, "must be less than price_max")
    end
  end
end
5. Controller Integration for Different HTTP Methods
crystal
class UsersController < ApplicationController
  # GET with query params
  endpoint :index,
    method: :get,
    path: "/users",
    request: UserSearchSchema,
    responses: {
      200 => PaginatedResponse(UserResponse)
    }
  
  def index
    # params is validated UserSearchRequest
    users = User.search(
      query: params.query,
      filters: params.to_filter_hash
    ).page(params.page).per(params.per_page)
    
    respond_with PaginatedResponse.new(
      data: users.map { |u| UserResponse.new(u) },
      page: params.page,
      total: users.total_count
    )
  end
  
  # POST with JSON body
  endpoint :create,
    method: :post,
    path: "/users",
    request: CreateUserSchema,
    responses: {
      201 => UserResponse,
      422 => ValidationErrorResponse
    }
  
  # PUT with path params and body
  endpoint :update,
    method: :put,
    path: "/users/:id",
    request: UpdateUserSchema, # Combines path + body params
    responses: {
      200 => UserResponse
    }
  
  # DELETE with path params only
  endpoint :destroy,
    method: :delete,
    path: "/users/:id",
    request: DeleteUserSchema, # Only path params
    responses: {
      204 => EmptyResponse
    }
  
  # POST with file upload
  endpoint :upload_avatar,
    method: :post,
    path: "/users/:id/avatar",
    request: AvatarUploadSchema,
    responses: {
      200 => AvatarResponse
    }
end

# Multipart file upload schema
class AvatarUploadSchema < Amber::Schema::Definition
  from_path do
    field :id, UUID
  end
  
  from_body content_type: "multipart/form-data" do
    field :avatar, UploadedFile, required: true
    field :crop_data, CropData? # Optional crop parameters
  end
  
  validates_to AvatarUploadRequest, UploadValidationError
  
  validate :file_size
  validate :file_type
  
  private def file_size
    if avatar.size > 5.megabytes
      errors.add(:avatar, "must be less than 5MB")
    end
  end
  
  private def file_type
    allowed = ["image/jpeg", "image/png", "image/gif"]
    unless allowed.includes?(avatar.content_type)
      errors.add(:avatar, "must be a JPEG, PNG, or GIF")
    end
  end
end
6. Parameter Transformation and Coercion
crystal
module Amber::Schema
  # Type coercion for different sources
  class Coercer
    def self.coerce(value : String, to_type : T.class) : T forall T
      case T
      when Int32.class
        value.to_i
      when Float64.class
        value.to_f64
      when Bool.class
        parse_bool(value)
      when Time.class
        Time.parse_iso8601(value)
      when UUID.class
        UUID.new(value)
      when Array(String).class
        # Handle different array formats
        value.split(",")
      else
        value.as(T)
      end
    end
    
    private def self.parse_bool(value : String) : Bool
      case value.downcase
      when "true", "1", "yes", "on"
        true
      when "false", "0", "no", "off"
        false
      else
        raise ArgumentError.new("Cannot parse '#{value}' as Bool")
      end
    end
  end
end

# Custom type example
struct PaginationParams
  getter page : Int32
  getter per_page : Int32
  getter offset : Int32
  
  def self.from_params(page : String?, per_page : String?)
    page_num = (page || "1").to_i
    per_page_num = (per_page || "20").to_i
    
    new(
      page: page_num,
      per_page: per_page_num,
      offset: (page_num - 1) * per_page_num
    )
  end
end
7. Request Context and Parser Selection
crystal
module Amber::Schema
  class RequestParser
    PARSERS = {
      "application/json" => Parsers::JSONParser.new,
      "application/xml" => Parsers::XMLParser.new,
      "application/x-www-form-urlencoded" => Parsers::FormParser.new,
      "multipart/form-data" => Parsers::MultipartParser.new,
      "text/csv" => Parsers::CSVParser.new,
      "application/protobuf" => Parsers::ProtobufParser.new,
      "application/msgpack" => Parsers::MessagePackParser.new
    }
    
    def self.parse(request : HTTP::Request, schema : Schema::Definition.class)
      params = {} of String => Any
      
      # Extract from different sources based on schema definition
      if schema.uses_path_params?
        params.merge!(extract_path_params(request, schema))
      end
      
      if schema.uses_query_params?
        params.merge!(extract_query_params(request, schema))
      end
      
      if schema.uses_body_params? && request.body
        parser = select_parser(request.headers["Content-Type"]?)
        params.merge!(parser.parse(request.body.not_nil!))
      end
      
      if schema.uses_header_params?
        params.merge!(extract_header_params(request, schema))
      end
      
      # Create and validate schema instance
      schema.new(params)
    end
    
    private def self.select_parser(content_type : String?) : Parser
      return Parsers::JSONParser.new unless content_type
      
      # Handle content type with charset: "application/json; charset=utf-8"
      base_type = content_type.split(";").first.strip
      
      PARSERS[base_type]? || raise UnsupportedContentType.new(content_type)
    end
  end
end
This comprehensive system handles:

Multiple Content Types: JSON, XML, Form, Multipart, CSV, Protobuf, MessagePack
Multiple Parameter Sources: Path, Query, Body, Headers, Cookies
Complex Query Parameters: Arrays, nested objects, date ranges
Type Coercion: Automatic conversion from strings to proper types
File Uploads: With validation for size and type
GET Request Handling: Full support for complex search/filter parameters
Flexible Parsing: Different formats for the same logical structure
The key is treating each parameter source appropriately while maintaining a unified validation approach through your schema system.
