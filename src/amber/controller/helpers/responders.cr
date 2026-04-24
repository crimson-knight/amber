module Amber::Controller::Helpers
  module Responders
    Log = ::Log.for(self)

    alias ProcType = Proc(String) | Proc(Int32)

    class Content
      TYPE = {
        html: "text/html",
        json: "application/json; charset=utf-8",
        txt:  "text/plain",
        text: "text/plain",
        xml:  "application/xml",
        js:   "text/javascript",
      }

      TYPE_EXT_REGEX         = /\.(#{TYPE.keys.join("|")})$/
      ACCEPT_SEPARATOR_REGEX = /,|,\s/

      @requested_responses : Array(String)
      @available_responses : Hash(String, String | ProcType)?
      @first_response_type : String?
      @first_response_value : String | ProcType | Nil = nil
      @type : String? = nil
      @body : String | Int32 | Nil = nil

      def initialize(@requested_responses)
      end

      {% for type in %w(html xml js json text) %}
        def {{type.id}}(value : String | ProcType)
          store_response(TYPE[:{{type.id}}], value)
          self
        end

        def {{type.id}}(&block : -> _)
          {{type.id}}(block)
        end
      {% end %}

      def json(value : Hash(Symbol | String, String))
        json(value.to_json)
      end

      def json(**args : Object)
        json(args.to_h)
      end

      def type
        (@type ||= select_type).to_s
      end

      def body
        @body ||= begin
          case _body = response_value(type)
          when Proc
            _body.call
          else
            _body
          end
        end
      end

      private def select_type
        if first_type = @first_response_type
          if single_response?
            return first_type if @requested_responses.empty? || @requested_responses.includes?("*/*")
            return first_type if @requested_responses.any? { |resp| first_type.includes?(resp) }
            return
          end
        end

        available_responses = @available_responses
        raise "You must define at least one response_type." unless available_responses || @first_response_type
        # NOTE: If only one response is requested or */* is present don't return anything else.
        if @requested_responses.size != 1 || @requested_responses.includes?("*/*")
          @requested_responses << available_response_keys.first
        end

        result = @requested_responses.find do |resp|
          available_response_keys.find { |r| r.includes?(resp) }
        end

        if result == "application/json"
          result = "application/json; charset=utf-8"
        end

        result
      end

      private def single_response?
        !@first_response_type.nil? && @available_responses.nil?
      end

      private def store_response(type : String, value : String | ProcType)
        if responses = @available_responses
          responses[type] = value
          return
        end

        if first_type = @first_response_type
          if first_type == type
            @first_response_value = value
            return
          end

          @available_responses = {
            first_type => @first_response_value.as(String | ProcType),
            type       => value,
          }
          return
        end

        @first_response_type = type
        @first_response_value = value
      end

      private def available_response_keys
        if responses = @available_responses
          responses.keys
        else
          [@first_response_type.not_nil!]
        end
      end

      private def response_value(type : String)
        if responses = @available_responses
          responses[type]?
        elsif @first_response_type == type
          @first_response_value
        end
      end
    end

    def set_response(body, status_code = 200, content_type = Content::TYPE[:html])
      if context.response.status_code == 200
        context.response.status_code = status_code
      else
        Log.error { "Setting response status_code would overwrite previous value" }
      end
      context.response.content_type = content_type
      context.content = body
    end

    private def extension_request_type
      path_ext = request.path.match(Content::TYPE_EXT_REGEX).try(&.[1])
      return [Content::TYPE[path_ext]] if path_ext
    end

    private def accepts_request_type
      accept = context.request.headers["Accept"]?
      if accept && !accept.empty?
        return [accept] unless accept.includes?(',') || accept.includes?(';')
        accepts = accept.split(";").first?.try(&.split(Content::ACCEPT_SEPARATOR_REGEX))
        return accepts if !accepts.nil? && !accepts.empty?
      end
    end

    private def requested_responses
      extension_request_type || accepts_request_type || [] of String
    end

    private def selected_response_type(requested_responses, available_response_types)
      first_response_type = nil

      available_response_types.each do |response_type|
        first_response_type ||= response_type
      end

      raise "You must define at least one response_type." unless first_response_type

      return first_response_type if requested_responses.empty?

      requested_responses.each do |requested_response|
        next if requested_response == "*/*"

        available_response_types.each do |available_response_type|
          return available_response_type if available_response_type.includes?(requested_response)
        end
      end

      if requested_responses.size != 1 || requested_responses.includes?("*/*")
        first_response_type
      end
    end

    private def resolve_response_body(value)
      case value
      when Proc
        value.call
      else
        value
      end
    end

    macro respond_with(*args, **named_args, &block)
      {% unless block.is_a?(Nop) %}
      {% response_methods = %w(html xml js json text) %}
      {% expressions = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
      {% supported = true %}
      {% response_count = 0 %}
      {% lazy_candidate = false %}
      {% status_code = args.size > 0 ? args[0] : 200 %}

      {% for expression in expressions %}
        {% if expression.is_a?(Call) && response_methods.includes?(expression.name.stringify) %}
          {% response_count += 1 %}
          {% if expression.args.size == 1 && expression.args[0].is_a?(Call) %}
            {% lazy_candidate = true %}
          {% end %}
          {% if expression.named_args.is_a?(ArrayLiteral) %}
            {% for named_arg in expression.named_args %}
              {% if named_arg.value.is_a?(Call) %}
                {% lazy_candidate = true %}
              {% end %}
            {% end %}
          {% end %}
        {% else %}
          {% supported = false %}
        {% end %}
      {% end %}

      {% if supported && response_count > 1 && lazy_candidate %}
        __amber_requested_responses = requested_responses
        __amber_selected_response_type = selected_response_type(
          __amber_requested_responses,
          {
            {% for expression in expressions %}
              {% if expression.is_a?(Call) && response_methods.includes?(expression.name.stringify) %}
                Content::TYPE[:{{expression.name.id}}],
              {% end %}
            {% end %}
          }
        )
        __amber_response_body = nil

        if __amber_selected_response_type
          case __amber_selected_response_type
          {% for response_method in response_methods %}
            when Content::TYPE[:{{response_method.id}}]
              {% for expression in expressions %}
                {% if expression.is_a?(Call) && expression.name.stringify == response_method %}
                  __amber_response_body = begin
                    {% if expression.block %}
                      {{expression.block.body}}
                    {% elsif expression.name.stringify == "json" && expression.named_args.is_a?(ArrayLiteral) %}
                      {
                        {% for named_arg in expression.named_args %}
                          {{named_arg.name.id}}: {{named_arg.value}},
                        {% end %}
                      }.to_json
                    {% elsif expression.args.size == 1 %}
                      {{expression.args[0]}}
                    {% else %}
                      raise "Unsupported respond_with #{ {{expression.name.stringify}} } response shape."
                    {% end %}
                  end
                {% end %}
              {% end %}
          {% end %}
          end
        end

        if __amber_response_body
          __amber_resolved_body = resolve_response_body(__amber_response_body)
          set_response(body: __amber_resolved_body.to_s, status_code: {{ status_code }}, content_type: __amber_selected_response_type.not_nil!)
        else
          set_response(body: "Response Not Acceptable.", status_code: 406, content_type: Content::TYPE[:text])
        end
      {% else %}
        respond_with_runtime({{ status_code }}) do
          {{block.body}}
        end
      {% end %}
      {% else %}
        {% response_data = args.size > 0 ? args[0] : nil %}
        {% response_status = named_args[:status] || (args.size > 1 ? args[1] : 200) %}
        {% schema_name = named_args[:schema_name] || (args.size > 2 ? args[2] : nil) %}

        respond_with_schema(
          {% if response_data %}
            {{ response_data }},
          {% else %}
            nil,
          {% end %}
          {{ response_status }},
          {% if schema_name %}
            {{ schema_name }}
          {% else %}
            nil
          {% end %}
        )
      {% end %}
    end

    protected def respond_with_runtime(status_code = 200, &block)
      content = with Content.new(requested_responses) yield
      if content.body
        set_response(body: content.body.to_s, status_code: status_code, content_type: content.type)
      else
        set_response(body: "Response Not Acceptable.", status_code: 406, content_type: Content::TYPE[:text])
      end
    end
  end
end
