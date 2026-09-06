require "json"
require "./errors"

# Validates supplied file metadata, not file contents or filesystem permissions.
# Native adapters and HTTP multipart parsers share this value-only contract.
module Amber::Schema
  # File metadata validator for schema field validation
  class FileMetadataValidator
    def self.validate_file(field_name : String, file_data : JSON::Any, options : Hash(String, JSON::Any)) : Array(Error)
      errors = [] of Error

      return errors unless file_hash = file_data.as_h?

      # Check if this is actually a file upload
      filename = file_hash["filename"]?.try(&.as_s?)
      unless filename
        errors << CustomValidationError.new(field_name, "Expected file upload", "not_a_file")
        return errors
      end

      content = file_hash["content"]?.try(&.as_s?) || ""
      content_type = file_hash["content_type"]?.try(&.as_s?)
      size = file_hash["size"]?.try(&.as_i64?) || content.bytesize.to_i64

      # Validate file size
      if max_size = options["max_size"]?.try(&.as_i64?)
        if size > max_size
          errors << CustomValidationError.new(
            field_name,
            "File size #{size} bytes exceeds maximum of #{max_size} bytes",
            "file_too_large"
          )
        end
      end

      if min_size = options["min_size"]?.try(&.as_i64?)
        if size < min_size
          errors << CustomValidationError.new(
            field_name,
            "File size #{size} bytes is below minimum of #{min_size} bytes",
            "file_too_small"
          )
        end
      end

      # Validate content type
      if allowed_types = options["allowed_types"]?.try(&.as_a?)
        if content_type
          type_strings = allowed_types.map(&.as_s)
          unless type_strings.includes?(content_type)
            errors << CustomValidationError.new(
              field_name,
              "Content type '#{content_type}' not allowed. Allowed types: #{type_strings.join(", ")}",
              "invalid_content_type"
            )
          end
        else
          errors << CustomValidationError.new(
            field_name,
            "Content type missing for file upload",
            "missing_content_type"
          )
        end
      end

      # Validate file extensions
      if allowed_extensions = options["allowed_extensions"]?.try(&.as_a?)
        extension = File.extname(filename).downcase
        ext_strings = allowed_extensions.map(&.as_s).map(&.downcase)
        unless ext_strings.includes?(extension)
          errors << CustomValidationError.new(
            field_name,
            "File extension '#{extension}' not allowed. Allowed extensions: #{ext_strings.join(", ")}",
            "invalid_file_extension"
          )
        end
      end

      # Validate filename pattern
      if pattern = options["filename_pattern"]?.try(&.as_s?)
        regex = Regex.new(pattern)
        unless filename.matches?(regex)
          errors << CustomValidationError.new(
            field_name,
            "Filename '#{filename}' does not match required pattern: #{pattern}",
            "invalid_filename_pattern"
          )
        end
      end

      errors
    end
  end
end
