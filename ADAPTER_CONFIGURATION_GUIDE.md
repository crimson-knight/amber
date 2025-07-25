# Amber Framework: Adapter Configuration Guide

This guide explains how to configure and use the new adapter system in Amber Framework. The adapter system provides a clean abstraction for session storage and pub/sub messaging, allowing you to choose the best backend for your needs.

## Quick Start

### Default Configuration (Memory Adapters)

By default, Amber uses in-memory adapters that work out-of-the-box with no external dependencies:

```yaml
# config/environments/development.yml
session:
  key: "myapp.session"
  store: "signed_cookie"
  expires: 3600
  adapter: "memory"       # Default in-memory session storage

pubsub:
  adapter: "memory"       # Default in-memory pub/sub messaging
```

This configuration provides:
- ✅ **Zero dependencies** - no Redis, database, or external services required
- ✅ **Fast performance** - everything runs in process memory
- ✅ **Perfect for development** - simple setup and testing
- ⚠️ **Single process only** - data is not shared across server instances

## Session Adapters

### Memory Session Adapter (Default)

The built-in memory adapter stores session data in process memory with automatic expiration.

```yaml
session:
  adapter: "memory"
  expires: 3600  # Session TTL in seconds
```

**Features:**
- Thread-safe using mutexes
- Automatic cleanup of expired sessions
- Atomic batch operations
- No external dependencies

**Use cases:**
- Development and testing
- Single-server deployments
- Applications that don't require session persistence

### Database Session Adapter (Custom)

Store sessions in your database for persistence and distribution across multiple servers.

#### 1. Create the adapter:

```crystal
# src/adapters/database_session_adapter.cr
require "db"

class DatabaseSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@db : DB::Database)
    ensure_sessions_table_exists
  end

  def get(session_id : String, key : String) : String?
    @db.query_one?(
      "SELECT value FROM sessions WHERE session_id = ? AND key = ? AND (expires_at IS NULL OR expires_at > ?)", 
      session_id, key, Time.utc, as: String
    )
  end

  def set(session_id : String, key : String, value : String) : Nil
    @db.exec(
      "INSERT OR REPLACE INTO sessions (session_id, key, value, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
      session_id, key, value, Time.utc, Time.utc
    )
  end

  def delete(session_id : String, key : String) : Nil
    @db.exec("DELETE FROM sessions WHERE session_id = ? AND key = ?", session_id, key)
  end

  def destroy(session_id : String) : Nil
    @db.exec("DELETE FROM sessions WHERE session_id = ?", session_id)
  end

  def exists?(session_id : String) : Bool
    @db.query_one("SELECT COUNT(*) FROM sessions WHERE session_id = ?", session_id, as: Int32) > 0
  end

  def keys(session_id : String) : Array(String)
    @db.query_all("SELECT key FROM sessions WHERE session_id = ?", session_id, as: String)
  end

  def values(session_id : String) : Array(String)
    @db.query_all("SELECT value FROM sessions WHERE session_id = ?", session_id, as: String)
  end

  def to_hash(session_id : String) : Hash(String, String)
    result = Hash(String, String).new
    @db.query_each("SELECT key, value FROM sessions WHERE session_id = ?", session_id) do |rs|
      result[rs.read(String)] = rs.read(String)
    end
    result
  end

  def empty?(session_id : String) : Bool
    @db.query_one("SELECT COUNT(*) FROM sessions WHERE session_id = ?", session_id, as: Int32) == 0
  end

  def expire(session_id : String, seconds : Int32) : Nil
    expires_at = Time.utc + seconds.seconds
    @db.exec("UPDATE sessions SET expires_at = ? WHERE session_id = ?", expires_at, session_id)
  end

  def batch_set(session_id : String, data : Hash(String, String)) : Nil
    @db.transaction do |tx|
      data.each do |key, value|
        tx.connection.exec(
          "INSERT OR REPLACE INTO sessions (session_id, key, value, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
          session_id, key, value, Time.utc, Time.utc
        )
      end
    end
  end

  private def ensure_sessions_table_exists
    @db.exec <<-SQL
      CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        expires_at DATETIME,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL,
        UNIQUE(session_id, key)
      )
    SQL
    
    @db.exec "CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id)"
    @db.exec "CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at)"
  end
end
```

#### 2. Register the adapter:

```crystal
# config/application.cr
Amber::Adapters::AdapterFactory.register_session_adapter("database") do
  DatabaseSessionAdapter.new(Amber.settings.database)
end
```

#### 3. Configure in environment:

```yaml
# config/environments/production.yml
session:
  adapter: "database"
  expires: 7200
```

### Redis Session Adapter (Custom)

For high-performance session storage with Redis:

#### 1. Create the adapter:

```crystal
# src/adapters/redis_session_adapter.cr
require "redis"

class RedisSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@redis : Redis)
  end

  def get(session_id : String, key : String) : String?
    @redis.hget(session_id, key)
  end

  def set(session_id : String, key : String, value : String) : Nil
    @redis.hset(session_id, key, value)
  end

  def delete(session_id : String, key : String) : Nil
    @redis.hdel(session_id, key)
  end

  def destroy(session_id : String) : Nil
    @redis.del(session_id)
  end

  def exists?(session_id : String) : Bool
    @redis.exists(session_id) > 0
  end

  def keys(session_id : String) : Array(String)
    @redis.hkeys(session_id)
  end

  def values(session_id : String) : Array(String)
    @redis.hvals(session_id)
  end

  def to_hash(session_id : String) : Hash(String, String)
    @redis.hgetall(session_id)
  end

  def empty?(session_id : String) : Bool
    @redis.hlen(session_id) == 0
  end

  def expire(session_id : String, seconds : Int32) : Nil
    @redis.expire(session_id, seconds)
  end

  def batch_set(session_id : String, data : Hash(String, String)) : Nil
    @redis.hmset(session_id, data)
  end
end
```

#### 2. Register and configure:

```crystal
# config/application.cr
Amber::Adapters::AdapterFactory.register_session_adapter("redis") do
  redis = Redis.new(url: ENV["REDIS_URL"])
  RedisSessionAdapter.new(redis)
end
```

```yaml
# config/environments/production.yml
session:
  adapter: "redis"
  expires: 7200
```

## Pub/Sub Adapters

### Memory Pub/Sub Adapter (Default)

The built-in memory adapter handles pub/sub messaging within a single process.

```yaml
pubsub:
  adapter: "memory"
```

**Features:**
- Asynchronous message delivery using fibers
- Topic-based subscription management
- Error resilient - one failing subscriber doesn't break others
- Perfect for single-server WebSocket applications

**Use cases:**
- Development and testing
- Single-server WebSocket applications
- Chat applications with limited scale

### Redis Pub/Sub Adapter (Custom)

For distributed WebSocket applications across multiple servers:

#### 1. Create the adapter:

```crystal
# src/adapters/redis_pubsub_adapter.cr
require "redis"

class RedisPubSubAdapter < Amber::Adapters::PubSubAdapter
  def initialize(@redis : Redis)
    @subscriptions = Hash(String, (String, JSON::Any) -> Nil).new
    @subscriber = Redis.new(url: @redis.url)
    @closed = false
    spawn { listen_for_messages }
  end

  def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
    return if @closed
    
    # Include sender_id in the message for proper routing
    msg_with_sender = {
      "sender_id" => sender_id,
      "message" => message
    }
    
    @redis.publish(topic, msg_with_sender.to_json)
  end

  def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
    @subscriptions[topic] = block
    @subscriber.subscribe(topic) unless @closed
  end

  def unsubscribe(topic : String) : Nil
    @subscriptions.delete(topic)
    @subscriber.unsubscribe(topic) unless @closed
  end

  def unsubscribe_all : Nil
    @subscriptions.clear
    @subscriber.unsubscribe unless @closed
  end

  def close : Nil
    @closed = true
    @subscriber.close
    @redis.close
  end

  private def listen_for_messages
    @subscriber.subscribe do |on|
      on.message do |channel, message|
        next if @closed
        
        if callback = @subscriptions[channel]?
          begin
            parsed = JSON.parse(message)
            sender_id = parsed["sender_id"].as_s
            msg = parsed["message"]
            callback.call(sender_id, msg)
          rescue JSON::ParseException
            # Handle malformed messages
          end
        end
      end
    end
  rescue IO::Error
    # Handle connection errors gracefully
  end
end
```

#### 2. Register and configure:

```crystal
# config/application.cr
Amber::Adapters::AdapterFactory.register_pubsub_adapter("redis") do
  redis = Redis.new(url: ENV["REDIS_URL"])
  RedisPubSubAdapter.new(redis)
end
```

```yaml
# config/environments/production.yml
pubsub:
  adapter: "redis"
```

## Environment-Specific Configuration

### Development Environment

```yaml
# config/environments/development.yml
session:
  key: "myapp.session"
  store: "signed_cookie"
  expires: 3600
  adapter: "memory"        # Fast, no dependencies

pubsub:
  adapter: "memory"        # Simple WebSocket testing
```

### Testing Environment

```yaml
# config/environments/test.yml
session:
  key: "myapp.test.session"
  store: "signed_cookie"
  expires: 300             # Short-lived for tests
  adapter: "memory"        # Isolated test sessions

pubsub:
  adapter: "memory"        # Predictable test behavior
```

### Production Environment

```yaml
# config/environments/production.yml
session:
  key: "myapp.session"
  store: "signed_cookie"
  expires: 7200            # 2 hours
  adapter: "redis"         # Persistent, scalable

pubsub:
  adapter: "redis"         # Multi-server WebSocket support
```

## Advanced Configuration

### Multiple Adapter Types

You can use different adapters for different purposes:

```crystal
# config/application.cr

# Fast Redis for sessions
Amber::Adapters::AdapterFactory.register_session_adapter("redis") do
  Redis.new(url: ENV["REDIS_URL"])
end

# Database for audit logs
Amber::Adapters::AdapterFactory.register_session_adapter("audit_db") do
  DatabaseSessionAdapter.new(audit_database)
end

# Message queue for pub/sub
Amber::Adapters::AdapterFactory.register_pubsub_adapter("rabbitmq") do
  RabbitMQPubSubAdapter.new(ENV["RABBITMQ_URL"])
end
```

### Conditional Adapter Registration

```crystal
# config/application.cr

# Use Redis in production, memory in development
if Amber.env.production?
  Amber::Adapters::AdapterFactory.register_session_adapter("redis") do
    Redis.new(url: ENV["REDIS_URL"])
  end
  
  Amber::Adapters::AdapterFactory.register_pubsub_adapter("redis") do
    Redis.new(url: ENV["REDIS_URL"])
  end
end

# Always register database adapter as fallback
Amber::Adapters::AdapterFactory.register_session_adapter("database") do
  DatabaseSessionAdapter.new(Amber.settings.database)
end
```

### Health Checks and Monitoring

Implement health checks for your custom adapters:

```crystal
class RedisSessionAdapter < Amber::Adapters::SessionAdapter
  # ... other methods ...

  def healthy? : Bool
    @redis.ping == "PONG"
  rescue
    false
  end
  
  def stats : Hash(String, Int32)
    {
      "connected" => @redis.ping == "PONG" ? 1 : 0,
      "memory_usage" => @redis.info("memory")["used_memory"].to_i,
      "active_sessions" => @redis.dbsize
    }
  rescue
    {"connected" => 0, "memory_usage" => 0, "active_sessions" => 0}
  end
end
```

## Caching Strategies

### Session Caching

Implement multi-tier session storage for optimal performance:

```crystal
class CachedSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@memory : MemorySessionAdapter, @persistent : DatabaseSessionAdapter)
  end

  def get(session_id : String, key : String) : String?
    # Try memory first, fallback to persistent storage
    @memory.get(session_id, key) || begin
      value = @persistent.get(session_id, key)
      @memory.set(session_id, key, value) if value
      value
    end
  end

  def set(session_id : String, key : String, value : String) : Nil
    # Write to both memory and persistent storage
    @memory.set(session_id, key, value)
    @persistent.set(session_id, key, value)
  end

  # ... implement other methods with similar caching logic
end
```

### Pub/Sub Message Caching

Cache recent messages for new subscribers:

```crystal
class CachedPubSubAdapter < Amber::Adapters::PubSubAdapter
  def initialize(@redis : Redis, @cache_size : Int32 = 100)
    @message_cache = Hash(String, Array(JSON::Any)).new
  end

  def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
    # Cache the message
    @message_cache[topic] ||= Array(JSON::Any).new
    @message_cache[topic].push(message)
    @message_cache[topic] = @message_cache[topic].last(@cache_size)
    
    # Publish normally
    super(topic, sender_id, message)
  end

  def subscribe_with_history(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
    # Send cached messages first
    if cached_messages = @message_cache[topic]?
      cached_messages.each { |msg| block.call("system", msg) }
    end
    
    # Then subscribe for new messages
    subscribe(topic, &block)
  end
end
```

## Performance Considerations

### Session Performance Tips

1. **Use appropriate TTLs**: Set reasonable session expiration times
2. **Batch operations**: Use `batch_set` for multiple session updates
3. **Connection pooling**: Share database/Redis connections when possible
4. **Async operations**: Use fibers for non-blocking I/O

### Pub/Sub Performance Tips

1. **Topic design**: Use hierarchical topic names (`chat:room:123`)
2. **Message size**: Keep messages small and serialize efficiently
3. **Subscriber limits**: Monitor subscriber counts per topic
4. **Error handling**: Implement retry logic for failed deliveries

## Troubleshooting

### Common Issues

1. **"Unknown adapter" errors**: Ensure adapters are registered before use
2. **Connection timeouts**: Check network connectivity and credentials
3. **Memory leaks**: Monitor session cleanup and subscriber management
4. **Performance issues**: Profile adapter operations and optimize queries

### Debug Mode

Enable debug logging for adapters:

```crystal
# config/application.cr
if Amber.env.development?
  Amber::Adapters::AdapterFactory.register_session_adapter("debug_memory") do
    adapter = MemorySessionAdapter.new
    DebugSessionAdapter.new(adapter)  # Wrapper that logs all operations
  end
end
```

## Migration Guide

### From Legacy Redis

If migrating from the old Redis-coupled system:

1. **Remove Redis dependency** from `shard.yml`
2. **Update configuration** to use new adapter format
3. **Register Redis adapter** if still needed
4. **Test thoroughly** with new adapter system

### Gradual Migration

Implement a migration adapter that supports both old and new systems:

```crystal
class MigrationSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@old_store : OldRedisStore, @new_adapter : SessionAdapter)
  end

  def get(session_id : String, key : String) : String?
    # Try new adapter first, fallback to old store
    @new_adapter.get(session_id, key) || @old_store.get(session_id, key)
  end

  def set(session_id : String, key : String, value : String) : Nil
    # Write to both systems during migration
    @new_adapter.set(session_id, key, value)
    @old_store.set(session_id, key, value)
  end
  
  # ... implement migration logic for other methods
end
```

This allows for gradual migration and rollback capability during the transition period.

## Summary

The Amber adapter system provides:

- **Flexibility**: Choose the right backend for your needs
- **Scalability**: Easy to switch from development to production setups  
- **Testability**: Memory adapters make testing simple and fast
- **Extensibility**: Implement custom adapters for any backend
- **Performance**: Optimize adapters for your specific use case

The adapter pattern ensures your application can grow and adapt without being locked into any specific technology stack. 