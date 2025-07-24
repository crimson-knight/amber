# Amber Framework: Redis Dependency Removal - COMPLETE!

## Overview

The Amber framework has been successfully refactored to remove its tight coupling with Redis. The framework now uses an abstracted adapter system that allows users to implement custom storage and messaging backends without any dependency on Redis or any other specific implementation.

**Key Changes:**
- ✅ **Redis completely removed** from the codebase - no dependencies, no conditional compilation
- ✅ **Memory adapters** as the only built-in implementations  
- ✅ **Clean adapter interfaces** for session storage and pub/sub messaging
- ✅ **Simple configuration** via YAML settings
- ✅ **Extensible system** for custom adapter implementations
- ✅ **No backward compatibility** required - clean, simplified codebase

## Architecture

### Adapter Interfaces

The framework now provides two main abstract adapter interfaces:

#### SessionAdapter
```crystal
abstract class Amber::Adapters::SessionAdapter
  abstract def get(session_id : String, key : String) : String?
  abstract def set(session_id : String, key : String, value : String) : Nil
  abstract def delete(session_id : String, key : String) : Nil
  abstract def destroy(session_id : String) : Nil
  abstract def exists?(session_id : String) : Bool
  abstract def keys(session_id : String) : Array(String)
  abstract def values(session_id : String) : Array(String)
  abstract def to_hash(session_id : String) : Hash(String, String)
  abstract def empty?(session_id : String) : Bool
  abstract def expire(session_id : String, seconds : Int32) : Nil
  abstract def batch_set(session_id : String, data : Hash(String, String)) : Nil
end
```

#### PubSubAdapter
```crystal
abstract class Amber::Adapters::PubSubAdapter
  abstract def publish(topic : String, message : JSON::Any) : Nil
  abstract def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
  abstract def unsubscribe(topic : String) : Nil
  abstract def unsubscribe_all : Nil
  abstract def close : Nil
end
```

### Built-in Implementations

#### MemorySessionAdapter
- Thread-safe in-memory session storage using `Mutex`
- Automatic session expiration with background cleanup fiber
- Hash-based storage with TTL support
- Default session adapter for all applications

#### MemoryPubSubAdapter
- In-process pub/sub messaging using `Channel(Message)`
- Asynchronous message delivery via fibers
- Topic-based subscription management
- Default pub/sub adapter for WebSocket channels

## Configuration

Configure adapters in your application's environment files:

```yaml
# config/environments/development.yml
session:
  key: "myapp.session"
  store: "signed_cookie"
  expires: 3600
  adapter: "memory"       # Uses MemorySessionAdapter

pubsub:
  adapter: "memory"       # Uses MemoryPubSubAdapter
```

```yaml
# config/environments/production.yml  
session:
  key: "myapp.session"
  store: "signed_cookie"
  expires: 7200
  adapter: "database"     # Custom adapter (must be registered)

pubsub:
  adapter: "redis"        # Custom adapter (must be registered)
```

## Creating Custom Adapters

### Custom Session Adapter

```crystal
# src/adapters/database_session_adapter.cr
class DatabaseSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@db : DB::Database)
  end

  def get(session_id : String, key : String) : String?
    @db.query_one?("SELECT value FROM sessions WHERE session_id = ? AND key = ?", 
                   session_id, key, as: String)
  end

  def set(session_id : String, key : String, value : String) : Nil
    @db.exec("INSERT OR REPLACE INTO sessions (session_id, key, value, expires_at) VALUES (?, ?, ?, ?)",
             session_id, key, value, Time.utc + 1.hour)
  end

  def delete(session_id : String, key : String) : Nil
    @db.exec("DELETE FROM sessions WHERE session_id = ? AND key = ?", session_id, key)
  end

  def destroy(session_id : String) : Nil
    @db.exec("DELETE FROM sessions WHERE session_id = ?", session_id)
  end

  def exists?(session_id : String) : Bool
    @db.query_one("SELECT COUNT(*) FROM sessions WHERE session_id = ?", 
                  session_id, as: Int32) > 0
  end

  def keys(session_id : String) : Array(String)
    @db.query_all("SELECT key FROM sessions WHERE session_id = ?", 
                  session_id, as: String)
  end

  def values(session_id : String) : Array(String)
    @db.query_all("SELECT value FROM sessions WHERE session_id = ?", 
                  session_id, as: String)
  end

  def to_hash(session_id : String) : Hash(String, String)
    result = Hash(String, String).new
    @db.query_each("SELECT key, value FROM sessions WHERE session_id = ?", session_id) do |rs|
      result[rs.read(String)] = rs.read(String)
    end
    result
  end

  def empty?(session_id : String) : Bool
    @db.query_one("SELECT COUNT(*) FROM sessions WHERE session_id = ?", 
                  session_id, as: Int32) == 0
  end

  def expire(session_id : String, seconds : Int32) : Nil
    expires_at = Time.utc + seconds.seconds
    @db.exec("UPDATE sessions SET expires_at = ? WHERE session_id = ?", 
             expires_at, session_id)
  end

  def batch_set(session_id : String, data : Hash(String, String)) : Nil
    @db.transaction do |tx|
      data.each do |key, value|
        tx.connection.exec("INSERT OR REPLACE INTO sessions (session_id, key, value, expires_at) VALUES (?, ?, ?, ?)",
                          session_id, key, value, Time.utc + 1.hour)
      end
    end
  end
end
```

### Custom PubSub Adapter

```crystal
# src/adapters/redis_pubsub_adapter.cr
require "redis"

class RedisPubSubAdapter < Amber::Adapters::PubSubAdapter
  def initialize(@redis : Redis)
    @subscriptions = Hash(String, (String, JSON::Any) -> Nil).new
    @subscriber = Redis.new(url: @redis.url)
    spawn { listen_for_messages }
  end

  def publish(topic : String, message : JSON::Any) : Nil
    @redis.publish(topic, message.to_json)
  end

  def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
    @subscriptions[topic] = block
    @subscriber.subscribe(topic)
  end

  def unsubscribe(topic : String) : Nil
    @subscriptions.delete(topic)
    @subscriber.unsubscribe(topic)
  end

  def unsubscribe_all : Nil
    @subscriptions.clear
    @subscriber.unsubscribe
  end

  def close : Nil
    @subscriber.close
    @redis.close
  end

  private def listen_for_messages
    @subscriber.subscribe do |on|
      on.message do |channel, message|
        if callback = @subscriptions[channel]?
          begin
            json_message = JSON.parse(message)
            callback.call(channel, json_message)
          rescue JSON::ParseException
            # Handle malformed messages
          end
        end
      end
    end
  end
end
```

## Registering Custom Adapters

Register your custom adapters during application initialization:

```crystal
# config/application.cr or src/your_app.cr

# Register custom session adapter
Amber::Adapters::AdapterFactory.register_session_adapter("database") do
  DatabaseSessionAdapter.new(MyApp.database)
end

# Register custom pub/sub adapter  
Amber::Adapters::AdapterFactory.register_pubsub_adapter("redis") do
  redis = Redis.new(url: ENV["REDIS_URL"])
  RedisPubSubAdapter.new(redis)
end
```

## Migration from Legacy Redis

If you were previously using Redis with Amber, here's how to migrate:

### 1. Remove Redis Dependencies

Remove Redis from your `shard.yml`:

```yaml
# Remove this from dependencies:
# redis:
#   github: stefanwille/crystal-redis
#   version: "~> 2.9.1"
```

### 2. Update Configuration

Replace Redis session configuration:

```yaml
# OLD (remove):
session:
  key: "myapp.session"
  store: "redis"  # Remove this
  expires: 3600

# NEW:
session:
  key: "myapp.session"
  store: "signed_cookie"
  expires: 3600
  adapter: "memory"  # Or your custom adapter
```

### 3. Custom Redis Implementation (Optional)

If you need Redis functionality, implement a custom adapter as shown above and register it in your application.

## Benefits

### 1. **No External Dependencies**
- Framework works out-of-the-box with no Redis installation required
- Simplified deployment and development setup
- Reduced attack surface and dependency management

### 2. **Framework Agnostic**
- Choose any storage backend (Redis, PostgreSQL, MongoDB, etc.)
- Mix and match different adapters for different environments
- Easy to test with in-memory adapters

### 3. **Performance Optimized**
- Memory adapters provide excellent performance for development
- Production adapters can be optimized for specific use cases
- No network overhead for local development

### 4. **Clean Architecture**
- Clear separation of concerns
- Easy to understand and maintain
- Follows SOLID principles

## Testing

The framework includes comprehensive tests for all adapter implementations:

```bash
# Run all adapter tests
crystal spec spec/amber/adapters/

# Run specific adapter tests
crystal spec spec/amber/adapters/memory_session_adapter_spec.cr
crystal spec spec/amber/adapters/memory_pubsub_adapter_spec.cr
crystal spec spec/amber/adapters/adapter_factory_spec.cr
```

Test your custom adapters by inheriting from the provided test suites:

```crystal
# spec/adapters/database_session_adapter_spec.cr
require "../../spec_helper"

describe DatabaseSessionAdapter do
  adapter = DatabaseSessionAdapter.new(test_database)
  
  # Include shared examples for SessionAdapter compliance
  it_behaves_like "a session adapter", adapter
end
```

## Important Notes

1. **Breaking Change**: This is a breaking change that removes all Redis dependencies. Applications relying on Redis must implement custom adapters.

2. **Memory Limitations**: The default memory adapters store data in process memory. For production applications with multiple server instances, consider implementing persistent adapters.

3. **Session Distribution**: Memory sessions are not shared across server instances. Use a persistent adapter (database, Redis, etc.) for distributed applications.

4. **WebSocket Scaling**: Memory pub/sub only works within a single process. Implement a distributed pub/sub adapter for multi-server WebSocket applications.

5. **Configuration Migration**: Update your configuration files to use the new `adapter` keys instead of the legacy `store: "redis"` configuration.

## Summary

The Redis dependency removal is complete! The Amber framework now provides:

- ✅ Clean adapter interfaces for extensibility
- ✅ Memory-based default implementations  
- ✅ No external dependencies required
- ✅ Simple configuration system
- ✅ Comprehensive test coverage
- ✅ Documentation for custom adapter development

The framework is now more flexible, easier to deploy, and simpler to understand while maintaining full functionality through the adapter system. 