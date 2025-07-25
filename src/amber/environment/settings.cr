require "yaml"

module Amber::Environment
  class Settings
    include YAML::Serializable
    
    alias SettingValue = String | Int32 | Bool | Nil

    struct SMTPSettings
      include YAML::Serializable
      
      property host : String = "127.0.0.1"
      property port : Int32 = 1025
      property enabled : Bool = false
      property username : String = ""
      property password : String = ""
      property tls : Bool = false
      
      def initialize
      end
      
      def self.from_hash(settings = {} of String => SettingValue) : self
        i = new
        settings.each do |key, value|
          case key
          when "host" then i.host = value.as(String) if value.is_a?(String)
          when "port" then i.port = value.as(Int32) if value.is_a?(Int32)
          when "enabled" then i.enabled = value.as(Bool) if value.is_a?(Bool)
          when "username" then i.username = value.as(String) if value.is_a?(String)
          when "password" then i.password = value.as(String) if value.is_a?(String)
          when "tls" then i.tls = value.as(Bool) if value.is_a?(Bool)
          end
        end
        i
      end
    end
    
    property database_url : String = ""
    property host : String = "localhost"
    property name : String = "Amber_App"
    property port : Int32 = 3000
    property port_reuse : Bool = true
    property process_count : Int32 = 1
    property secret_key_base : String = ""
    property secrets : Hash(String, String) = {} of String => String
    property ssl_key_file : String?
    property ssl_cert_file : String?
    
    @[YAML::Field(key: "logging")]
    property logging_config : Hash(String, String | Bool | Array(String)) = Logging::DEFAULTS
    
    @[YAML::Field(key: "auto_reload")]
    property? auto_reload : Bool = false
    
    @[YAML::Field(key: "session")]
    property session_config : Hash(String, Int32 | String) = {"key" => "amber.session", "store" => "signed_cookie", "expires" => 0, "adapter" => "memory"}
    
    # Backward compatibility setter
    def session=(value : Hash(String, Int32 | String))
      @session_config = value
    end
    
    @[YAML::Field(key: "pubsub")]
    property pubsub_config : Hash(String, String) = {"adapter" => "memory"}
    
    # Backward compatibility setter
    def pubsub=(value : Hash(String, String))
      @pubsub_config = value
    end
    
    property smtp : SMTPSettings = SMTPSettings.new
    
    property pipes : Hash(String, Hash(String, Hash(String, String | Int32 | Bool | Nil))) = {"static" => {"headers" => {} of String => SettingValue}}

    def initialize
      @secret_key_base = Random::Secure.urlsafe_base64(32)
    end

    def session
      {
        :key     => @session_config["key"].to_s,
        :store   => session_store,
        :expires => @session_config["expires"].to_i,
        :adapter => @session_config["adapter"]?.try(&.to_s) || "memory",
      }
    end

    def pubsub
      {
        :adapter => @pubsub_config["adapter"]?.try(&.to_s) || "memory",
      }
    end

    def session_store
      case @session_config["store"].to_s
      when "signed_cookie" then :signed_cookie
      when "redis"         then :redis
      else
        :encrypted_cookie
      end
    end

    @_logging : Logging?
    def logging
      @_logging ||= Logging.new(@logging_config)
    end
  end
end