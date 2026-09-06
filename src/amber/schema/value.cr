require "json"
require "uri"
require "uuid"
require "./errors"
require "./result"
require "./annotations"
require "./type_coercion"
require "./file_metadata_validator"
require "./validator"
require "./definition"
require "./validators/*"

# Platform-neutral schema definitions, validation results and value coercion.
# HTTP parsing, request/controller integration and response writers are excluded.
