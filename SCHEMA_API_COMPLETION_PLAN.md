# Schema API Completion Plan

## Current Status: 5 failures out of 261 tests (98.1% success rate)

**Phase 1 (IN PROGRESS)**: Fix Core Validation Issues
- ✅ Fix Nested Schema Integration
- ✅ Fix Format Validators  
- ✅ Fix Enum Type Handling

## Phase 2: Complete Remaining Features (Medium Priority)

### 4. Implement XML Parser
- XPath-based field extraction for complex XML structures
- XML namespace support for handling different XML schemas
- Integration with parser registry for content-type selection
- Support for XML attributes vs elements
- CDATA section handling

### 5. Enhance Form Data Parser
- Advanced multipart/form-data handling
- File upload support with validation (size, type, etc.)
- Complex nested form data (arrays, objects)
- Support for repeated fields and checkbox arrays
- Integration with existing type coercion system

## Phase 3: Advanced Features (Lower Priority)

### 6. Implement OpenAPI Generation
- Compile-time spec generation from controller annotations
- Schema-to-OpenAPI conversion with proper types
- Documentation integration with existing route definitions
- Support for multiple response schemas per endpoint
- Security scheme generation from authentication annotations

### 7. Add Route-Level Validation
- Annotation processing in route definitions
- Automatic validation hooks in router
- Integration tests for full request lifecycle
- Performance optimization for annotation reading
- Backward compatibility with existing route syntax

## Implementation Details

### XML Parser Implementation
```crystal
# Support for XPath extraction
field :title, String, xpath: "//book/title"
field :authors, Array(String), xpath: "//book/author"

# Namespace support
field :id, String, xpath: "//ns:book/@id", 
      namespaces: {"ns" => "http://example.com/books"}
```

### Enhanced Form Data Parser
```crystal
# File upload validation
field :avatar, File, max_size: 5.megabytes, 
      allowed_types: ["image/jpeg", "image/png"]

# Complex nested forms
field :address_street, String, as: "user[address][street]"
field :tags, Array(String), repeated: true  # tags[]=a&tags[]=b
```

### OpenAPI Generation
```crystal
# Automatic generation from annotations
@[Request(schema: CreateUserSchema, content_type: "application/json")]
@[Response(status: 201, schema: UserResponse)]
@[Response(status: 422, schema: ValidationErrorResponse)]
def create
  # Implementation generates OpenAPI spec automatically
end
```

## Expected Outcomes
- **Phase 2**: Complete content-type support for XML and advanced forms
- **Phase 3**: Full Schema API feature with automatic documentation
- **Final**: Production-ready schema validation system for Amber

## Risk Assessment
- **XML Parser**: Medium complexity, good test coverage needed
- **Form Enhancement**: Low risk, incremental improvements
- **OpenAPI Generation**: High complexity, requires macro expertise
- **Route Integration**: Medium risk, affects core framework behavior

## Testing Strategy
- Each phase should maintain 100% test coverage
- Integration tests for each parser type
- Performance benchmarks for validation overhead
- Documentation examples for each feature

---
*Plan created: Phase 1 completion - targeting 100% test success*