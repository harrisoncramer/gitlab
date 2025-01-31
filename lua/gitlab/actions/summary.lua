-- This module is responsible for the MR description
-- This lets the user open the description in a popup and
-- send edits to the description back to Gitlab
local Layout = require("nui.layout")
local Popup = require("nui.popup")
local git = require("gitlab.git")
local job = require("gitlab.job")
local common = require("gitlab.actions.common")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local miscellaneous = require("gitlab.actions.miscellaneous")

local M = {
  layout_visible = false,
  layout = nil,
  layout_buf = nil,
  title_bufnr = nil,
  description_bufnr = nil,
}

-- The function will render a popup containing the MR title and MR description, and optionally,
-- any additional metadata that the user wants. The title and description are editable and
-- can be changed via the local action keybinding, which also closes the popup
M.summary = function()
  if M.layout_visible then
    M.layout:unmount()
    M.layout_visible = false
    return
  end

  local title = state.INFO.title
  local description_lines = common.build_content(state.INFO.description)
  local info_lines = state.settings.info.enabled and M.build_info_lines() or { "" }

  local layout, title_popup, description_popup, info_popup = M.create_layout(info_lines)

  layout:mount()

  local popups = {
    title_popup,
    description_popup,
    info_popup,
  }

  M.layout = layout
  M.info_popup = info_popup
  M.title_popup = title_popup
  M.description_popup = description_popup
  M.layout_buf = layout.bufnr
  M.layout_visible = true

  local function exit()
    layout:unmount()
    M.layout_visible = false
  end

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(description_popup.bufnr, 0, -1, false, description_lines)
    vim.api.nvim_buf_set_lines(title_popup.bufnr, 0, -1, false, { title })

    if info_popup then
      M.update_details_popup(info_popup.bufnr, info_lines)
    end

    popup.set_popup_keymaps(
      description_popup,
      M.edit_summary,
      miscellaneous.attach_file,
      { cb = exit, action_before_close = true, action_before_exit = true, save_to_temp_register = true }
    )
    popup.set_popup_keymaps(
      title_popup,
      M.edit_summary,
      nil,
      { cb = exit, action_before_close = true, action_before_exit = true }
    )
    popup.set_popup_keymaps(
      info_popup,
      M.edit_summary,
      nil,
      { cb = exit, action_before_close = true, action_before_exit = true }
    )
    popup.set_cycle_popups_keymaps(popups)

    vim.api.nvim_set_current_buf(description_popup.bufnr)
  end)

  git.check_current_branch_up_to_date_on_remote(vim.log.levels.WARN)
  git.check_mr_in_good_condition()
end

M.update_summary_details = function()
  if not M.info_popup or not M.info_popup.bufnr then
    return
  end
  local details_lines = state.settings.info.enabled and M.build_info_lines() or { "" }
  local internal_layout = M.create_internal_layout(details_lines, M.title_popup, M.description_popup, M.info_popup)
  M.layout:update(M.get_outer_layout_config(), internal_layout)
  M.update_details_popup(M.info_popup.bufnr, details_lines)
end

M.update_details_popup = function(bufnr, info_lines)
  u.switch_can_edit_buf(bufnr, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, info_lines)
  u.switch_can_edit_buf(bufnr, false)
  M.color_details(bufnr) -- Color values in details popup
end

-- Builds a lua list of strings that contain metadata about the current MR. Only builds the
-- lines that users include in their state.settings.info.fields list.
M.build_info_lines = function()
  local info = state.INFO
  local options = {
    author = { title = "Author", content = "@" .. info.author.username .. " (" .. info.author.name .. ")" },
    created_at = { title = "Created", content = u.format_to_local(info.created_at, vim.fn.strftime("%z")) },
    updated_at = { title = "Updated", content = u.time_since(info.updated_at) },
    detailed_merge_status = { title = "Status", content = info.detailed_merge_status },
    draft = { title = "Draft", content = (info.draft and "Yes" or "No") },
    conflicts = { title = "Merge Conflicts", content = (info.has_conflicts and "Yes" or "No") },
    assignees = { title = "Assignees", content = u.make_readable_list(info.assignees, "name") },
    reviewers = { title = "Reviewers", content = u.make_readable_list(info.reviewers, "name") },
    branch = { title = "Branch", content = info.source_branch },
    labels = { title = "Labels", content = table.concat(info.labels, ", ") },
    target_branch = { title = "Target Branch", content = info.target_branch },
    delete_branch = {
      title = "Delete Source Branch",
      content = (info.force_remove_source_branch and "Yes" or "No"),
    },
    squash = { title = "Squash Commits", content = (info.squash and "Yes" or "No") },
    pipeline = {
      title = "Pipeline Status",
      content = function()
        local pipeline = state.INFO.pipeline
        if type(pipeline) ~= "table" or (type(pipeline) == "table" and u.table_size(pipeline) == 0) then
          return ""
        end
        return pipeline.status
      end,
    },
    web_url = { title = "MR URL", content = info.web_url },
  }

  local longest_used = ""
  for _, v in ipairs(state.settings.info.fields) do
    if v == "merge_status" then
      v = "detailed_merge_status"
    end -- merge_status was deprecated, see https://gitlab.com/gitlab-org/gitlab/-/issues/3169#note_1162532204
    local title = options[v].title
    if string.len(title) > string.len(longest_used) then
      longest_used = title
    end
  end

  local function row_offset(row)
    local offset = string.len(longest_used) - string.len(row)
    return string.rep(" ", offset + 3)
  end

  return List.new(state.settings.info.fields):map(function(v)
    if v == "merge_status" then
      v = "detailed_merge_status"
    end
    local row = options[v]
    local line = "* " .. row.title .. row_offset(row.title)
    if type(row.content) == "function" then
      local content = row.content()
      if content ~= nil then
        line = line .. row.content()
      end
    else
      line = line .. row.content
    end
    return line
  end)
end

-- This function will PUT the new description to the Go server
M.edit_summary = function()
  local description = u.get_buffer_text(M.description_bufnr)
  local title = u.get_buffer_text(M.title_bufnr):gsub("\n", " ")
  local body = { title = title, description = description }
  job.run_job("/mr/summary", "PUT", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    state.INFO.description = data.mr.description
    state.INFO.title = data.mr.title
  end)
end

---Create the Summary layout and individual popups that make up the Layout.
---@return NuiLayout, NuiPopup, NuiPopup, NuiPopup
M.create_layout = function(info_lines)
  local settings = u.merge(state.settings.popup, state.settings.popup.summary or {})
  local title_popup = Popup(popup.create_box_popup_state(nil, false, settings))
  M.title_bufnr = title_popup.bufnr
  local description_popup = Popup(popup.create_popup_state("Description", settings))
  M.description_bufnr = description_popup.bufnr
  local details_popup
  if state.settings.info.enabled then
    details_popup = Popup(popup.create_box_popup_state("Details", false, settings))
  end

  local internal_layout = M.create_internal_layout(info_lines, title_popup, description_popup, details_popup)

  local layout = Layout(M.get_outer_layout_config(), internal_layout)

  popup.set_up_autocommands(description_popup, layout, vim.api.nvim_get_current_win())

  return layout, title_popup, description_popup, details_popup
end

---Create the internal layout of the Summary and individual popups that make up the Layout.
---@param info_lines string[] Table of strings that make up the details content
---@param title_popup NuiPopup
---@param description_popup NuiPopup
---@param details_popup NuiPopup
---@return NuiLayout.Box
M.create_internal_layout = function(info_lines, title_popup, description_popup, details_popup)
  local internal_layout
  if state.settings.info.enabled then
    if state.settings.info.horizontal then
      local longest_line = u.get_longest_string(info_lines)
      internal_layout = Layout.Box({
        Layout.Box(title_popup, { size = 3 }),
        Layout.Box({
          Layout.Box(details_popup, { size = longest_line + 3 }),
          Layout.Box(description_popup, { grow = 1 }),
        }, { dir = "row", size = "95%" }),
      }, { dir = "col" })
    else
      internal_layout = Layout.Box({
        Layout.Box(title_popup, { size = 3 }),
        Layout.Box(description_popup, { grow = 1 }),
        Layout.Box(details_popup, { size = #info_lines + 3 }),
      }, { dir = "col" })
    end
  else
    internal_layout = Layout.Box({
      Layout.Box(title_popup, { size = 3 }),
      Layout.Box(description_popup, { grow = 1 }),
    }, { dir = "col" })
  end
  return internal_layout
end

---Create the config for the outer Layout of the Summary
---@return nui_layout_options
M.get_outer_layout_config = function()
  local settings = u.merge(state.settings.popup, state.settings.popup.summary or {})
  return {
    position = settings.position,
    relative = "editor",
    size = {
      width = settings.width,
      height = settings.height,
    },
  }
end

M.color_details = function(bufnr)
  local details_namespace = vim.api.nvim_create_namespace("Details")
  for i, v in ipairs(state.settings.info.fields) do
    if v == "labels" then
      local line_content = u.get_line_content(bufnr, i)
      for j, label in ipairs(state.LABELS) do
        local start_idx, end_idx = line_content:find(label.Name)
        if start_idx ~= nil and end_idx ~= nil then
          vim.cmd("highlight " .. "label" .. j .. " guifg=white")
          vim.api.nvim_set_hl(0, ("label" .. j), { fg = label.Color })
          vim.api.nvim_buf_add_highlight(bufnr, details_namespace, ("label" .. j), i - 1, start_idx - 1, end_idx)
        end
      end
    elseif v == "delete_branch" or v == "squash" or v == "draft" or v == "conflicts" then
      local line_content = u.get_line_content(bufnr, i)
      local start_idx, end_idx = line_content:find("%S-$")
      if start_idx ~= nil and end_idx ~= nil then
        vim.api.nvim_set_hl(0, "boolean", { link = "Constant" })
        vim.api.nvim_buf_add_highlight(bufnr, details_namespace, "boolean", i - 1, start_idx - 1, end_idx)
      end
    end
  end
end

return M
