# Main entry point for the Amber Schema API
# Provides request/response validation and parsing capabilities

# Include all schema components
require "./schema/value"
require "./schema/parser"
require "./schema/response_builder"

# Include subdirectories
require "./schema/parsers/*"
require "./schema/response/*"

# Include controller integration
require "./schema/controller_integration_simple"

module Amber
  module Schema
    # Version of the Schema API
    VERSION = "0.1.0"
  end
end
