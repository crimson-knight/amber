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

  abstract class ReusableDefinition
    abstract def apply(raw_params : Amber::Router::Params, current_params : Hash(String, String?), current_errors : ErrorBuffer)
    abstract def total_rule_count : Int32
    abstract def direct_rule_count : Int32
    abstract def fallback_rule_count : Int32

    def hybrid? : Bool
      direct_rule_count > 0 && fallback_rule_count > 0
    end
  end

  class Definition < ReusableDefinition
    getter rules : Array(CompiledRule)

    def initialize(@rules : Array(CompiledRule))
    end

    def apply(raw_params : Amber::Router::Params, current_params : Hash(String, String?), current_errors : ErrorBuffer)
      @rules.each do |rule|
        apply_rule(raw_params, rule, current_params, current_errors)
      end
    end

    def total_rule_count : Int32
      @rules.size
    end

    def direct_rule_count : Int32
      0
    end

    def fallback_rule_count : Int32
      @rules.size
    end

    private def apply_rule(raw_params : Amber::Router::Params, rule : CompiledRule, current_params : Hash(String, String?), current_errors : ErrorBuffer)
      value = raw_params[rule.field]?

      case rule.kind
      when .required?
        return append_missing_error(rule, current_errors) unless value
        return append_blank_error(rule, value, current_errors) if value.blank? && !rule.allow_blank
        current_params[rule.field] = value
        return append_predicate_error(rule, value, current_errors) unless rule_valid?(rule, value)
      when .optional?
        return unless value
        current_params[rule.field] = value
        return if value.blank? && rule.allow_blank
        return append_predicate_error(rule, value, current_errors) unless rule_valid?(rule, value)
      end
    end

    private def rule_valid?(rule : CompiledRule, value : String) : Bool
      return true unless predicate = rule.predicate
      predicate.call(value)
    end

    private def append_missing_error(rule : CompiledRule, current_errors : ErrorBuffer)
      current_errors << Error.new(rule.field, nil, rule_error_message(rule))
    end

    private def append_blank_error(rule : CompiledRule, value : String, current_errors : ErrorBuffer)
      current_errors << Error.new(rule.field, value, rule_error_message(rule))
    end

    private def append_predicate_error(rule : CompiledRule, value : String, current_errors : ErrorBuffer)
      current_errors << Error.new(rule.field, value, rule_error_message(rule))
    end

    private def rule_error_message(rule : CompiledRule) : String
      rule.msg || "Field #{rule.field} is required"
    end
  end

  abstract class CompiledDefinition < ReusableDefinition
    @[AlwaysInline]
    protected def apply_required_rule(raw_params : Amber::Router::Params, current_params : Hash(String, String?), current_errors : ErrorBuffer, field : String, msg : String?, allow_blank : Bool)
      if value = raw_params[field]?
        if value.blank? && !allow_blank
          current_errors << Error.new(field, value, rule_error_message(field, msg))
        else
          current_params[field] = value
        end
      else
        current_errors << Error.new(field, nil, rule_error_message(field, msg))
      end
    end

    @[AlwaysInline]
    protected def apply_required_rule(raw_params : Amber::Router::Params, current_params : Hash(String, String?), current_errors : ErrorBuffer, field : String, msg : String?, allow_blank : Bool, &predicate : String -> Bool)
      if value = raw_params[field]?
        if value.blank? && !allow_blank
          current_errors << Error.new(field, value, rule_error_message(field, msg))
        else
          current_params[field] = value
          current_errors << Error.new(field, value, rule_error_message(field, msg)) unless yield value
        end
      else
        current_errors << Error.new(field, nil, rule_error_message(field, msg))
      end
    end

    @[AlwaysInline]
    protected def apply_optional_rule(raw_params : Amber::Router::Params, current_params : Hash(String, String?), _current_errors : ErrorBuffer, field : String, _msg : String?, _allow_blank : Bool)
      if value = raw_params[field]?
        current_params[field] = value
      end
    end

    @[AlwaysInline]
    protected def apply_optional_rule(raw_params : Amber::Router::Params, current_params : Hash(String, String?), current_errors : ErrorBuffer, field : String, msg : String?, allow_blank : Bool, &predicate : String -> Bool)
      if value = raw_params[field]?
        current_params[field] = value
        return if value.blank? && allow_blank
        current_errors << Error.new(field, value, rule_error_message(field, msg)) unless yield value
      end
    end

    private def rule_error_message(field : String, msg : String?) : String
      msg || "Field #{field} is required"
    end
  end

  # Holds a validation error message
  record Error, param : String, value : String?, message : String

  class ErrorBuffer
    @errors : Array(Error)?

    def clear
      @errors.try &.clear
    end

    @[AlwaysInline]
    def <<(error : Error)
      (@errors ||= [] of Error) << error
    end

    @[AlwaysInline]
    def empty? : Bool
      current_errors = @errors
      current_errors.nil? || current_errors.empty?
    end

    def to_a : Array(Error)
      @errors || ([] of Error)
    end
  end

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
    @error_buffer : ErrorBuffer?
    @reusable_definition : ReusableDefinition?

    def initialize(@raw_params); end

    def self.define(&)
      builder = DefinitionBuilder.new([] of CompiledRule)
      with builder yield
      Definition.new(builder._rules)
    end

    macro compile(name, &block)
      {% validator_name = "CompiledValidation#{name.id}".id %}
      {% expressions = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
      {% direct_rule_count = 0 %}
      {% fallback_rule_count = 0 %}
      {% for expression, index in expressions %}
        {% unless expression.is_a?(Call) %}
          {% raise "Params.compile only supports required/optional rule calls" %}
        {% end %}
        {% rule_name = expression.name.stringify %}
        {% unless rule_name == "required" || rule_name == "optional" %}
          {% raise "Params.compile only supports required/optional rules" %}
        {% end %}
        {% direct_rule = true %}
        {% field_name = nil %}
        {% allow_blank = rule_name == "required" ? false : true %}
        {% message = nil %}

        {% if expression.block && expression.block.args.size != 1 %}
          {% direct_rule = false %}
        {% end %}

        {% if expression.args.size > 0 %}
          {% field_arg = expression.args[0] %}
          {% if field_arg.is_a?(SymbolLiteral) %}
            {% field_name = field_arg.stringify[1..-1] %}
          {% elsif field_arg.is_a?(StringLiteral) %}
            {% field_name = field_arg.stringify[1..-2] %}
          {% else %}
            {% direct_rule = false %}
          {% end %}
        {% else %}
          {% direct_rule = false %}
        {% end %}

        {% if expression.args.size >= 2 %}
          {% second_arg = expression.args[1] %}
          {% if second_arg.is_a?(StringLiteral) %}
            {% message = second_arg.stringify[1..-2] %}
          {% elsif second_arg.is_a?(BoolLiteral) %}
            {% allow_blank = second_arg.stringify == "true" %}
          {% elsif second_arg.is_a?(NilLiteral) %}
          {% else %}
            {% direct_rule = false %}
          {% end %}
        {% end %}

        {% if expression.args.size >= 3 %}
          {% third_arg = expression.args[2] %}
          {% if third_arg.is_a?(BoolLiteral) %}
            {% allow_blank = third_arg.stringify == "true" %}
          {% else %}
            {% direct_rule = false %}
          {% end %}
        {% end %}

        {% if expression.args.size > 3 %}
          {% direct_rule = false %}
        {% end %}

        {% unless expression.named_args.is_a?(Nop) %}
          {% for named_arg in expression.named_args %}
            {% if named_arg.name.stringify == "allow_blank" && named_arg.value.is_a?(BoolLiteral) %}
              {% allow_blank = named_arg.value.stringify == "true" %}
            {% else %}
              {% direct_rule = false %}
            {% end %}
          {% end %}
        {% end %}

        {% if direct_rule %}
          {% direct_rule_count += 1 %}
        {% else %}
          {% fallback_rule_count += 1 %}
        {% end %}
      {% end %}

      class {{validator_name}} < Amber::Validators::CompiledDefinition
        {% for expression, index in expressions %}
          {% unless expression.is_a?(Call) %}
            {% raise "Params.compile only supports required/optional rule calls" %}
          {% end %}
          {% rule_name = expression.name.stringify %}
          {% unless rule_name == "required" || rule_name == "optional" %}
            {% raise "Params.compile only supports required/optional rules" %}
          {% end %}
          {% direct_rule = true %}
          {% field_name = nil %}
          {% allow_blank = rule_name == "required" ? false : true %}
          {% message = nil %}

          {% if expression.block && expression.block.args.size != 1 %}
            {% direct_rule = false %}
          {% end %}

          {% if expression.args.size > 0 %}
            {% field_arg = expression.args[0] %}
            {% if field_arg.is_a?(SymbolLiteral) %}
              {% field_name = field_arg.stringify[1..-1] %}
            {% elsif field_arg.is_a?(StringLiteral) %}
              {% field_name = field_arg.stringify[1..-2] %}
            {% else %}
              {% direct_rule = false %}
            {% end %}
          {% else %}
            {% direct_rule = false %}
          {% end %}

          {% if expression.args.size >= 2 %}
            {% second_arg = expression.args[1] %}
            {% if second_arg.is_a?(StringLiteral) %}
              {% message = second_arg.stringify[1..-2] %}
            {% elsif second_arg.is_a?(BoolLiteral) %}
              {% allow_blank = second_arg.stringify == "true" %}
            {% elsif second_arg.is_a?(NilLiteral) %}
            {% else %}
              {% direct_rule = false %}
            {% end %}
          {% end %}

          {% if expression.args.size >= 3 %}
            {% third_arg = expression.args[2] %}
            {% if third_arg.is_a?(BoolLiteral) %}
              {% allow_blank = third_arg.stringify == "true" %}
            {% else %}
              {% direct_rule = false %}
            {% end %}
          {% end %}

          {% if expression.args.size > 3 %}
            {% direct_rule = false %}
          {% end %}

          {% unless expression.named_args.is_a?(Nop) %}
            {% for named_arg in expression.named_args %}
              {% if named_arg.name.stringify == "allow_blank" && named_arg.value.is_a?(BoolLiteral) %}
                {% allow_blank = named_arg.value.stringify == "true" %}
              {% else %}
                {% direct_rule = false %}
              {% end %}
            {% end %}
          {% end %}

          {% unless direct_rule %}
            {% fallback_name = "FALLBACK_DEFINITION_#{index}".id %}
            {{fallback_name}} = begin
              builder = Amber::Validators::DefinitionBuilder.new([] of Amber::Validators::CompiledRule)
              builder.{{expression.name.id}}(
                {% for arg in expression.args %}
                  {{arg}},
                {% end %}
                {% unless expression.named_args.is_a?(Nop) %}
                  {% for named_arg in expression.named_args %}
                    {{named_arg.name.id}}: {{named_arg.value}},
                  {% end %}
                {% end %}
              ){% if expression.block %} do {% if expression.block.args.size > 0 %}|{{expression.block.args.splat}}|{% end %}
                {{expression.block.body}}
              end{% end %}
              Amber::Validators::Definition.new(builder._rules)
            end
          {% end %}
        {% end %}

        def total_rule_count : Int32
          {{expressions.size}}
        end

        def direct_rule_count : Int32
          {{direct_rule_count}}
        end

        def fallback_rule_count : Int32
          {{fallback_rule_count}}
        end

        @[AlwaysInline]
        def apply(raw_params : Amber::Router::Params, current_params : Hash(String, String?), current_errors : Amber::Validators::ErrorBuffer)
          {% for expression, index in expressions %}
            {% unless expression.is_a?(Call) %}
              {% raise "Params.compile only supports required/optional rule calls" %}
            {% end %}
            {% rule_name = expression.name.stringify %}
            {% unless rule_name == "required" || rule_name == "optional" %}
              {% raise "Params.compile only supports required/optional rules" %}
            {% end %}
            {% direct_rule = true %}
            {% field_name = nil %}
            {% allow_blank = rule_name == "required" ? false : true %}
            {% message = nil %}

            {% if expression.block && expression.block.args.size != 1 %}
              {% direct_rule = false %}
            {% end %}

            {% if expression.args.size > 0 %}
              {% field_arg = expression.args[0] %}
              {% if field_arg.is_a?(SymbolLiteral) %}
                {% field_name = field_arg.stringify[1..-1] %}
              {% elsif field_arg.is_a?(StringLiteral) %}
                {% field_name = field_arg.stringify[1..-2] %}
              {% else %}
                {% direct_rule = false %}
              {% end %}
            {% else %}
              {% direct_rule = false %}
            {% end %}

            {% if expression.args.size >= 2 %}
              {% second_arg = expression.args[1] %}
              {% if second_arg.is_a?(StringLiteral) %}
                {% message = second_arg.stringify[1..-2] %}
              {% elsif second_arg.is_a?(BoolLiteral) %}
                {% allow_blank = second_arg.stringify == "true" %}
              {% elsif second_arg.is_a?(NilLiteral) %}
              {% else %}
                {% direct_rule = false %}
              {% end %}
            {% end %}
            {% if expression.args.size >= 3 %}
              {% third_arg = expression.args[2] %}
              {% if third_arg.is_a?(BoolLiteral) %}
                {% allow_blank = third_arg.stringify == "true" %}
              {% else %}
                {% direct_rule = false %}
              {% end %}
            {% end %}
            {% if expression.args.size > 3 %}
              {% direct_rule = false %}
            {% end %}
            {% unless expression.named_args.is_a?(Nop) %}
              {% for named_arg in expression.named_args %}
                {% if named_arg.name.stringify == "allow_blank" && named_arg.value.is_a?(BoolLiteral) %}
                  {% allow_blank = named_arg.value.stringify == "true" %}
                {% else %}
                  {% direct_rule = false %}
                {% end %}
              {% end %}
            {% end %}

            {% if direct_rule %}
              {% if rule_name == "required" %}
                apply_required_rule(raw_params, current_params, current_errors, {{field_name}}, {% if message %}{{message}}{% else %}nil{% end %}, {{allow_blank}}){% if expression.block %} do |{{expression.block.args.splat}}|
                  {{expression.block.body}}
                end{% end %}
              {% else %}
                apply_optional_rule(raw_params, current_params, current_errors, {{field_name}}, {% if message %}{{message}}{% else %}nil{% end %}, {{allow_blank}}){% if expression.block %} do |{{expression.block.args.splat}}|
                  {{expression.block.body}}
                end{% end %}
              {% end %}
            {% else %}
              {% fallback_name = "FALLBACK_DEFINITION_#{index}".id %}
              {{fallback_name}}.apply(raw_params, current_params, current_errors)
            {% end %}
          {% end %}
        end
      end

      {{name.id}} = {{validator_name}}.new
    end

    def rules
      @rules ||= [] of BaseRule
    end

    def params
      @params ||= {} of String => String?
    end

    def error_buffer
      @error_buffer ||= ErrorBuffer.new
    end

    def errors
      error_buffer.to_a
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

    def validation(definition : ReusableDefinition)
      @reusable_definition = definition
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
      current_errors = error_buffer
      current_params = params
      current_errors.clear
      current_params.clear

      current_reusable_definition = @reusable_definition
      current_rules = @rules
      has_reusable_definition = !current_reusable_definition.nil?
      has_dynamic_rules = !current_rules.nil? && !current_rules.empty?
      return true unless has_reusable_definition || has_dynamic_rules

      current_reusable_definition.try &.apply(raw_params, current_params, current_errors)

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
  end
end
