-- This module contains code shared between at least two modules. This includes
-- actions common to multiple tree types, as well as general utility functions
-- that are specific to actions (like jumping to a file or opening a URL)
local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local reviewer = require("gitlab.reviewer")
local indicators_common = require("gitlab.indicators.common")
local state = require("gitlab.state")
local M = {}

---Build note header from note
---@param note Note|DraftNote
---@return string
M.build_note_header = function(note)
  if note.note then
    return "@" .. state.USER.username .. " " .. state.settings.discussion_tree.draft
  end
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
end

M.switch_can_edit_bufs = function(bool, ...)
  local bufnrs = { ... }
  ---@param v integer
  for _, v in ipairs(bufnrs) do
    u.switch_can_edit_buf(v, bool)
    vim.api.nvim_set_option_value("filetype", "gitlab", { buf = v })
  end
end

---Takes in a chunk of text separated by new line characters and returns a lua table
---@param content string
---@return table
M.build_content = function(content)
  local description_lines = u.lines_into_table(content)
  table.insert(description_lines, "")
  return description_lines
end

M.add_empty_titles = function()
  local draft_notes = require("gitlab.actions.draft_notes")
  local discussions = require("gitlab.actions.discussions")
  local linked, unlinked, drafts =
    List.new(u.ensure_table(state.DISCUSSION_DATA and state.DISCUSSION_DATA.discussions)),
    List.new(u.ensure_table(state.DISCUSSION_DATA and state.DISCUSSION_DATA.unlinked_discussions)),
    List.new(u.ensure_table(state.DRAFT_NOTES))

  local position_drafts = drafts:filter(function(note)
    return draft_notes.has_position(note)
  end)
  local non_positioned_drafts = drafts:filter(function(note)
    return not draft_notes.has_position(note)
  end)

  local fields = {
    {
      bufnr = discussions.linked_bufnr,
      count = #linked + #position_drafts,
      title = "No Discussions for this MR",
    },
    {
      bufnr = discussions.unlinked_bufnr,
      count = #unlinked + #non_positioned_drafts,
      title = "No Notes (Unlinked Discussions) for this MR",
    },
  }

  for _, v in ipairs(fields) do
    if v.bufnr ~= nil then
      M.switch_can_edit_bufs(true, v.bufnr)
      local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
      vim.cmd("highlight default TitleHighlight guifg=#787878")

      -- Set empty title if applicable
      if v.count == 0 then
        vim.api.nvim_buf_set_lines(v.bufnr, 0, 1, false, { v.title })
        local linnr = 1
        vim.api.nvim_buf_set_extmark(
          v.bufnr,
          ns_id,
          linnr - 1,
          0,
          { end_row = linnr - 1, end_col = string.len(v.title), hl_group = "TitleHighlight" }
        )
      end
      M.switch_can_edit_bufs(false, v.bufnr)
    end
  end
end

---@param tree NuiTree
M.get_url = function(tree)
  local current_node = tree:get_node()
  local note_node = M.get_note_node(tree, current_node)
  if note_node == nil then
    return
  end
  local url = note_node.url
  if url == nil then
    u.notify("Could not get URL of note", vim.log.levels.ERROR)
    return
  end
  return url
end

---@param tree NuiTree
M.open_in_browser = function(tree)
  local url = M.get_url(tree)
  if url ~= nil then
    u.open_in_browser(url)
  end
end

---@param tree NuiTree
M.copy_node_url = function(tree)
  local url = M.get_url(tree)
  if url ~= nil then
    vim.fn.setreg("+", url)
    u.notify("Copied '" .. url .. "' to clipboard", vim.log.levels.INFO)
  end
end

-- For developers!
M.print_node = function(tree)
  local current_node = tree:get_node()
  vim.print(current_node)
end

---Check if type of node is note or note body
---@param node NuiTree.Node?
---@return boolean
M.is_node_note = function(node)
  if node and (node.type == "note_body" or node.type == "note") then
    return true
  else
    return false
  end
end

---Get root node
---@param tree NuiTree
---@param node NuiTree.Node?
---@return NuiTree.Node?
M.get_root_node = function(tree, node)
  if not node then
    return nil
  end
  if node.type == "note_body" or node.type == "note" and not node.is_root then
    local parent_id = node:get_parent_id()
    return M.get_root_node(tree, tree:get_node(parent_id))
  elseif node.is_root then
    return node
  end
end

---Get note node
---@param tree NuiTree
---@param node NuiTree.Node?
---@return NuiTree.Node?
M.get_note_node = function(tree, node)
  if not node then
    return nil
  end

  if node.type == "note_body" then
    local parent_id = node:get_parent_id()
    if parent_id == nil then
      return node
    end
    return M.get_note_node(tree, tree:get_node(parent_id))
  elseif node.type == "note" then
    return node
  end
end

---Takes a node and returns the line where the note is positioned in the new SHA. If
---the line is not in the new SHA, returns nil
---@param node NuiTree.Node
---@return number|nil
local function get_new_line(node)
  ---@type GitlabLineRange|nil
  local range = node.range
  if range == nil then
    return node.new_line
  end

  local _, new_start_line = indicators_common.parse_line_code(range.start.line_code)
  return new_start_line
end

---Takes a node and returns the line where the note is positioned in the old SHA. If
---the line is not in the old SHA, returns nil
---@param node NuiTree.Node
---@return number|nil
local function get_old_line(node)
  ---@type GitlabLineRange|nil
  local range = node.range
  if range == nil then
    return node.old_line
  end

  local old_start_line, _ = indicators_common.parse_line_code(range.start.line_code)
  return old_start_line
end

---@param id string|integer
---@return integer|nil line_number
---@return boolean is_new_sha True if line number refers to NEW SHA
M.get_line_number = function(id)
  ---@type Discussion|DraftNote|nil
  local d_or_n
  d_or_n = List.new(state.DISCUSSION_DATA and state.DISCUSSION_DATA.discussions or {}):find(function(d)
    return d.id == id
  end) or List.new(state.DRAFT_NOTES or {}):find(function(d)
    return d.id == id
  end)

  if d_or_n == nil then
    return nil, true
  end

  local first_note = indicators_common.get_first_note(d_or_n)
  local is_new_sha = indicators_common.is_new_sha(d_or_n)
  return ((is_new_sha and first_note.position.new_line or first_note.position.old_line) or 1), is_new_sha
end

---Return the start and end line numbers for the note range. The range is calculated from the line
---codes but the position itself is based on either the `new_line` or `old_line`.
---@param old_line integer|nil The line number in the OLD version
---@param new_line integer|nil The line number in the NEW version
---@param start_line_code string The line code for the start of the range
---@param end_line_code string The line code for the end of the range
---@return integer start_line
---@return integer end_line
---@return boolean is_new_sha True if line range refers to NEW SHA
M.get_line_numbers_for_range = function(old_line, new_line, start_line_code, end_line_code)
  local old_start_line, new_start_line = indicators_common.parse_line_code(start_line_code)
  local old_end_line, new_end_line = indicators_common.parse_line_code(end_line_code)
  if old_line ~= nil and old_start_line ~= 0 then
    local range = old_end_line - old_start_line
    return (old_line - range), old_line, false
  elseif new_line ~= nil then
    local range = new_end_line - new_start_line
    return (new_line - range), new_line, true
  else
    u.notify("Error getting new or old line for range", vim.log.levels.ERROR)
    return 1, 1, false
  end
end

---@param root_node NuiTree.Node
---@return integer|nil line_number
---@return boolean is_new_sha True if line number refers to NEW SHA
M.get_line_number_from_node = function(root_node)
  if root_node.range then
    local line_number, _, is_new_sha = M.get_line_numbers_for_range(
      root_node.old_line,
      root_node.new_line,
      root_node.range.start.line_code,
      root_node.range["end"].line_code
    )
    return line_number, is_new_sha
  else
    return M.get_line_number(root_node.id)
  end
end

-- This function (settings.keymaps.discussion_tree.jump_to_reviewer) will jump the cursor to the reviewer's location associated with the note. The implementation depends on the reviewer
M.jump_to_reviewer = function(tree, callback)
  local node = tree:get_node()
  local root_node = M.get_root_node(tree, node)
  if root_node == nil then
    u.notify("Could not get discussion node", vim.log.levels.ERROR)
    return
  end
  local line_number, is_new_sha = M.get_line_number_from_node(root_node)
  if line_number == nil then
    u.notify("Could not get line number", vim.log.levels.ERROR)
    return
  end
  reviewer.jump(root_node.file_name, line_number, is_new_sha)
  callback()
end

-- This function (settings.keymaps.discussion_tree.jump_to_file) will jump to the file changed in a new tab
M.jump_to_file = function(tree)
  local node = tree:get_node()
  local root_node = M.get_root_node(tree, node)
  if root_node == nil then
    u.notify("Could not get discussion node", vim.log.levels.ERROR)
    return
  end
  if root_node.file_name == nil then
    u.notify("This comment was not left on a particular location", vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(root_node.file_name) == 0 then
    u.notify(
      string.format("The file %s for which the comment was made doesn't exist in HEAD.", root_node.file_name),
      vim.log.levels.WARN
    )
    return
  end
  vim.cmd.tabnew()
  local line_number = get_new_line(root_node) or get_old_line(root_node)
  if line_number == nil then
    line_number = 1
  end
  local bufnr = vim.fn.bufnr(root_node.file_name)
  if bufnr ~= -1 then
    vim.cmd("buffer " .. bufnr)
    vim.api.nvim_win_set_cursor(0, { line_number, 0 })
    return
  end

  -- If buffer is not already open, open it
  vim.cmd("edit " .. root_node.file_name)
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
end

return M
