# Standalone Round 18 proof that a target-aware responder macro can drop
# inactive target branches before Crystal type-checks their branch bodies.
#
# Expected builds:
#   crystal run benchmarks/respond_with_target_pruning_proof.cr
#   crystal run -Damber_target_web benchmarks/respond_with_target_pruning_proof.cr
#   crystal run -Damber_target_native benchmarks/respond_with_target_pruning_proof.cr

module AmberFrameworkPerfRound18
  module TargetResponderProof
    macro target_respond_with(&block)
      {% active_target = flag?(:amber_target_native) ? "native" : "web" %}
      {% expressions = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
      {% selected_expression = nil %}

      {% for expression in expressions %}
        {% if selected_expression == nil && expression.is_a?(Call) %}
          {% target = expression.receiver ? expression.receiver.stringify : "web" %}
          {% selected_expression = expression if target == active_target %}
        {% end %}
      {% end %}

      {% if selected_expression %}
        {% if selected_expression.block %}
          {{ selected_expression.block.body }}
        {% elsif selected_expression.args.size == 1 %}
          {{ selected_expression.args[0] }}
        {% else %}
          nil
        {% end %}
      {% else %}
        nil
      {% end %}
    end
  end
end

include AmberFrameworkPerfRound18::TargetResponderProof

{% if flag?(:amber_target_native) %}
  class NativeOnlyScreen
    def self.build
      "native-screen"
    end
  end
{% else %}
  class WebOnlyTemplate
    def self.render
      "web-html"
    end
  end
{% end %}

selected = target_respond_with do
  web.html WebOnlyTemplate.render
  native.screen NativeOnlyScreen.build
end

expected =
  {% if flag?(:amber_target_native) %}
    "native-screen"
  {% else %}
    "web-html"
  {% end %}

raise "expected #{expected}, got #{selected}" unless selected == expected
puts selected
