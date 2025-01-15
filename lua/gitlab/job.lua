-- This module is responsible for making API calls to the Go server and
-- running the callbacks associated with those jobs when the JSON is returned
local Job = require("plenary.job")
local u = require("gitlab.utils")
local M = {}

M.run_job = function(endpoint, method, body, callback)
  local state = require("gitlab.state")
  local args = { "-s", "-X", (method or "POST"), string.format("localhost:%s", state.settings.port) .. endpoint }

  if body ~= nil then
    local encoded_body = vim.json.encode(body)
    table.insert(args, 1, "-d")
    table.insert(args, 2, encoded_body)
  end

  -- This handler will handle all responses from the Go server. Anything with a successful
  -- status will call the callback (if it is supplied for the job). Otherwise, it will print out the
  -- success message or error message and details from the Go server.
  local stderr = {}
  Job:new({
    command = "curl",
    args = args,
    on_stdout = function(_, output)
      vim.defer_fn(function()
        if output == nil then
          return
        end
        local data_ok, data = pcall(vim.json.decode, output)

        -- Failing to unmarshal JSON
        if not data_ok then
          local msg = string.format("Failed to parse JSON from %s endpoint", endpoint)
          if type(output) == "string" then
            msg = string.format(msg .. ", got: '%s'", output)
          end
          u.notify(string.format(msg, endpoint, output), vim.log.levels.WARN)
          return
        end

        -- If JSON provided, handle success or error cases
        if data ~= nil then
          if data.details == nil then
            if callback then
              callback(data)
              return
            end
            local message = string.format("%s", data.message)
            u.notify(message, vim.log.levels.INFO)
            return
          end

          -- Handle error case
          local message = string.format("%s: %s", data.message, data.details)
          u.notify(message, vim.log.levels.ERROR)
        end
      end, 0)
    end,
    on_stderr = function(_, data)
      if data then
        table.insert(stderr, data)
      end
    end,
    on_exit = function(code, status)
      vim.defer_fn(function()
        if #stderr ~= 0 then
          u.notify(
            string.format("Could not run command `%s %s`! Stderr was:", code.command, table.concat(code.args, " ")),
            vim.log.levels.ERROR
          )
          vim.notify(string.format("%s", table.concat(stderr, "\n")), vim.log.levels.ERROR)
        end
        if status ~= 0 then
          u.notify(string.format("Go server exited with non-zero code: %d", status), vim.log.levels.ERROR)
        end
      end, 0)
    end,
  }):start()
end

return M
