local password = "AmberBenchmark!2026"
local index = 0
local application_errors = 0

request = function()
  index = index + 1
  local user_id = ((index - 1) % 50) + 1
  local email = string.format("user%06d@example.test", user_id)
  local body = string.format('{"email":"%s","password":"%s"}', email, password)
  return wrk.format("POST", "/api/v1/sessions", {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
  }, body)
end

response = function(status, headers, body)
  if status ~= 200 or not string.find(body, '"token":"[0-9a-f]+"') then
    application_errors = application_errors + 1
  end
end

done = function(summary, latency, requests)
  io.write(string.format("APPLICATION_ERRORS: %d\n", application_errors))
end
