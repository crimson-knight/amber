# Enhanced multipart form data parser with file upload support
require "http"
require "../file_metadata_validator"

module Amber::Schema::Parser
  # Backwards-compatible HTTP parser name for the shared value validator.
  alias FileUploadValidator = ::Amber::Schema::FileMetadataValidator

  # Enhanced multipart parser that creates file data structures
  class MultipartParser
    # File info structure for multipart uploads
    struct FileInfo
      getter filename : String?
      getter content_type : String?
      getter size : UInt64?
      getter content : String
      getter headers : HTTP::Headers

      def initialize(@filename, @content_type, @size, @content, @headers)
      end

      def to_json_any : JSON::Any
        data = {} of String => JSON::Any
        data["filename"] = JSON::Any.new(@filename) if @filename
        data["content_type"] = JSON::Any.new(@content_type) if @content_type
        data["size"] = JSON::Any.new(@size.not_nil!.to_i64) if @size
        data["content"] = JSON::Any.new(@content)

        # Add headers as a nested object
        headers_hash = {} of String => JSON::Any
        @headers.each do |name, values|
          if values.size == 1
            headers_hash[name] = JSON::Any.new(values[0])
          else
            headers_hash[name] = JSON::Any.new(values.map { |v| JSON::Any.new(v) })
          end
        end
        data["headers"] = JSON::Any.new(headers_hash)

        JSON::Any.new(data)
      end
    end

    # Parse multipart form data, handling both files and regular fields
    def self.parse_multipart_request(request : HTTP::Request) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any

      HTTP::FormData.parse(request) do |upload|
        next unless upload

        filename = upload.filename
        content = upload.body.gets_to_end

        if filename.is_a?(String) && !filename.empty?
          # This is a file upload
          file_info = FileInfo.new(
            filename: filename,
            content_type: upload.headers["Content-Type"]?,
            size: content.bytesize.to_u64,
            content: content,
            headers: upload.headers
          )
          QueryParser.set_nested_value(result, upload.name, file_info.to_json_any)
        else
          # This is a regular form field
          QueryParser.set_nested_value(result, upload.name, QueryParser.parse_value(content))
        end
      end

      result
    end
  end
end
