# Integrates Schema API with Amber controllers
require "../schema"

module Amber::Controller
  # Extension module that patches Base controller to include Schema API
  module SchemaIntegration
    macro included
      # Include the Schema::ControllerIntegration module
      include Amber::Schema::ControllerIntegration

      @original_params : Amber::Validators::Params?
      @raw_params : Amber::Router::Params?
      @schema_params_wrapper : SchemaParamsWrapper?
      
      # Override the params getter to maintain backward compatibility
      # The original params returns Amber::Validators::Params
      # We'll keep it but also provide access to validated schema data
      @[AlwaysInline]
      protected def original_params : Amber::Validators::Params
        @original_params ||= Amber::Validators::Params.new(raw_params)
      end
      
      # Create an alias for the original params
      {% unless @type.has_method?(:legacy_params) %}
        protected def legacy_params
          original_params
        end
      {% end %}

      def request_data=(value : Hash(String, JSON::Any)?)
        @request_data = value
        @schema_params_wrapper = nil
      end
      
      # Override params to provide a migration path
      @[AlwaysInline]
      protected def params
        # If we have validated schema data, create a wrapper that provides
        # backward compatibility with the old params interface
        if request_data = @request_data
          @schema_params_wrapper ||= SchemaParamsWrapper.new(request_data, raw_params)
        else
          # Fall back to original params behavior
          original_params
        end
      end
      
      # Helper method to access raw params when needed
      @[AlwaysInline]
      protected def raw_params : Amber::Router::Params
        @raw_params ||= context.params
      end
    end
  end
  
  # Wrapper class that provides backward compatibility between Schema API
  # and the existing Amber::Validators::Params interface
  class SchemaParamsWrapper
    getter validated_data : Hash(String, JSON::Any)
    getter raw_params : Amber::Router::Params
    
    def initialize(@validated_data : Hash(String, JSON::Any), @raw_params : Amber::Router::Params)
    end
    
    # Delegate array-like access to validated data first, then raw params
    @[AlwaysInline]
    def [](key : String)
      if json_value = validated_data[key]?
        json_value_to_param_string(json_value)
      else
        raw_params[key]
      end
    end

    @[AlwaysInline]
    def [](key : Symbol)
      self[key.to_s]
    end

    @[AlwaysInline]
    def []?(key : String)
      if json_value = validated_data[key]?
        json_value_to_param_string(json_value)
      else
        raw_params[key]?
      end
    end

    @[AlwaysInline]
    def []?(key : Symbol)
      self[key.to_s]?
    end

    # Check if key exists in either validated data or raw params
    @[AlwaysInline]
    def has_key?(key : String) : Bool
      validated_data.has_key?(key) || raw_params.has_key?(key)
    end

    @[AlwaysInline]
    def has_key?(key : Symbol) : Bool
      key_str = key.to_s
      validated_data.has_key?(key_str) || raw_params.has_key?(key_str)
    end
    
    # Provide access to validation methods for migration
    def validation(&)
      # Create a temporary Amber::Validators::Params for validation
      validator = Amber::Validators::Params.new(raw_params)
      with Amber::Validators::ValidationBuilder.new(validator) yield
      validator
    end

    def validation(definition : Amber::Validators::Definition)
      Amber::Validators::Params.new(raw_params).validation(definition)
    end

    def validation(definition : Amber::Validators::CompiledDefinition)
      Amber::Validators::Params.new(raw_params).validation(definition)
    end
    
    # Convert to hash combining validated and raw data
    def to_h
      result = {} of String => String?
      
      # Start with raw params
      raw_params.to_h.each do |k, v|
        result[k] = v
      end
      
      # Override with validated data
      validated_data.each do |k, v|
        result[k] = json_value_to_h_string(v)
      end
      
      result
    end
    
    # Access to raw unvalidated params
    def to_unsafe_h
      raw_params.to_h
    end

    private def json_value_to_param_string(json_value : JSON::Any) : String
      case json_value.raw
      when String
        json_value.as_s
      when Int64
        json_value.as_i.to_s
      when Float64
        json_value.as_f.to_s
      when Bool
        json_value.as_bool.to_s
      when Nil
        ""
      else
        json_value.to_s
      end
    end

    private def json_value_to_h_string(json_value : JSON::Any) : String?
      case json_value.raw
      when String
        json_value.as_s
      when Int64
        json_value.as_i.to_s
      when Float64
        json_value.as_f.to_s
      when Bool
        json_value.as_bool.to_s
      when Nil
        nil
      else
        json_value.to_s
      end
    end
    
    # Forward missing methods to raw params for full compatibility
    forward_missing_to @raw_params
  end
end

# Patch the Base controller to include Schema integration
class Amber::Controller::Base
  include Amber::Controller::SchemaIntegration
end
