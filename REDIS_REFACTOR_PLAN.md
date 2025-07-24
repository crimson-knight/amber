# Amber Framework Redis Dependency Removal - **COMPLETED** ✅

This document outlines the successful removal of tight coupling with Redis from the Amber framework and implementation of an abstracted adapter interface.

## 🎯 **Refactor Status: COMPLETE**

**All phases have been successfully implemented:**

✅ **Phase 1**: Design abstract adapter interfaces  
✅ **Phase 2**: Implement in-memory adapters as default implementations  
✅ **Phase 3**: Update configuration system to support pluggable adapters  
✅ **Phase 4**: Remove direct Redis requires and make Redis optional  
✅ **Phase 5**: Update documentation and templates  

---

## 🔧 **How to Use the New Adapter System**

### **Configuration**

#### **Session Adapters**

```yaml
# config/environments/development.yml
session:
  key: "myapp.session"
  store: "signed_cookie"  # Legacy cookie setting
  expires: 3600
  adapter: "memory"       # New: Choose your session adapter

# Available adapters:
# - "memory" (default, always available)
# - "redis" (available when redis shard is installed)
```

#### **PubSub Adapters** 

```yaml
# config/environments/development.yml
pubsub:
  adapter: "memory"       # New: Choose your pub/sub adapter

# Available adapters:
# - "memory" (default, always available)  
# - "redis" (available when redis shard is installed)
```

### **Using Redis Adapters**

#### **1. Add Redis to your shard.yml**

```yaml
# shard.yml
dependencies:
  redis:
    github: stefanwille/crystal-redis
    version: "~> 2.8.0"
```

#### **2. Compile with Redis flag**

```bash
# During development
crystal build src/your_app.cr -Dredis

# For production
crystal build src/your_app.cr --release -Dredis
```

#### **3. Configure Redis adapters**

```yaml
# config/environments/production.yml
session:
  adapter: "redis"
  key: "myapp.session"
  expires: 3600

pubsub:
  adapter: "redis"
```

### **Custom Adapters**

#### **Creating a Custom Session Adapter**

```crystal
# src/my_custom_session_adapter.cr
class MyCustomSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@database_connection : MyDB::Connection)
  end

  def get(session_id : String, key : String) : String?
    @database_connection.query_one?("SELECT value FROM sessions WHERE session_id = ? AND key = ?", session_id, key, as: String)
  end

  def set(session_id : String, key : String, value : String) : Nil
    @database_connection.exec("INSERT OR REPLACE INTO sessions (session_id, key, value) VALUES (?, ?, ?)", session_id, key, value)
  end

  # ... implement other abstract methods
end

# Register your adapter
Amber::Adapters::AdapterFactory.register_session_adapter("database") do
  MyCustomSessionAdapter.new(MyDB.connection)
end
```

#### **Creating a Custom PubSub Adapter**

```crystal  
# src/my_custom_pubsub_adapter.cr
class MyCustomPubSubAdapter < Amber::Adapters::PubSubAdapter
  def initialize(@message_queue : MyMQ::Client)
  end

  def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
    @message_queue.publish(topic, {sender_id: sender_id, message: message}.to_json)
  end

  def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
    @message_queue.subscribe(topic) do |msg|
      data = JSON.parse(msg)
      block.call(data["sender_id"].as_s, data["message"])
    end
  end

  # ... implement other abstract methods
end

# Register your adapter
Amber::Adapters::AdapterFactory.register_pubsub_adapter("messagequeue") do
  MyCustomPubSubAdapter.new(MyMQ.client)
end
```

---

## 📖 **Migration Guide**

### **From Legacy Redis Sessions**

#### **Before (Legacy)**
```yaml
# Only worked with Redis
session:
  store: "redis"
  key: "myapp.session"
  expires: 3600
```

#### **After (New System)**
```yaml
# Works with any adapter
session:
  adapter: "redis"      # or "memory" or your custom adapter
  key: "myapp.session"
  expires: 3600
```

### **From Legacy WebSocket PubSub**

#### **Before (Legacy)**
```crystal
# Hardcoded Redis usage
Amber::Server.configure do |settings|
  settings.pubsub_adapter = Amber::WebSockets::Adapters::RedisAdapter
end
```

#### **After (New System)**
```yaml
# Configuration-driven approach
pubsub:
  adapter: "redis"  # or "memory" or your custom adapter
```

---

## 🚀 **Benefits Achieved**

### **✅ Flexibility**
- Choose the best storage backend for your needs
- Switch adapters without code changes
- Support for custom implementations

### **✅ No Hard Dependencies**
- Framework works without Redis installed
- Redis is now truly optional
- Reduced deployment complexity

### **✅ Better Testing**
- In-memory adapters for fast testing
- No external dependencies in test suite
- Easier CI/CD pipelines

### **✅ Production Ready**
- All existing Redis functionality preserved
- Backward compatibility maintained
- Performance optimizations retained

---

## 🏗️ **Architecture Overview**

### **Core Interfaces**

```
Amber::Adapters::SessionAdapter (Abstract)
├── MemorySessionAdapter (Built-in, Default)
└── RedisSessionAdapter (Conditional, when -Dredis)

Amber::Adapters::PubSubAdapter (Abstract)  
├── MemoryPubSubAdapter (Built-in, Default)
└── RedisPubSubAdapter (Conditional, when -Dredis)

Amber::Adapters::AdapterFactory (Registry)
└── Manages adapter registration and instantiation
```

### **Configuration Flow**

```
1. Application loads configuration (YAML)
2. Settings parse adapter names from config
3. AdapterFactory creates adapter instances
4. Framework uses adapters through abstract interfaces
5. Zero knowledge of concrete implementations
```

---

## 🧪 **Testing**

### **All Adapters Tested**
```bash
# Run all adapter tests
crystal spec spec/amber/adapters/

# Test specific adapters
crystal spec spec/amber/adapters/memory_session_adapter_spec.cr
crystal spec spec/amber/adapters/memory_pubsub_adapter_spec.cr
crystal spec spec/amber/adapters/adapter_factory_spec.cr
```

### **Test Both Modes**
```bash
# Test without Redis
crystal build src/amber.cr --no-codegen

# Test with Redis  
crystal build src/amber.cr --no-codegen -Dredis
```

---

## ⚠️ **Important Notes**

### **Compilation Flags**
- **Without `-Dredis`**: Only memory adapters available
- **With `-Dredis`**: Both memory and Redis adapters available

### **Legacy Support**
- Old Redis session stores still work but are deprecated
- Old WebSocket Redis adapters still work but are deprecated  
- Migration to new system recommended for new projects

### **Environment Variables**
- `REDIS_URL` still used by Redis adapters when available
- Falls back to `"redis://localhost:6379"` if not set

---

## 📝 **Files Modified/Created**

### **New Adapter System**
- `src/amber/adapters/session_adapter.cr` - Abstract session interface
- `src/amber/adapters/pubsub_adapter.cr` - Abstract pub/sub interface
- `src/amber/adapters/memory_session_adapter.cr` - Memory session implementation
- `src/amber/adapters/memory_pubsub_adapter.cr` - Memory pub/sub implementation
- `src/amber/adapters/redis_session_adapter.cr` - Redis session implementation (conditional)
- `src/amber/adapters/redis_pubsub_adapter.cr` - Redis pub/sub implementation (conditional)
- `src/amber/adapters/adapter_factory.cr` - Adapter registration system
- `src/amber/adapters.cr` - Module entry point

### **Configuration Updates**
- `src/amber/environment/settings.cr` - Added adapter configuration support
- `src/amber/router/session/adapter_session_store.cr` - New adapter-based session store
- `src/amber/router/session/session_store.cr` - Updated to support adapters
- `src/amber/server/server.cr` - Added adapter initialization

### **Conditional Redis Support**
- `src/amber.cr` - Removed hard Redis require
- `src/amber/router/session/redis_store.cr` - Made conditional
- `src/amber/websockets/adapters/redis.cr` - Made conditional
- `src/amber/websockets/channel.cr` - Made Redis references conditional

### **Comprehensive Tests**
- `spec/amber/adapters/adapter_interfaces_spec.cr`
- `spec/amber/adapters/memory_session_adapter_spec.cr`
- `spec/amber/adapters/memory_pubsub_adapter_spec.cr`
- `spec/amber/adapters/adapter_factory_spec.cr`
- `spec/amber/adapters/adapter_session_store_spec.cr`

---

## 🎉 **Refactor Complete!**

The Amber framework has been successfully refactored to remove direct Redis dependency while maintaining full backward compatibility and adding powerful new adapter capabilities. Users can now choose the best storage backend for their specific needs, from simple in-memory solutions to distributed Redis deployments and everything in between. 