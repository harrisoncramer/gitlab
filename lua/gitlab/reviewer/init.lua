-- This Module contains all of the reviewer code. This is the code
-- that parses or interacts with diffview directly, such as opening
-- and closing, getting metadata about the current view, and registering
-- callbacks for open/close actions.

local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local git = require("gitlab.git")
local hunks = require("gitlab.hunks")
local async = require("diffview.async")
local diffview_lib = require("diffview.lib")

local M = {
  is_open = false,
  bufnr = nil,
  tabnr = nil,
  stored_win = nil,
  buf_winids = {},
}

-- Checks for legacy installations, only Diffview is supported.
M.init = function()
  if state.settings.reviewer ~= "diffview" then
    vim.notify(
      string.format("gitlab.nvim could not find reviewer %s, only diffview is supported", state.settings.reviewer),
      vim.log.levels.ERROR
    )
  end
end

-- Opens the reviewer window.
M.open = function()
  local diff_refs = state.INFO.diff_refs
  if diff_refs == nil then
    u.notify("Gitlab did not provide diff refs required to review this MR", vim.log.levels.ERROR)
    return
  end

  if diff_refs.base_sha == "" or diff_refs.head_sha == "" then
    u.notify("Merge request contains no changes", vim.log.levels.ERROR)
    return
  end

  local diffview_open_command = "DiffviewOpen"

  if state.settings.reviewer_settings.diffview.imply_local then
    local has_clean_tree, err = git.has_clean_tree()
    if err ~= nil then
      return
    end
    if has_clean_tree then
      diffview_open_command = diffview_open_command .. " --imply-local"
    else
      u.notify(
        "Your working tree has changes, cannot use 'imply_local' setting for gitlab reviews.\n Stash or commit all changes to use.",
        vim.log.levels.WARN
      )
      state.settings.reviewer_settings.diffview.imply_local = false
    end
  end

  vim.api.nvim_command(string.format("%s %s..%s", diffview_open_command, diff_refs.base_sha, diff_refs.head_sha))

  M.is_open = true
  local cur_view = diffview_lib.get_current_view()
  M.diffview_layout = cur_view.cur_layout
  M.tabnr = vim.api.nvim_get_current_tabpage()

  if state.settings.discussion_diagnostic ~= nil or state.settings.discussion_sign ~= nil then
    u.notify(
      "Diagnostics are now configured as settings.discussion_signs, see :h gitlab.nvim.signs-and-diagnostics",
      vim.log.levels.WARN
    )
  end

  -- Register Diffview hook for close event to set tab page # to nil
  local on_diffview_closed = function(view)
    if view.tabpage == M.tabnr then
      M.tabnr = nil
    end
  end
  require("diffview.config").user_emitter:on("view_closed", function(_, args)
    if M.tabnr == args.tabpage then
      M.is_open = false
      on_diffview_closed(args)
    end
  end)

  if state.settings.discussion_tree.auto_open then
    local discussions = require("gitlab.actions.discussions")
    discussions.close()
    require("gitlab").toggle_discussions() -- Fetches data and opens discussions
  end

  git.check_current_branch_up_to_date_on_remote(vim.log.levels.WARN)
  git.check_mr_in_good_condition()
end

-- Closes the reviewer and cleans up
M.close = function()
  vim.cmd("DiffviewClose")
  local discussions = require("gitlab.actions.discussions")
  discussions.close()
end

--- Jumps to the location provided in the reviewer window
---@param file_name string
---@param line_number number
---@param new_buffer boolean
M.jump = function(file_name, line_number, new_buffer)
  if M.tabnr == nil then
    u.notify("Can't jump to Diffvew. Is it open?", vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_set_current_tabpage(M.tabnr)
  local view = diffview_lib.get_current_view()
  if view == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end

  local files = view.panel:ordered_file_list()
  local file = List.new(files):find(function(file)
    return file.path == file_name
  end)
  if file == nil then
    u.notify(
      string.format("The file %s for which the comment was made doesn't exist in HEAD.", file_name),
      vim.log.levels.WARN
    )
    return
  end
  async.await(view:set_file(file))

  local layout = view.cur_layout
  local number_of_lines
  if new_buffer then
    layout.b:focus()
    number_of_lines = u.get_buffer_length(layout.b.file.bufnr)
  else
    layout.a:focus()
    number_of_lines = u.get_buffer_length(layout.a.file.bufnr)
  end
  if line_number > number_of_lines then
    u.notify("Diagnostic position outside buffer. Jumping to last line instead.", vim.log.levels.WARN)
    line_number = number_of_lines
  end
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
  u.open_fold_under_cursor()
  vim.cmd("normal! zz")
end

---Get the data from diffview, such as line information and file name. May be used by
---other modules such as the comment module to create line codes or set diagnostics
---@return DiffviewInfo | nil
M.get_reviewer_data = function()
  local view = diffview_lib.get_current_view()
  local layout = view.cur_layout
  local old_win = u.get_window_id_by_buffer_id(layout.a.file.bufnr)
  local new_win = u.get_window_id_by_buffer_id(layout.b.file.bufnr)

  if old_win == nil or new_win == nil then
    u.notify("Error getting window IDs for current files", vim.log.levels.ERROR)
    return
  end

  local current_file = M.get_current_file_path()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local new_line = vim.api.nvim_win_get_cursor(new_win)[1]
  local old_line = vim.api.nvim_win_get_cursor(old_win)[1]

  local is_current_sha_focused = M.is_current_sha_focused()

  local modification_type = hunks.get_modification_type(old_line, new_line, is_current_sha_focused)
  if modification_type == nil then
    u.notify("Error getting modification type", vim.log.levels.ERROR)
    return
  end

  if modification_type == "bad_file_unmodified" then
    u.notify("Comments on unmodified lines will be placed in the old file", vim.log.levels.WARN)
  end

  local current_bufnr = is_current_sha_focused and layout.b.file.bufnr or layout.a.file.bufnr
  local opposite_bufnr = is_current_sha_focused and layout.a.file.bufnr or layout.b.file.bufnr
  local old_sha_win_id = u.get_window_id_by_buffer_id(layout.a.file.bufnr)
  local new_sha_win_id = u.get_window_id_by_buffer_id(layout.b.file.bufnr)

  return {
    file_name = layout.a.file.path,
    old_file_name = M.is_file_renamed() and layout.b.file.path or "",
    old_line_from_buf = old_line,
    new_line_from_buf = new_line,
    modification_type = modification_type,
    new_sha_win_id = new_sha_win_id,
    current_bufnr = current_bufnr,
    old_sha_win_id = old_sha_win_id,
    opposite_bufnr = opposite_bufnr,
  }
end

---Return whether user is focused on the new version of the file
---@return boolean
M.is_current_sha_focused = function()
  local view = diffview_lib.get_current_view()
  local layout = view.cur_layout
  local b_win = u.get_window_id_by_buffer_id(layout.b.file.bufnr)
  local a_win = u.get_window_id_by_buffer_id(layout.a.file.bufnr)
  local current_win = require("gitlab.actions.comment").current_win
  if a_win ~= current_win and b_win ~= current_win then
    current_win = M.stored_win
    M.stored_win = nil
  end
  return current_win == b_win
end

---Get currently shown file data
M.get_current_file_data = function()
  local view = diffview_lib.get_current_view()
  return view and view.panel and view.panel.cur_file
end

---Get currently shown file path
---@return string|nil
M.get_current_file_path = function()
  local file_data = M.get_current_file_data()
  return file_data and file_data.path
end

---Get currently shown file's old path
---@return string|nil
M.get_current_file_oldpath = function()
  local file_data = M.get_current_file_data()
  return file_data and file_data.oldpath
end

---Tell whether current file is renamed or not
---@return boolean|nil
M.is_file_renamed = function()
  local file_data = M.get_current_file_data()
  return file_data and file_data.status == "R"
end

---Tell whether current file has changes or not
---@return boolean|nil
M.does_file_have_changes = function()
  local file_data = M.get_current_file_data()
  return file_data.stats.additions > 0 or file_data.stats.deletions > 0
end

---Run callback every time the buffer in one of the two reviewer windows changes.
---@param callback fun(opts: table) - for more information about opts see callback in :h nvim_create_autocmd
M.set_callback_for_file_changed = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.file_changed", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewDiffBufWinEnter" },
    group = group,
    callback = function(...)
      if M.tabnr == vim.api.nvim_get_current_tabpage() then
        callback(...)
      end
    end,
  })
end

---Run callback the first time a new diff buffer is created and loaded into a window.
---@param callback fun(opts: table) - for more information about opts see callback in :h nvim_create_autocmd
M.set_callback_for_buf_read = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.buf_read", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewDiffBufRead" },
    group = group,
    callback = function(...)
      if vim.api.nvim_get_current_tabpage() == M.tabnr then
        callback(...)
      end
    end,
  })
end

---Run callback when the reviewer is closed or the user switches to another tab.
---@param callback fun(opts: table) - for more information about opts see callback in :h nvim_create_autocmd
M.set_callback_for_reviewer_leave = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.leave", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewViewLeave", "DiffviewViewClosed" },
    group = group,
    callback = function(...)
      if vim.api.nvim_get_current_tabpage() == M.tabnr then
        callback(...)
      end
    end,
  })
end

---Run callback when the reviewer is opened for the first time or the view is entered from another
---tab page.
---@param callback fun(opts: table) - for more information about opts see callback in :h nvim_create_autocmd
M.set_callback_for_reviewer_enter = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.enter", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewViewEnter", "DiffviewViewOpened" },
    group = group,
    callback = function(...)
      if vim.api.nvim_get_current_tabpage() == M.tabnr then
        callback(...)
      end
    end,
  })
end

---Create the line-wise visual selection in the range of the motion (or on the [count] number of
---lines) and execute the gitlab.nvim API function. After that, restore the cursor position and the
---original operatorfunc.
---@param callback string Name of the gitlab.nvim API function to call
M.execute_callback = function(callback)
  return function()
    vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { "'[V']" } }, {})
    local _, err = pcall(
      vim.api.nvim_cmd,
      { cmd = "lua", args = { ("require'gitlab'.%s()"):format(callback) }, mods = { lockmarks = true } },
      {}
    )
    vim.api.nvim_win_set_cursor(M.old_winnr, M.old_cursor_position)
    vim.opt.operatorfunc = M.old_opfunc
    if err ~= "" then
      u.notify_vim_error(err, vim.log.levels.ERROR)
    end
  end
end

---Set the operatorfunc that will work on the lines defined by the motion that follows after the
---operator mapping, and enter the operator-pending mode.
---@param cb string Name of the gitlab.nvim API function to call, e.g., "create_multiline_comment".
local function execute_operatorfunc(cb)
  M.old_opfunc = vim.opt.operatorfunc
  M.old_winnr = vim.api.nvim_get_current_win()
  M.old_cursor_position = vim.api.nvim_win_get_cursor(M.old_winnr)
  vim.opt.operatorfunc = ("v:lua.require'gitlab.reviewer'.execute_callback'%s'"):format(cb)
  -- Use the operator count before motion to allow, e.g., 2cc == c2c
  local count = M.operator_count > 0 and tostring(M.operator_count) or ""
  vim.api.nvim_feedkeys("g@" .. count, "n", false)
end

---Set keymaps for creating comments, suggestions and for jumping to discussion tree.
---@param bufnr integer Number of the buffer for which the keybindings will be created.
M.set_keymaps = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  -- Require keymaps only after user settings have been merged with defaults
  local keymaps = require("gitlab.state").settings.keymaps
  if keymaps.disable_all or keymaps.reviewer.disable_all then
    return
  end

  -- Set mappings for creating comments
  if keymaps.reviewer.create_comment ~= false then
    -- Set keymap for repeated operator keybinding
    vim.keymap.set("o", keymaps.reviewer.create_comment, function()
      -- The "V" in "V%d$" forces linewise motion, see `:h o_V`
      vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { string.format("V%d$", vim.v.count1) } }, {})
    end, {
      buffer = bufnr,
      desc = "Create comment for [count] lines",
      nowait = keymaps.reviewer.create_comment_nowait,
    })

    -- Set operator keybinding
    vim.keymap.set(
      "n",
      keymaps.reviewer.create_comment,
      function()
        M.operator_count = vim.v.count
        execute_operatorfunc("create_multiline_comment")
      end,
      { buffer = bufnr, desc = "Create comment for range of motion", nowait = keymaps.reviewer.create_comment_nowait }
    )
    vim.keymap.set("v", keymaps.reviewer.create_comment, function()
      require("gitlab").create_multiline_comment()
    end, {
      buffer = bufnr,
      desc = "Create comment for selected text",
      nowait = keymaps.reviewer.create_comment_nowait,
    })
  end

  -- Set mappings for creating suggestions
  if keymaps.reviewer.create_suggestion ~= false then
    -- Set keymap for repeated operator keybinding
    vim.keymap.set("o", keymaps.reviewer.create_suggestion, function()
      -- The "V" in "V%d$" forces linewise motion, see `:h o_V`
      vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { string.format("V%d$", vim.v.count1) } }, {})
    end, {
      buffer = bufnr,
      desc = "Create suggestion for [count] lines",
      nowait = keymaps.reviewer.create_suggestion_nowait,
    })

    -- Set operator keybinding
    vim.keymap.set("n", keymaps.reviewer.create_suggestion, function()
      M.operator_count = vim.v.count
      M.operator = keymaps.reviewer.create_suggestion
      execute_operatorfunc("create_comment_suggestion")
    end, {
      buffer = bufnr,
      desc = "Create suggestion for range of motion",
      nowait = keymaps.reviewer.create_suggestion_nowait,
    })

    -- Set visual mode keybinding
    vim.keymap.set("v", keymaps.reviewer.create_suggestion, function()
      require("gitlab").create_comment_suggestion()
    end, {
      buffer = bufnr,
      desc = "Create suggestion for selected text",
      nowait = keymaps.reviewer.create_suggestion_nowait,
    })
  end

  -- Set mapping for moving to discussion tree
  if keymaps.reviewer.move_to_discussion_tree ~= false then
    vim.keymap.set("n", keymaps.reviewer.move_to_discussion_tree, function()
      require("gitlab").move_to_discussion_tree_from_diagnostic()
    end, { buffer = bufnr, desc = "Move to discussion", nowait = keymaps.reviewer.move_to_discussion_tree_nowait })
  end
end

---Delete keymaps from reviewer buffers.
---@param bufnr integer Number of the buffer from which the keybindings will be removed.
local del_keymaps = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  -- Require keymaps only after user settings have been merged with defaults
  local keymaps = require("gitlab.state").settings.keymaps
  if keymaps.disable_all or keymaps.reviewer.disable_all then
    return
  end
  for _, func in ipairs({ "create_comment", "create_suggestion" }) do
    if keymaps.reviewer[func] ~= false then
      for _, mode in ipairs({ "n", "o", "v" }) do
        pcall(vim.api.nvim_buf_del_keymap, bufnr, mode, keymaps.reviewer[func])
      end
    end
  end
  if keymaps.reviewer.move_to_discussion_tree ~= false then
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", keymaps.reviewer.move_to_discussion_tree)
  end
end

--- Set up autocaommands that will take care of setting and unsetting buffer-local options and keymaps
M.set_reviewer_autocommands = function(bufnr)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.win_enter." .. bufnr, {})
  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if vim.api.nvim_get_current_win() == M.buf_winids[bufnr] then
        M.stored_win = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
        M.set_keymaps(bufnr)
      else
        if M.diffview_layout.b.id == M.buf_winids[bufnr] then
          vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
        end
        del_keymaps(bufnr)
      end
    end,
  })
end

--- Update the stored winid for a given reviewer buffer. This is necessary for the
--- M.set_reviewer_autocommands function to work correctly in cases like when the user closes one of
--- the original reviewer windows and Diffview automatically creates a new pair
--- of reviewer windows or the user wipes out a buffer and Diffview reloads it with a different ID.
M.update_winid_for_buffer = function(bufnr)
  M.buf_winids[bufnr] = vim.fn.bufwinid(bufnr)
end

return M
