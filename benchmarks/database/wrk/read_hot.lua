local token = "benchmark-session-token-0001"
local index = 0
local application_errors = 0
local headers = {
  ["Accept"] = "application/json",
  ["Authorization"] = "Bearer " .. token,
}

local function resource_id(sequence)
  if sequence % 10 < 7 then
    return ((sequence * 7919) % 200000) + 1
  end
  return ((sequence * 104729) % 1000000) + 1
end

request = function()
  index = index + 1
  local id = resource_id(index)
  local bucket = index % 100
  local path
  if bucket < 45 then
    path = "/api/v1/resources/" .. id
  elseif bucket < 65 then
    path = "/api/v1/resources/by-uuid/10000000-0000-4000-8000-" .. string.format("%012x", id)
  elseif bucket < 80 then
    path = "/api/v1/resources/by-ulid/01J8Z3M5N7" .. string.format("%016d", id)
  else
    path = "/api/v1/users/" .. (((id - 1) % 10000) + 1) .. "/resources"
  end
  return wrk.format("GET", path, headers)
end

response = function(status, response_headers, body)
  if status ~= 200 or #body < 20 then
    application_errors = application_errors + 1
  end
end

done = function(summary, latency, requests)
  io.write(string.format("APPLICATION_ERRORS: %d\n", application_errors))
end
