{% if flag?(:android) %}
  {% raise "Amber server-only code cannot be compiled for Android. Require amber/native from the Android entrypoint and inject platform services into shared application code. Keep require amber, controllers, routes, sessions, mailers and server jobs in the web entrypoint." %}
{% end %}
