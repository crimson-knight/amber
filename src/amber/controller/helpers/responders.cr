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

    protected def respond_with(status_code = 200, &block)
      content = with Content.new(requested_responses) yield
      if content.body
        set_response(body: content.body.to_s, status_code: status_code, content_type: content.type)
      else
        set_response(body: "Response Not Acceptable.", status_code: 406, content_type: Content::TYPE[:text])
      end
    end
  end
end
