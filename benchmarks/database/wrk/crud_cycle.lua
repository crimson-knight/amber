local token = "benchmark-session-token-0001"
local index = 0
local application_errors = 0
local headers = {
  ["Accept"] = "application/json",
  ["Authorization"] = "Bearer " .. token,
}

request = function()
  index = index + 1
  local id = ((index * 7919) % 1000000) + 1
  return wrk.format("POST", "/api/v1/resources/" .. id .. "/crud-cycle", headers)
end

response = function(status, response_headers, body)
  if status ~= 200 or not string.find(body, '"deleted":true') then
    application_errors = application_errors + 1
  end
end

done = function(summary, latency, requests)
  io.write(string.format("APPLICATION_ERRORS: %d\n", application_errors))
end
