require "http"
require "./parsers/*"
require "./file"

class HTTP::Request
  def matched_route_resolved? : Bool
    !@matched_route.nil?
  end
end

module Amber::Router
  module Types
    alias Key = String | Symbol
    alias Files = Hash(String, Amber::Router::File)
    alias Params = Hash(String, String)
  end

  class Params
    TYPE_EXT_REGEX   = Amber::Support::MimeTypes::TYPE_EXT_REGEX
    URL_ENCODED_FORM = "application/x-www-form-urlencoded"
    MULTIPART_FORM   = "multipart/form-data"
    APPLICATION_JSON = "application/json"

    private enum BodySource
      None
      Form
      Multipart
      Json
    end

    @files = Types::Files.new
    @multipart : Types::Params?
    @json : Types::Params?
    @form : HTTP::Params?
    @query : HTTP::Params?
    @route : Types::Params?
    @route_loaded = false
    @body_source : BodySource?

    def initialize(@request : HTTP::Request)
    end

    @[AlwaysInline]
    def [](key : String) : String
      self.[key]? || raise Amber::Exceptions::Validator::InvalidParam.new(key)
    end

    @[AlwaysInline]
    def [](key : Symbol) : String
      _key = key.to_s
      self.[_key]? || raise Amber::Exceptions::Validator::InvalidParam.new(key)
    end

    @[AlwaysInline]
    def []?(key : String)
      _key = key

      if route_resolved?
        if value = route_lookup(_key)
          return value
        end
      end

      case body_source
      when .form?
        query[_key]? || form[_key]? || route_lookup(_key)
      when .multipart?
        query[_key]? || multipart[_key]? || route_lookup(_key)
      when .json?
        query[_key]? || json[_key]? || route_lookup(_key)
      else
        query[_key]? || route_lookup(_key)
      end
    end

    @[AlwaysInline]
    def []?(key : Symbol)
      self.[key.to_s]?
    end

    def files
      multipart unless @multipart
      @files
    end

    @[AlwaysInline]
    def []=(key : String, value)
      query[key] = value
    end

    @[AlwaysInline]
    def []=(key : Symbol, value)
      query[key.to_s] = value
    end

    @[AlwaysInline]
    def has_key?(key : String) : Bool
      !!self.[key]?
    end

    @[AlwaysInline]
    def has_key?(key : Symbol) : Bool
      !!self.[key.to_s]?
    end

    @[AlwaysInline]
    def fetch_all(key : String) : Array
      _key = key
      if query.has_key?(_key)
        query.fetch_all(_key)
      else
        form.fetch_all(_key)
      end
    end

    @[AlwaysInline]
    def fetch_all(key : Symbol) : Array
      fetch_all(key.to_s)
    end

    @[AlwaysInline]
    def json(key : String)
      JSON.parse(self[key]?.to_s)
    rescue JSON::ParseException
      raise "Value of params.json(#{key.inspect}) is not JSON!"
    end

    @[AlwaysInline]
    def json(key : Symbol)
      json(key.to_s)
    end

    @[AlwaysInline]
    def override_method?(key : String)
      _key = key

      if value = query[_key]?
        return value
      end

      case body_source
      when .form?
        form[_key]?
      when .multipart?
        multipart[_key]?
      else
        nil
      end
    end

    @[AlwaysInline]
    def override_method?(key : Symbol)
      override_method?(key.to_s)
    end

    def to_h : Types::Params
      params_hash = Types::Params.new
      query.each { |key, _| params_hash[key] = query[key] }

      route.each_key do |key|
        if value = route[key]
          params_hash[key] = value
        end
      end

      case body_source
      when .form?
        form.each { |key, _| params_hash[key] = form[key] }
        route.each_key do |key|
          if value = route[key]
            params_hash[key] = value
          end
        end
      when .json?
        json.each_key { |key| params_hash[key] = json[key].to_s }
      when .multipart?
        multipart.each_key { |key| params_hash[key] = multipart[key].to_s }
      end
      params_hash
    end

    private def query
      @query ||= @request.query_params
    end

    private def form
      return HTTP::Params.parse("") unless content_type?(URL_ENCODED_FORM)
      @form ||= Parsers::FormData.parse(@request)
    end

    private def multipart
      return @multipart.not_nil! if @multipart
      return Types::Params.new unless content_type?(MULTIPART_FORM)
      @multipart, @files = Parsers::Multipart.parse(@request)
      @multipart.not_nil!
    end

    private def json
      return Types::Params.new unless content_type?(APPLICATION_JSON)
      @json ||= Parsers::JSON.parse(@request)
    end

    private def route
      return @route.not_nil! if @route_loaded

      @route = @request.matched_route.params
      @route_loaded = true
      @route.not_nil!
    end

    private def content_type?(header_type)
      case body_source
      when .form?
        header_type == URL_ENCODED_FORM
      when .multipart?
        header_type == MULTIPART_FORM
      when .json?
        header_type == APPLICATION_JSON
      else
        false
      end
    end

    private def route_lookup(key : String)
      if @route_loaded
        @route.not_nil![key]?
      elsif @request.matched_route_resolved?
        @request.matched_route[key]?
      else
        route[key]?
      end
    end

    private def route_resolved?
      @route_loaded || @request.matched_route_resolved?
    end

    private def body_source
      @body_source ||= begin
        case content_type = @request.headers["Content-Type"]?
        when .try &.starts_with?(URL_ENCODED_FORM)
          BodySource::Form
        when .try &.starts_with?(MULTIPART_FORM)
          BodySource::Multipart
        when .try &.starts_with?(APPLICATION_JSON)
          BodySource::Json
        else
          BodySource::None
        end
      end
    end
  end
end
