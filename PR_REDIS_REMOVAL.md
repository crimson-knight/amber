# Remove Redis Dependency and Implement Adapter System

## 🎯 Overview

This PR completely removes Redis as a dependency from the Amber framework and replaces it with a clean, extensible adapter system. The framework now provides memory-based implementations by default and allows users to implement custom adapters for their specific storage and messaging needs.

## ⚡ Key Changes

### ✅ **Redis Completely Removed**
- Deleted all Redis-specific implementation files
- Removed conditional compilation flags
- Eliminated `redis_url` from configuration  
- No external dependencies required by default

### 🏗️ **New Adapter System**
- Abstract `SessionAdapter` interface for session storage
- Abstract `PubSubAdapter` interface for WebSocket messaging
- `MemorySessionAdapter` as default session storage
- `MemoryPubSubAdapter` as default pub/sub messaging
- `AdapterFactory` for centralized adapter management

### 📝 **Configuration Updates**
- Added `adapter` key to session configuration
- Added `pubsub` configuration section
- Simplified settings without Redis dependencies

## 🚨 Breaking Changes

### **Configuration Format**
**Before:**
```yaml
session:
  key: "amber.session"
  store: "redis"
  expires: 3600

redis_url: "redis://localhost:6379"
```

**After:**
```yaml
session:
  key: "amber.session"
  store: "signed_cookie"  # For legacy cookie sessions
  adapter: "memory"       # For adapter-based sessions
  expires: 3600

pubsub:
  adapter: "memory"
```

### **Removed Classes/Files**
- `Amber::Router::Session::RedisStore`
- `Amber::WebSockets::Adapters::RedisAdapter`
- `Amber::Adapters::RedisSessionAdapter`
- `Amber::Adapters::RedisPubSubAdapter`
- All Redis conditional compilation code

### **Migration Required**
Applications using Redis for sessions or pub/sub must:
1. Implement custom Redis adapters using the new interfaces
2. Update configuration to use `adapter` keys
3. Register custom adapters with `AdapterFactory`

## 💡 Benefits

### **For Framework Maintainers**
- **Simplified Codebase**: No conditional compilation or external dependencies
- **Easier Testing**: Memory adapters make tests faster and more reliable
- **Reduced Complexity**: Clean interfaces without implementation coupling

### **For Application Developers**
- **Flexibility**: Use any storage/messaging backend (Database, Redis, S3, etc.)
- **No Dependencies**: Framework works out-of-the-box without external services
- **Easy Testing**: Memory adapters perfect for development and testing
- **Custom Solutions**: Implement adapters tailored to specific needs

## 🔧 Implementation Details

### **Session Storage**
```crystal
# Abstract interface
abstract class Amber::Adapters::SessionAdapter
  abstract def get(session_id : String) : String?
  abstract def set(session_id : String, value : String) : Nil
  abstract def delete(session_id : String) : Nil
  abstract def destroy(session_id : String) : Nil
  abstract def exists?(session_id : String) : Bool
  # ... additional methods
end

# Memory implementation (built-in)
class Amber::Adapters::MemorySessionAdapter < SessionAdapter
  # Thread-safe implementation with cleanup
end
```

### **Pub/Sub Messaging**
```crystal
# Abstract interface  
abstract class Amber::Adapters::PubSubAdapter
  abstract def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
  abstract def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
  abstract def unsubscribe(topic : String) : Nil
  # ... additional methods
end

# Memory implementation (built-in)
class Amber::Adapters::MemoryPubSubAdapter < PubSubAdapter
  # Fiber-based async message delivery
end
```

### **Adapter Factory**
```crystal
# Register custom adapters
Amber::Adapters::AdapterFactory.register_session_adapter("database") do
  MyDatabaseSessionAdapter.new(MyDB.connection)
end

# Framework creates adapters based on configuration
adapter = AdapterFactory.create_session_adapter("database")
```

## ✅ Testing

- **79 adapter tests pass** (0 failures)
- All existing session and environment tests updated and passing
- Framework compiles successfully without external dependencies
- Memory adapters provide full functionality for development and testing

## 📖 Documentation

- Updated `REDIS_REFACTOR_PLAN.md` with complete implementation details
- Architecture overview and benefits documented
- Migration guide for existing Redis users
- Examples for custom adapter implementation

## 🎯 Future Considerations

### **Optional Redis Add-on**
While Redis is removed from the core framework, the community can create:
- `amber-redis-adapters` shard with Redis implementations
- Drop-in Redis adapters following the new interfaces
- Easy installation via shard dependencies

### **Community Adapters**
The new system enables community-created adapters for:
- Database session storage (PostgreSQL, MySQL, SQLite)
- Message queues (RabbitMQ, Apache Kafka)
- Cloud services (AWS DynamoDB, Google Cloud Storage)
- Custom enterprise solutions

## 🔍 Validation

Run the following to verify the changes:

```bash
# Verify compilation
crystal build src/amber.cr --no-codegen

# Run adapter tests
crystal spec spec/amber/adapters/

# Test memory functionality
crystal spec spec/amber/router/session/
```

---

**This change modernizes Amber's architecture while maintaining the flexibility to use any storage or messaging backend through the clean adapter system.** 