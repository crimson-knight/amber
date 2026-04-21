module Amber::Router::Parsers
  module JSON
    def self.parse(request : HTTP::Request)
      json_params = Types::Params.new

      return json_params unless request_body = request.body
      body = request_body.gets_to_end
      return json_params unless body.size > 2

      json_params["_json"] = body

      parser = ::JSON::PullParser.new(body)

      if parser.kind.begin_object?
        parser.read_object do |key, _|
          json_params[key] = if parser.kind.string?
                               parser.read_string
                             else
                               parser.read_raw
                             end
        end
      else
        parser.skip
      end

      json_params
    end
  end
end
