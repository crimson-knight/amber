# Query string parser for URL parameters
module Amber::Schema::Parser
  class QueryParser < Base
    def parse(value : JSON::Any) : JSON::Any
      # QueryParser operates on the full params hash, not individual values
      value
    end

    def can_parse?(value : JSON::Any) : Bool
      value.as_h?
    end

    # Parse query string into nested hash structure
    def self.parse_query_string(query_string : String) : Hash(String, JSON::Any)
      params = HTTP::Params.parse(query_string)
      parse_params_to_nested(params)
    end

    # Convert flat params to nested structure
    def self.parse_params_to_nested(params : HTTP::Params | Hash(String, String)) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any

      case params
      when HTTP::Params
        params.each do |key, value|
          set_nested_value(result, key, value)
        end
      when Hash(String, String)
        params.each do |key, value|
          set_nested_value(result, key, value)
        end
      end

      result
    end

    # Handle nested parameter keys like user[profile][name]
    private def self.set_nested_value(hash : Hash(String, JSON::Any), key : String, value : String)
      # Handle array notation
      if key.ends_with?("[]")
        base_key = key[0..-3]
        hash[base_key] ||= JSON::Any.new([] of JSON::Any)
        if array = hash[base_key].as_a?
          array << parse_value(value)
        end
        return
      end

      # Handle nested object notation
      parts = key.split(/[\[\]]/).reject(&.empty?)
      
      if parts.size == 1
        # Simple key
        hash[key] = parse_value(value)
      else
        # Nested key
        current = hash
        parts[0..-2].each do |part|
          current[part] ||= JSON::Any.new({} of String => JSON::Any)
          if nested = current[part].as_h?
            current = nested
          else
            # Type conflict, skip this parameter
            return
          end
        end
        current[parts.last] = parse_value(value)
      end
    end

    # Try to parse value as JSON, number, or boolean
    private def self.parse_value(value : String) : JSON::Any
      # Try boolean
      return JSON::Any.new(true) if value == "true"
      return JSON::Any.new(false) if value == "false"

      # Try number
      if int_value = value.to_i64?
        return JSON::Any.new(int_value)
      end
      
      if float_value = value.to_f64?
        return JSON::Any.new(float_value)
      end

      # Try JSON
      if value.starts_with?("{") || value.starts_with?("[")
        begin
          return JSON.parse(value)
        rescue
          # Not valid JSON, treat as string
        end
      end

      # Default to string
      JSON::Any.new(value)
    end

    # Flatten nested hash to query string
    def self.to_query_string(data : Hash(String, JSON::Any), prefix : String? = nil) : String
      params = [] of String

      data.each do |key, value|
        full_key = prefix ? "#{prefix}[#{key}]" : key
        
        case value.raw
        when Hash
          if nested = value.as_h?
            params << to_query_string(nested, full_key)
          end
        when Array
          if array = value.as_a?
            array.each do |item|
              params << "#{full_key}[]=#{URI.encode_www_form(item.to_s)}"
            end
          end
        else
          params << "#{full_key}=#{URI.encode_www_form(value.to_s)}"
        end
      end

      params.join("&")
    end
  end
end