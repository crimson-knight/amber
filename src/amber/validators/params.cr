module Amber::Validators
  # Holds a validation error message
  record Error, param : String, value : String?, message : String

  # This struct holds the validation rules to be performed
  class BaseRule
    getter predicate : (String -> Bool)
    getter field : String
    getter value : String?
    getter present : Bool

    def initialize(field : String | Symbol, @msg : String?, @allow_blank : Bool = true)
      @field = field.to_s
      @present = false
      @predicate = ->(_s : String) { true }
    end

    def initialize(field : String | Symbol, @msg : String?, @allow_blank : Bool = true, &block : String -> Bool)
      @field = field.to_s
      @present = false
      @predicate = block
    end

    def apply(params : Amber::Router::Params)
      raise Exceptions::Validator::InvalidParam.new(@field) unless params.has_key? @field
      call_predicate(params)
    end

    def error
      Error.new @field, @value.to_s, error_message
    end

    private def call_predicate(params : Amber::Router::Params)
      @value = params[@field]
      @present = params.has_key?(@field)

      return true if params[@field].blank? && @allow_blank

      @predicate.call params[@field] unless @predicate.nil?
    end

    private def error_message
      @msg || "Field #{@field} is required"
    end
  end

  # RequiredRule returns false if key is missing or value is blank or if block returns false.
  class RequiredRule < BaseRule
    def apply(params : Amber::Router::Params)
      return false unless params.has_key?(@field)
      return false if params[@field].blank? && !@allow_blank
      call_predicate(params)
    end
  end

  # OptionalRule only validates (evaluates block) if the key is present and the value is not blank (see call_predicate).
  class OptionalRule < BaseRule
    def apply(params : Amber::Router::Params)
      return true if !params.has_key?(@field)
      call_predicate(params)
    end
  end

  record ValidationBuilder, _validator : Params do
    def required(param : String | Symbol, msg : String? = nil, allow_blank = false)
      _validator.add_rule RequiredRule.new(param, msg, allow_blank)
    end

    def required(param : String | Symbol, msg : String? = nil, allow_blank = false, &b : String -> Bool)
      _validator.add_rule RequiredRule.new(param, msg, allow_blank, &b)
    end

    def optional(param : String | Symbol, msg : String? = nil, allow_blank = true)
      _validator.add_rule OptionalRule.new(param, msg, allow_blank)
    end

    def optional(param : String | Symbol, msg : String? = nil, allow_blank = true, &b : String -> Bool)
      _validator.add_rule OptionalRule.new(param, msg, allow_blank, &b)
    end
  end

  class Params
    getter raw_params : Amber::Router::Params
    @rules : Array(BaseRule)?
    @params : Hash(String, String?)?
    @errors : Array(Error)?

    def initialize(@raw_params); end

    def rules
      @rules ||= [] of BaseRule
    end

    def params
      @params ||= {} of String => String?
    end

    def errors
      @errors ||= [] of Error
    end

    @[AlwaysInline]
    def [](key : String | Symbol)
      @raw_params[key]
    end

    @[AlwaysInline]
    def []?(key : String | Symbol)
      @raw_params[key]?
    end

    @[AlwaysInline]
    def has_key?(key : String | Symbol) : Bool
      @raw_params.has_key?(key)
    end

    @[AlwaysInline]
    def fetch_all(key : String | Symbol)
      @raw_params.fetch_all(key)
    end

    @[AlwaysInline]
    def json(key : String | Symbol)
      @raw_params.json(key)
    end

    # This will allow params to respond to HTTP::Params methods.
    # For example: [], []?, add, delete, each, fetch, etc.
    forward_missing_to @raw_params

    # Setups validation rules to be performed
    #
    # ```
    # params.validation do
    #   required(:email) { |p| p.url? }
    #   required(:age, UInt32)
    # end
    # ```
    def validation(&)
      with ValidationBuilder.new(self) yield
      self
    end

    # Input must be valid otherwise raises error, if valid returns a hash
    # of validated params Otherwise raises a Validator::ValidationFailed error
    # messages contain errors.
    #
    # ```
    # user = User.new params.validate!
    # ```
    def validate!
      return params if valid?
      raise Amber::Exceptions::Validator::ValidationFailed.new errors
    end

    # Returns True or false whether the validation passed
    #
    # ```
    # unless params.valid?
    #   response.puts {errors: params.errors}.to_json
    #   response.status_code 400
    # end
    # ```
    def valid?
      current_errors = errors
      current_params = params
      current_errors.clear
      current_params.clear

      current_rules = @rules
      return true unless current_rules && !current_rules.empty?

      current_rules.each do |rule|
        unless rule.apply(raw_params)
          current_errors << rule.error
        end

        current_params[rule.field] = rule.value if rule.present
      end

      current_errors.empty?
    end

    # Validates each field with a given set of predicates returns true if the
    # field is valid otherwise returns false
    #
    # ```
    # required(:email) { |p| p.email? & p.size.between? 1..10 }
    # ```
    def add_rule(rule : BaseRule)
      rules << rule
    end

    def to_h
      @params || ({} of String => String?)
    end

    def to_unsafe_h
      @raw_params.to_h
    end
  end
end
