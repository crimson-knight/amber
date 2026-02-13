require "./markdown/html_entities"
require "./markdown/utils"
require "./markdown/node"
require "./markdown/rule"
require "./markdown/options"
require "./markdown/renderer"
require "./markdown/parser"

module Amber
  module Markdown
    def self.to_html(source : String, options = Options.new) : String
      return "" if source.empty?

      document = Parser.parse(source, options)
      renderer = HTMLRenderer.new(options)
      renderer.render(document)
    end
  end
end
