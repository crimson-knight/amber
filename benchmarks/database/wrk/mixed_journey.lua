local password = "AmberBenchmark!2026"
local token = nil
local index = 0
local last_kind = "login"
local application_errors = 0

local function id_for(sequence)
  if sequence % 10 < 7 then
    return ((sequence * 7919) % 200000) + 1
  end
  return ((sequence * 104729) % 1000000) + 1
end

local function auth_headers(content_type)
  local headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer " .. token,
  }
  if content_type then
    headers["Content-Type"] = content_type
  end
  return headers
end

local function login_request(sequence)
  last_kind = "login"
  local user_id = (sequence % 50) + 1
  local email = string.format("user%06d@example.test", user_id)
  local body = string.format('{"email":"%s","password":"%s"}', email, password)
  return wrk.format("POST", "/api/v1/sessions", {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
  }, body)
end

request = function()
  index = index + 1
  local bucket = index % 100
  if token == nil or bucket < 2 then
    return login_request(index)
  end

  local id = id_for(index)
  if bucket < 47 then
    last_kind = "read"
    return wrk.format("GET", "/api/v1/resources/" .. id, auth_headers())
  elseif bucket < 62 then
    last_kind = "read"
    local uuid = "10000000-0000-4000-8000-" .. string.format("%012x", id)
    return wrk.format("GET", "/api/v1/resources/by-uuid/" .. uuid, auth_headers())
  elseif bucket < 72 then
    last_kind = "read"
    local ulid = "01J8Z3M5N7" .. string.format("%016d", id)
    return wrk.format("GET", "/api/v1/resources/by-ulid/" .. ulid, auth_headers())
  elseif bucket < 82 then
    last_kind = "read"
    local user_id = ((id - 1) % 10000) + 1
    return wrk.format("GET", "/api/v1/users/" .. user_id .. "/resources", auth_headers())
  elseif bucket < 90 then
    last_kind = "calculate"
    return wrk.format("POST", "/api/v1/resources/" .. id .. "/calculate", auth_headers())
  elseif bucket < 96 then
    last_kind = "update"
    local body = string.format('{"status":"active","score":%.2f}', (id % 10000) / 100.0)
    return wrk.format("PATCH", "/api/v1/resources/" .. id, auth_headers("application/json"), body)
  else
    last_kind = "crud"
    return wrk.format("POST", "/api/v1/resources/" .. id .. "/crud-cycle", auth_headers())
  end
end

response = function(status, response_headers, body)
  if status ~= 200 then
    application_errors = application_errors + 1
    return
  end

  if last_kind == "login" then
    local next_token = string.match(body, '"token":"([0-9a-f]+)"')
    if next_token then
      token = next_token
    else
      application_errors = application_errors + 1
    end
  elseif #body < 20 then
    application_errors = application_errors + 1
  end
end

done = function(summary, latency, requests)
  io.write(string.format("APPLICATION_ERRORS: %d\n", application_errors))
end
