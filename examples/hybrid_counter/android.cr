# Integration fixture: the runner supplies an isolated AssetPipeline shard.
# This application imports the public runtime, not the showcase's screen code.
require "asset_pipeline/ui/android/application"
require "./shared"

module HybridCounter::Android
  class SessionProcess < Amber::Native::ProcessManager
    getter starts = 0
    getter backgrounds = 0

    def start : Nil
      @starts += 1
    end

    def background : Nil
      @backgrounds += 1
    end
  end

  @@state = HybridCounter::State.new
  @@draft = ""
  @@validation_message = "Enter a name with at least two characters."
  @@configuration = Amber::Native::Configuration.new("dev.amber.hybridcounter")
  @@process = SessionProcess.new
  @@lifecycle = Amber::Native::Lifecycle.new([@@process])

  def self.lifecycle(event : UI::Android::Application::LifecycleEvent) : Nil
    case event
    in .foreground? then @@lifecycle.activate
    in .background? then @@lifecycle.background
    in .stop?       then @@lifecycle.stop
    end
  end

  def self.screen : UI::View
    root = UI::VStack.new(12.0, UI::Alignment::Leading)
    root.padding = UI::EdgeInsets.new(top: 16.0, trailing: 16.0, bottom: 16.0, leading: 16.0)
    root << label("Shared Amber counter", "counter-title")
    root << label("Session: #{@@lifecycle.state} / starts #{@@process.starts} / backgrounds #{@@process.backgrounds}", "counter-lifecycle")
    root << label("Count: #{@@state.count}", "counter-count")
    increment = UI::Button.new("Increment") { @@state.increment; nil }
    increment.test_id = "counter-increment"
    root << increment
    root << label("Name: #{@@state.name}", "counter-name")
    field = UI::TextField.new("Name", text: @@draft) { |value| @@draft = value; nil }
    field.test_id = "counter-input"
    root << field
    rename = UI::Button.new("Rename") do
      result = @@state.rename(@@draft)
      @@validation_message = result.success? ? "Name accepted by shared schema." : "Name rejected by shared schema."
      nil
    end
    rename.test_id = "counter-rename"
    root << rename
    root << label(@@validation_message, "counter-validation")
    root
  end

  private def self.label(text : String, id : String) : UI::Label
    UI::Label.new(text).tap { |label| label.test_id = id }
  end
end

UI::Android::Application.on_lifecycle { |event| HybridCounter::Android.lifecycle(event) }
UI::Android::Application.configure { |_route| HybridCounter::Android.screen }
