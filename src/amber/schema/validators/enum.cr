# Enum validation - ensures value is one of allowed values
module Amber::Schema::Validator
  class Enum < Base
    @field_name : String
    @allowed_values : Array(String)

    def initialize(@field_name : String, allowed_values : Array(String) | Array(Int32) | Array(Float64))
      @allowed_values = allowed_values.map(&.to_s)
      if @allowed_values.empty?
        raise ArgumentError.new("Enum validator requires at least one allowed value")
      end
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)

      # Convert JSON::Any to comparable value
      comparable_value = extract_value(value).to_s
      
      unless @allowed_values.includes?(comparable_value)
        allowed_str = @allowed_values.join(", ")
        context.add_error(
          CustomValidationError.new(
            @field_name,
            "Field '#{@field_name}' must be one of: #{allowed_str}",
            "invalid_enum_value"
          )
        )
      end
    end

    private def extract_value(value : JSON::Any)
      case value.raw
      when String
        value.as_s
      when Int
        value.as_i
      when Float
        value.as_f
      when Bool
        value.as_bool
      else
        value.raw
      end
    end
  end
end