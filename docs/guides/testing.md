# Testing Framework

Amber ships with a testing framework built on Crystal's `spec` library. It provides modules for making HTTP requests against your application without starting a real server, building controller instances in isolation, asserting on response properties, and testing WebSocket channels.

## Quick Start

```crystal
require "spec"
require "../src/my_app"

describe "HomeController" do
  include Amber::Testing::RequestHelpers
  include Amber::Testing::Assertions

  it "returns the home page" do
    response = get("/")
    assert_response_success(response)
    assert_html_content_type(response)
    assert_body_contains(response, "Welcome")
  end
end
```

## RequestHelpers

Include `Amber::Testing::RequestHelpers` in your spec context to make HTTP requests against the Amber application. Requests are routed through the Amber pipeline programmatically, without starting a real HTTP server.

```crystal
describe "API" do
  include Amber::Testing::RequestHelpers

  it "lists items" do
    response = get("/api/items")
    response.status_code.should eq(200)
  end
end
```

### Available Methods

| Method | Description |
|--------|-------------|
| `get(path, headers?)` | Send a GET request |
| `post(path, body?, headers?)` | Send a POST request |
| `put(path, body?, headers?)` | Send a PUT request |
| `patch(path, body?, headers?)` | Send a PATCH request |
| `delete(path, headers?)` | Send a DELETE request |
| `head(path, headers?)` | Send a HEAD request |
| `post_json(path, body)` | POST with JSON Content-Type and Accept headers |
| `put_json(path, body)` | PUT with JSON Content-Type and Accept headers |
| `patch_json(path, body)` | PATCH with JSON Content-Type and Accept headers |

### Setting Headers

```crystal
headers = HTTP::Headers{"Authorization" => "Bearer token123"}
response = get("/api/protected", headers: headers)
```

### Sending JSON

The `post_json`, `put_json`, and `patch_json` helpers automatically set the `Content-Type` and `Accept` headers to `application/json` and serialize the body with `to_json`:

```crystal
response = post_json("/api/users", {name: "Alice", email: "alice@example.com"})
response.status_code.should eq(201)
```

### Sending Form Data

```crystal
response = post("/users", body: "name=Alice&email=alice%40example.com")
```

## TestResponse

All request helpers return a `TestResponse` object with convenient methods for assertions:

```crystal
response = get("/api/status")

# Status code
response.status_code     # => 200

# Status category checks
response.successful?     # => true  (2xx)
response.redirect?       # => false (3xx)
response.client_error?   # => false (4xx)
response.server_error?   # => false (5xx)

# Body
response.body            # => "{"status":"ok"}"

# JSON parsing (raises JSON::ParseException on invalid JSON)
json = response.json     # => JSON::Any
json["status"].as_s      # => "ok"

# Headers
response.headers         # => HTTP::Headers
response.content_type    # => "application/json"
response.redirect_url    # => String? (Location header)
```

## Assertions

Include `Amber::Testing::Assertions` for domain-specific assertion helpers:

```crystal
describe "API" do
  include Amber::Testing::RequestHelpers
  include Amber::Testing::Assertions

  it "returns success" do
    response = get("/api/status")
    assert_response_success(response)
    assert_json_content_type(response)
  end

  it "redirects to login" do
    response = get("/dashboard")
    assert_response_redirect(response)
    assert_redirect_to(response, "/login")
  end

  it "returns 404 for missing resources" do
    response = get("/api/items/999999")
    assert_response_not_found(response)
  end
end
```

### Available Assertions

| Assertion | Description |
|-----------|-------------|
| `assert_response_status(response, code)` | Exact status code match |
| `assert_response_success(response)` | Status is 2xx |
| `assert_response_redirect(response)` | Status is 3xx |
| `assert_redirect_to(response, path)` | Redirect to specific URL |
| `assert_response_client_error(response)` | Status is 4xx |
| `assert_response_not_found(response)` | Status is 404 |
| `assert_response_server_error(response)` | Status is 5xx |
| `assert_content_type(response, type)` | Content-Type contains string |
| `assert_json_content_type(response)` | Content-Type is application/json |
| `assert_html_content_type(response)` | Content-Type is text/html |
| `assert_body_contains(response, text)` | Body contains string |
| `assert_json_body(response)` | Body is valid JSON, returns parsed JSON::Any |
| `assert_header(response, key, value)` | Header has exact value |

## ControllerHelpers

Include `Amber::Testing::ControllerHelpers` to test individual controllers in isolation, without routing through the full pipeline.

### Building Test Contexts

```crystal
include Amber::Testing::ControllerHelpers

# Build a basic context
context = build_test_context(method: "GET", path: "/users")

# Build a context with params
context = build_test_context(
  method: "POST",
  path: "/users",
  headers: HTTP::Headers{"Content-Type" => "application/json"},
  params: {"name" => "Alice"}
)
```

### Building Controllers

The `build_controller` macro creates a controller instance with a test context:

```crystal
include Amber::Testing::ControllerHelpers

describe UsersController do
  it "returns the index page" do
    controller = build_controller(UsersController, :index, "GET", "/users")
    result = controller.index
    result.should contain("Users")
  end
end
```

### Controller Assertions

```crystal
include Amber::Testing::ControllerHelpers

describe UsersController do
  it "responds with 200" do
    controller = build_controller(UsersController, :index, "GET", "/users")
    controller.index
    assert_controller_response(controller, 200)
  end

  it "redirects after create" do
    controller = build_controller(UsersController, :create, "POST", "/users")
    controller.create
    assert_controller_redirect_to(controller, "/users/1")
  end

  it "returns JSON content type" do
    controller = build_controller(UsersController, :index, "GET", "/api/users")
    controller.index
    assert_controller_content_type(controller, "application/json")
  end
end
```

## ContextBuilder

The `ContextBuilder` class provides a fluent interface for constructing `HTTP::Server::Context` objects for testing:

```crystal
context = Amber::Testing::ContextBuilder.new
  .method("POST")
  .path("/users")
  .header("Content-Type", "application/json")
  .json_body({name: "Alice", email: "alice@example.com"})
  .build
```

### Builder Methods

| Method | Description |
|--------|-------------|
| `method(m)` | Set HTTP method (GET, POST, PUT, PATCH, DELETE) |
| `path(p)` | Set request path |
| `header(key, value)` | Add a request header |
| `body(b)` | Set raw string body |
| `json_body(data)` | Set JSON body (auto-sets Content-Type) |
| `query_param(key, value)` | Add a query parameter |
| `params(hash)` | Add multiple query parameters |
| `build` | Build the HTTP::Server::Context |
| `build_with_io` | Build and return {Context, IO::Memory} tuple |

## WebSocketHelpers

Include `Amber::Testing::WebSocketHelpers` for testing WebSocket channels.

```crystal
describe "ChatChannel" do
  include Amber::Testing::WebSocketHelpers

  it "receives messages" do
    test_socket = create_test_socket("/chat")

    test_socket.send_json("join", "chat:lobby")
    test_socket.send_json("message", "chat:lobby", {"text" => "Hello!"})

    test_socket.list_of_received_messages.should_not be_empty
    test_socket.close
  end
end
```

### TestWebSocket

The `TestWebSocket` class wraps a WebSocket connection for use in tests. It tracks sent and received messages.

```crystal
test_socket = create_test_socket("/chat")

# Send a raw message
test_socket.send({"event" => "join", "topic" => "room:1"}.to_json)

# Send a structured JSON message
test_socket.send_json("message", "room:1", {"text" => "Hello"})

# Check received messages
test_socket.list_of_received_messages  # => Array(String)
test_socket.receive                     # => String? (last message)

# Check sent messages
test_socket.list_of_sent_messages      # => Array(String)

# Check connection state
test_socket.is_closed?                 # => Bool

# Clean up
test_socket.close
```

## Complete Test Example

```crystal
require "spec"
require "../src/my_app"

describe "Users API" do
  include Amber::Testing::RequestHelpers
  include Amber::Testing::Assertions

  describe "GET /api/users" do
    it "returns a list of users" do
      response = get("/api/users")
      assert_response_success(response)
      assert_json_content_type(response)

      json = assert_json_body(response)
      json.as_a.should_not be_empty
    end
  end

  describe "POST /api/users" do
    it "creates a user with valid data" do
      response = post_json("/api/users", {
        name:  "Alice",
        email: "alice@example.com",
      })
      assert_response_status(response, 201)
    end

    it "rejects invalid data" do
      response = post_json("/api/users", {name: ""})
      assert_response_client_error(response)
    end
  end

  describe "DELETE /api/users/:id" do
    it "deletes a user" do
      response = delete("/api/users/1")
      assert_response_success(response)
    end
  end
end
```

## Source Files

- `src/amber/testing.cr` -- Module entry point
- `src/amber/testing/request_helpers.cr` -- HTTP request helpers
- `src/amber/testing/controller_helpers.cr` -- Controller isolation helpers
- `src/amber/testing/assertions.cr` -- Domain-specific assertions
- `src/amber/testing/test_response.cr` -- TestResponse wrapper class
- `src/amber/testing/websocket_helpers.cr` -- WebSocket testing helpers
- `src/amber/testing/context_builder.cr` -- Fluent context builder
