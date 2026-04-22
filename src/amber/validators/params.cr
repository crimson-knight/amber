module Amber::Validators
  enum RuleKind
    Required
    Optional
  end

  record CompiledRule,
    kind : RuleKind,
    field : String,
    msg : String?,
    allow_blank : Bool,
    predicate : (String -> Bool)?

  class Definition
    getter rules : Array(CompiledRule)

    def initialize(@rules : Array(CompiledRule))
    end
  end

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

  record DefinitionBuilder, _rules : Array(CompiledRule) do
    def required(param : String | Symbol, msg : String? = nil, allow_blank = false)
      _rules << CompiledRule.new(RuleKind::Required, param.to_s, msg, allow_blank, nil)
    end

    def required(param : String | Symbol, msg : String? = nil, allow_blank = false, &b : String -> Bool)
      _rules << CompiledRule.new(RuleKind::Required, param.to_s, msg, allow_blank, b)
    end

    def optional(param : String | Symbol, msg : String? = nil, allow_blank = true)
      _rules << CompiledRule.new(RuleKind::Optional, param.to_s, msg, allow_blank, nil)
    end

    def optional(param : String | Symbol, msg : String? = nil, allow_blank = true, &b : String -> Bool)
      _rules << CompiledRule.new(RuleKind::Optional, param.to_s, msg, allow_blank, b)
    end
  end

  class Params
    getter raw_params : Amber::Router::Params
    @rules : Array(BaseRule)?
    @params : Hash(String, String?)?
    @errors : Array(Error)?
    @definition : Definition?

    def initialize(@raw_params); end

    def self.define(&)
      builder = DefinitionBuilder.new([] of CompiledRule)
      with builder yield
      Definition.new(builder._rules)
    end

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
    def [](key : String)
      @raw_params[key]
    end

    @[AlwaysInline]
    def [](key : Symbol)
      @raw_params[key]
    end

    @[AlwaysInline]
    def []?(key : String)
      @raw_params[key]?
    end

    @[AlwaysInline]
    def []?(key : Symbol)
      @raw_params[key]?
    end

    @[AlwaysInline]
    def has_key?(key : String) : Bool
      @raw_params.has_key?(key)
    end

    @[AlwaysInline]
    def has_key?(key : Symbol) : Bool
      @raw_params.has_key?(key)
    end

    @[AlwaysInline]
    def fetch_all(key : String)
      @raw_params.fetch_all(key)
    end

    @[AlwaysInline]
    def fetch_all(key : Symbol)
      @raw_params.fetch_all(key)
    end

    @[AlwaysInline]
    def json(key : String)
      @raw_params.json(key)
    end

    @[AlwaysInline]
    def json(key : Symbol)
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

    def validation(definition : Definition)
      @definition = definition
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

      current_definition = @definition
      current_rules = @rules
      has_definition = !current_definition.nil? && !current_definition.rules.empty?
      has_dynamic_rules = !current_rules.nil? && !current_rules.empty?
      return true unless has_definition || has_dynamic_rules

      if current_definition
        current_definition.rules.each do |rule|
          apply_compiled_rule(rule, current_params, current_errors)
        end
      end

      if current_rules
        current_rules.each do |rule|
          unless rule.apply(raw_params)
            current_errors << rule.error
          end

          current_params[rule.field] = rule.value if rule.present
        end
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

    private def apply_compiled_rule(rule : CompiledRule, current_params : Hash(String, String?), current_errors : Array(Error))
      value = raw_params[rule.field]?

      case rule.kind
      when .required?
        return append_missing_error(rule, current_errors) unless value
        return append_blank_error(rule, value, current_errors) if value.blank? && !rule.allow_blank
        current_params[rule.field] = value
        return append_predicate_error(rule, value, current_errors) unless compiled_rule_valid?(rule, value)
      when .optional?
        return unless value
        current_params[rule.field] = value
        return if value.blank? && rule.allow_blank
        return append_predicate_error(rule, value, current_errors) unless compiled_rule_valid?(rule, value)
      end
    end

    private def compiled_rule_valid?(rule : CompiledRule, value : String) : Bool
      return true unless predicate = rule.predicate
      predicate.call(value)
    end

    private def append_missing_error(rule : CompiledRule, current_errors : Array(Error))
      current_errors << Error.new(rule.field, nil, compiled_rule_error_message(rule))
    end

    private def append_blank_error(rule : CompiledRule, value : String, current_errors : Array(Error))
      current_errors << Error.new(rule.field, value, compiled_rule_error_message(rule))
    end

    private def append_predicate_error(rule : CompiledRule, value : String, current_errors : Array(Error))
      current_errors << Error.new(rule.field, value, compiled_rule_error_message(rule))
    end

    private def compiled_rule_error_message(rule : CompiledRule) : String
      rule.msg || "Field #{rule.field} is required"
    end
  end
end
