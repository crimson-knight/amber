require "http"
require "log"
require "json"
require "colorize"
require "random/secure"
require "kilt"
require "kilt/slang"
require "compiled_license"

require "./amber/version"
require "./amber/adapters"
require "./amber/controller/**"
require "./amber/dsl/**"
require "./amber/exceptions/**"
require "./amber/extensions/**"
require "./amber/router/context"
require "./amber/pipes/**"
require "./amber/server/**"
require "./amber/validators/**"
require "./amber/websockets/**"
require "./amber/environment"
require "./amber/schema/**"

module Amber
  include Amber::Environment
end
