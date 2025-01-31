-- This module is responsible for the MR pipeline
-- This lets the user see the current status of the pipeline
-- and retrigger the pipeline from within the editor
local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local M = {
  pipeline_jobs = nil,
  latest_pipeline = nil,
  pipeline_popup = nil,
}

local function get_latest_pipelines(count)
  count = count or 1 -- Default to 1 if count is not provided
  local pipelines = {}

  if not state.PIPELINE then
    u.notify("Pipeline state is not initialized", vim.log.levels.WARN)
    return nil
  end

  for i = 1, math.max(count, #state.PIPELINE) do
    local pipeline = state.PIPELINE[i].latest_pipeline
    if type(pipeline) == "table" and u.table_size(pipeline) > 0 then
      table.insert(pipelines, pipeline)
    end
  end

  if #pipelines == 0 then
    u.notify("No valid pipelines found", vim.log.levels.WARN)
    return nil
  end
  return pipelines
end

local function get_pipeline_jobs(idx)
  return u.reverse(type(state.PIPELINE[idx].jobs) == "table" and state.PIPELINE[idx].jobs or {})
end

-- The function will render the Pipeline state in a popup
M.open = function()
  M.latest_pipelines = get_latest_pipelines()
  if not M.latest_pipelines then
    return
  end
  if not M.latest_pipelines or #M.latest_pipelines == 0 then
    return
  end

  local max_width = 0
  local total_height = 0
  local pipelines_data = {}

  for idx, pipeline in ipairs(M.latest_pipelines) do
    local width = string.len(pipeline.web_url) + 10
    max_width = math.max(max_width, width)
    local pipeline_jobs = get_pipeline_jobs(idx)
    local pipeline_status = M.get_pipeline_status(idx, false)
    local height = 6 + #pipeline_jobs + 3
    total_height = total_height + height

    table.insert(pipelines_data, {
      pipeline = pipeline,
      pipeline_status = pipeline_status,
      jobs = pipeline_jobs,
      width = width,
      height = 6 + #pipeline_jobs + 3,
      lines = {},
    })
  end

  local pipeline_popup =
    Popup(popup.create_popup_state("Loading Pipelines...", state.settings.popup.pipeline, max_width, total_height, 60))
  popup.set_up_autocommands(pipeline_popup, nil, vim.api.nvim_get_current_win())
  M.pipeline_popup = pipeline_popup
  pipeline_popup:mount()

  local bufnr = vim.api.nvim_get_current_buf()
  vim.opt_local.wrap = false

  u.switch_can_edit_buf(bufnr, true)

  local all_lines = {}
  for i, data in ipairs(pipelines_data) do
    local pipeline = data.pipeline
    local lines = data.lines

    table.insert(lines, data.pipeline_status)
    table.insert(lines, "")
    table.insert(lines, string.format("Last Run: %s", u.time_since(pipeline.created_at)))
    table.insert(lines, string.format("Url: %s", pipeline.web_url))
    table.insert(lines, string.format("Triggered By: %s", pipeline.source))
    table.insert(lines, "")
    table.insert(lines, "Jobs:")

    local longest_title = u.get_longest_string(u.map(data.jobs, function(v)
      return v.name
    end))

    local function row_offset(name)
      local offset = longest_title - string.len(name)
      local res = string.rep(" ", offset + 5)
      return res
    end

    for _, pipeline_job in ipairs(data.jobs) do
      local offset = row_offset(pipeline_job.name)
      local row = string.format(
        "%s%s %s (%s)",
        pipeline_job.name,
        offset,
        state.settings.pipeline[pipeline_job.status] or "*",
        pipeline_job.status or ""
      )
      table.insert(lines, row)
    end

    -- Add separator between pipelines
    if i < #pipelines_data then
      table.insert(lines, "")
      table.insert(lines, string.rep("-", max_width))
      table.insert(lines, "")
    end

    for _, line in ipairs(lines) do
      table.insert(all_lines, line)
    end
  end

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, all_lines)

    local line_offset = 0
    for _, data in ipairs(pipelines_data) do
      local pipeline = data.pipeline
      local lines = data.lines

      M.color_status(pipeline.status, bufnr, all_lines[line_offset + 1], line_offset + 1)

      for j, pipeline_job in ipairs(data.jobs) do
        M.color_status(pipeline_job.status, bufnr, all_lines[line_offset + 7 + j], line_offset + 7 + j)
      end

      line_offset = line_offset + #lines
    end

    pipeline_popup.border:set_text("top", "Pipelines Status", "center")
    popup.set_popup_keymaps(pipeline_popup, M.retrigger, M.see_logs)
    u.switch_can_edit_buf(bufnr, false)
  end)
end
M.retrigger = function()
  M.latest_pipeline = get_latest_pipelines()
  if not M.latest_pipeline then
    return
  end
  if M.latest_pipeline.status ~= "failed" then
    u.notify("Pipeline is not in a failed state!", vim.log.levels.WARN)
    return
  end

  job.run_job("/pipeline/" .. M.latest_pipeline.id, "POST", nil, function()
    u.notify("Pipeline re-triggered!", vim.log.levels.INFO)
  end)
end

M.see_logs = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linnr = vim.api.nvim_win_get_cursor(0)[1]
  local text = u.get_line_content(bufnr, linnr)

  local job_name = string.match(text, "(.-)%s%s%s%s%s")

  if job_name == nil then
    u.notify("Cannot find job name", vim.log.levels.ERROR)
    return
  end

  local j = nil
  for _, pipeline_job in ipairs(M.pipeline_jobs) do
    if pipeline_job.name == job_name then
      j = pipeline_job
    end
  end

  if j == nil then
    u.notify("Cannot find job in state", vim.log.levels.ERROR)
    return
  end

  local body = { job_id = j.id }
  job.run_job("/job", "GET", body, function(data)
    local file = data.file
    if file == "" then
      u.notify("Log trace is empty", vim.log.levels.WARN)
      return
    end

    local lines = u.lines_into_table(file)

    if #lines == 0 then
      u.notify("Log trace lines could not be parsed", vim.log.levels.ERROR)
      return
    end

    M.pipeline_popup:unmount()

    vim.cmd.tabnew()
    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local temp_file = os.tmpname()
    local job_file_path = string.format(temp_file, j.id)

    vim.cmd("w! " .. job_file_path)
    vim.cmd("term cat " .. job_file_path)

    vim.api.nvim_buf_set_name(0, job_name)
  end)
end

---Returns the user-defined symbol representing the status
---of the current pipeline. Takes an optional argument to
---colorize the pipeline icon.
---@param wrap_with_color boolean
---@return string
M.get_pipeline_icon = function(idx, wrap_with_color)
  local symbol = state.settings.pipeline[state.PIPELINE[idx].latest_pipeline.status]
  if not wrap_with_color then
    return symbol
  end
  if M.latest_pipeline.status == "failed" then
    return "%#DiagnosticError#" .. symbol
  end
  if M.latest_pipeline.status == "success" then
    return "%#DiagnosticOk#" .. symbol
  end
  return "%#DiagnosticWarn#" .. symbol
end

---Returns the status of the latest pipeline and the symbol
--representing the status of the current pipeline. Takes an optional argument to
---colorize the pipeline icon.
---@param wrap_with_color boolean
---@return string
M.get_pipeline_status = function(idx, wrap_with_color)
  return string.format(
    "[%s]: Status: %s (%s)",
    state.PIPELINE[idx].name,
    M.get_pipeline_icon(idx, wrap_with_color),
    state.PIPELINE[idx].latest_pipeline.status
  )
end

M.color_status = function(status, bufnr, status_line, linnr)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  vim.cmd(string.format("highlight default StatusHighlight guifg=%s", state.settings.pipeline[status]))

  local status_to_color_map = {
    created = "DiagnosticWarn",
    pending = "DiagnosticWarn",
    preparing = "DiagnosticWarn",
    scheduled = "DiagnosticWarn",
    running = "DiagnosticWarn",
    canceled = "DiagnosticWarn",
    skipped = "DiagnosticWarn",
    failed = "DiagnosticError",
    success = "DiagnosticOK",
  }

  vim.api.nvim_buf_set_extmark(
    bufnr,
    ns_id,
    linnr - 1,
    0,
    { end_row = linnr - 1, end_col = string.len(status_line), hl_group = status_to_color_map[status] }
  )
end

return M
