-- This module is responsible for the notes and comments discussion tree.
-- That includes things like editing existing notes in the tree,
-- replying to notes in the tree, and marking discussions as resolved/unresolved.
-- Draft notes are managed separately, under lua/gitlab/actions/draft_notes/init.lua
local Split = require("nui.split")
local Popup = require("nui.popup")
local NuiTree = require("nui.tree")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local common = require("gitlab.actions.common")
local List = require("gitlab.utils.list")
local tree_utils = require("gitlab.actions.discussions.tree")
local discussions_tree = require("gitlab.actions.discussions.tree")
local draft_notes = require("gitlab.actions.draft_notes")
local signs = require("gitlab.indicators.signs")
local diagnostics = require("gitlab.indicators.diagnostics")
local winbar = require("gitlab.actions.discussions.winbar")
local help = require("gitlab.actions.help")
local emoji = require("gitlab.emoji")

local M = {
  split_visible = false,
  split = nil,
  ---@type number
  linked_bufnr = nil,
  ---@type number
  unlinked_bufnr = nil,
  ---@type NuiTree|nil
  discussion_tree = nil,
  ---@type NuiTree|nil
  unlinked_discussion_tree = nil,
}

---Re-fetches all discussions and re-renders the relevant view
---@param unlinked boolean
---@param all boolean|nil
M.rebuild_view = function(unlinked, all)
  M.load_discussions(function()
    if all then
      M.rebuild_unlinked_discussion_tree()
      M.rebuild_discussion_tree()
    elseif unlinked then
      M.rebuild_unlinked_discussion_tree()
    else
      M.rebuild_discussion_tree()
    end
    state.discussion_tree.last_updated = os.time()
    M.refresh_diagnostics()
  end)
end

---Makes API call to get the discussion data, stores it in the state, and calls the callback
---@param callback function|nil
M.load_discussions = function(callback)
  state.discussion_tree.last_updated = nil
  state.load_new_state("discussion_data", function(data)
    if not state.DISCUSSION_DATA then
      state.DISCUSSION_DATA = {}
    end
    state.DISCUSSION_DATA.discussions = u.ensure_table(data.discussions)
    state.DISCUSSION_DATA.unlinked_discussions = u.ensure_table(data.unlinked_discussions)
    state.DISCUSSION_DATA.emojis = u.ensure_table(data.emojis)
    if callback ~= nil then
      callback()
    end
  end)
end

---Initialize everything for discussions like setup of signs, callbacks for reviewer, etc.
M.initialize_discussions = function()
  state.discussion_tree.last_updated = os.time()
  signs.setup_signs()
  reviewer.set_callback_for_file_changed(function(args)
    reviewer.update_winid_for_buffer(args.buf)
  end)
  reviewer.set_callback_for_reviewer_enter(function()
    M.refresh_diagnostics()
  end)
  reviewer.set_callback_for_buf_read(function(args)
    vim.api.nvim_buf_set_option(args.buf, "modifiable", false)
    reviewer.set_keymaps(args.buf)
    reviewer.set_reviewer_autocommands(args.buf)
  end)
  reviewer.set_callback_for_reviewer_leave(function()
    signs.clear_signs()
    diagnostics.clear_diagnostics()
  end)
end

--- Take existing data and refresh the diagnostics, the winbar, and the signs
M.refresh_diagnostics = function()
  if state.settings.discussion_signs.enabled then
    diagnostics.refresh_diagnostics()
  end
  common.add_empty_titles()
end

---Opens the discussion tree, sets the keybindings. It also
---creates the tree for notes (which are not linked to specific lines of code)
---@param callback function?
M.open = function(callback)
  state.DISCUSSION_DATA.discussions = u.ensure_table(state.DISCUSSION_DATA.discussions)
  state.DISCUSSION_DATA.unlinked_discussions = u.ensure_table(state.DISCUSSION_DATA.unlinked_discussions)
  state.DRAFT_NOTES = u.ensure_table(state.DRAFT_NOTES)

  -- Make buffers, get and set buffer numbers, set filetypes
  local split, linked_bufnr, unlinked_bufnr = M.create_split_and_bufs()
  M.split = split
  M.linked_bufnr = linked_bufnr
  M.unlinked_bufnr = unlinked_bufnr

  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.split.bufnr })
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.unlinked_bufnr })
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.linked_bufnr })

  M.split = split
  M.split_visible = true
  split:mount()

  -- Initialize winbar module with data from buffers
  winbar.set_buffers(M.linked_bufnr, M.unlinked_bufnr)
  winbar.switch_view_type(state.settings.discussion_tree.default_view)

  local current_window = vim.api.nvim_get_current_win() -- Save user's current window in case they switched while content was loading
  vim.api.nvim_set_current_win(M.split.winid)

  common.switch_can_edit_bufs(true, M.linked_bufnr, M.unlinked_bufnr)
  M.rebuild_discussion_tree()
  M.rebuild_unlinked_discussion_tree()

  -- Set default buffer
  local default_buffer = winbar.bufnr_map[state.settings.discussion_tree.default_view]
  vim.api.nvim_set_current_buf(default_buffer)
  common.switch_can_edit_bufs(false, M.linked_bufnr, M.unlinked_bufnr)

  vim.api.nvim_set_current_win(current_window)
  if type(callback) == "function" then
    callback()
  end

  vim.schedule(function()
    M.refresh_diagnostics()
  end)
end

-- Clears the discussion state and unmounts the split
M.close = function()
  if M.split then
    M.split:unmount()
  end
  M.split_visible = false
  M.discussion_tree = nil
end

---Move to the discussion tree at the discussion from diagnostic on current line.
M.move_to_discussion_tree = function()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local d = vim.diagnostic.get(0, { namespace = diagnostics.diagnostics_namespace, lnum = current_line - 1 })

  ---Function used to jump to the discussion tree after the menu selection.
  local jump_after_menu_selection = function(diagnostic)
    ---Function used to jump to the discussion tree after the discussion tree is opened.
    local jump_after_tree_opened = function()
      -- All diagnostics in `diagnotics_namespace` have diagnostic_id
      local discussion_id = diagnostic.user_data.discussion_id
      local discussion_node, line_number = M.discussion_tree:get_node("-" .. discussion_id)
      if discussion_node == {} or discussion_node == nil then
        u.notify("Discussion not found", vim.log.levels.WARN)
        return
      end
      if not discussion_node:is_expanded() then
        for _, child in ipairs(discussion_node:get_child_ids()) do
          M.discussion_tree:get_node(child):expand()
        end
        discussion_node:expand()
      end
      M.discussion_tree:render()
      vim.api.nvim_win_set_cursor(M.split.winid, { line_number, 0 })
      vim.api.nvim_set_current_win(M.split.winid)
    end

    if not M.split_visible then
      M.toggle(jump_after_tree_opened)
    else
      jump_after_tree_opened()
    end
  end

  if #d == 0 then
    if state.settings.reviewer_settings.jump_with_no_diagnostics then
      vim.api.nvim_win_set_cursor(M.split.winid, { M.last_row, M.last_column })
      vim.api.nvim_set_current_win(M.split.winid)
    else
      u.notify("No diagnostics for this line.", vim.log.levels.WARN)
    end
    return
  elseif #d > 1 then
    vim.ui.select(d, {
      prompt = "Choose discussion to jump to",
      format_item = function(diagnostic)
        return diagnostic.message
      end,
    }, function(diagnostic)
      if not diagnostic then
        return
      end
      jump_after_menu_selection(diagnostic)
    end)
  else
    jump_after_menu_selection(d[1])
  end
end

-- The reply popup will mount in a window when you trigger it (settings.keymaps.discussion_tree.reply) when hovering over a node in the discussion tree.
M.reply = function(tree)
  if M.is_draft_note(tree) then
    u.notify("Gitlab does not support replying to draft notes", vim.log.levels.WARN)
    return
  end

  local node = tree:get_node()
  local discussion_node = common.get_root_node(tree, node)

  if discussion_node == nil then
    u.notify("Could not get discussion root", vim.log.levels.ERROR)
    return
  end

  local discussion_id = tostring(discussion_node.id)
  local comment = require("gitlab.actions.comment")
  local unlinked = tree.bufnr == M.unlinked_bufnr
  local layout = comment.create_comment_layout({
    ranged = false,
    discussion_id = discussion_id,
    unlinked = unlinked,
    reply = true,
  })

  layout:mount()
end

-- This function (settings.keymaps.discussion_tree.delete_comment) will trigger a popup prompting you to delete the current comment
M.delete_comment = function(tree, unlinked)
  vim.ui.select({ "Confirm", "Cancel" }, {
    prompt = "Delete comment?",
  }, function(choice)
    if choice == "Confirm" then
      local current_node = tree:get_node()
      local note_node = common.get_note_node(tree, current_node)
      local root_node = common.get_root_node(tree, current_node)
      if note_node == nil or root_node == nil then
        u.notify("Could not get note or root node", vim.log.levels.ERROR)
        return
      end

      ---@type integer
      if M.is_draft_note(tree) then
        draft_notes.confirm_delete_draft_note(note_node.id, unlinked)
      else
        local note_id = note_node.is_root and root_node.root_note_id or note_node.id
        local comment = require("gitlab.actions.comment")
        comment.confirm_delete_comment(note_id, root_node.id, unlinked)
      end
    end
  end)
end

-- This function (settings.keymaps.discussion_tree.edit_comment) will open the edit popup for the current comment in the discussion tree
M.edit_comment = function(tree, unlinked)
  local edit_popup = Popup(popup.create_popup_state("Edit Comment", state.settings.popup.edit))
  local current_node = tree:get_node()
  local note_node = common.get_note_node(tree, current_node)
  local root_node = common.get_root_node(tree, current_node)
  if note_node == nil or root_node == nil then
    u.notify("Could not get root or note node", vim.log.levels.ERROR)
    return
  end

  popup.set_up_autocommands(edit_popup, nil, vim.api.nvim_get_current_win())

  edit_popup:mount()

  -- Gather all lines from immediate children that aren't note nodes
  local lines = List.new(note_node:get_child_ids()):reduce(function(agg, child_id)
    local child_node = tree:get_node(child_id)
    if not child_node:has_children() then
      local line = tree:get_node(child_id).text
      table.insert(agg, line)
    end
    return agg
  end, {})

  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)

  -- Draft notes module handles edits for draft notes
  if M.is_draft_note(tree) then
    popup.set_popup_keymaps(
      edit_popup,
      draft_notes.confirm_edit_draft_note(note_node.id, unlinked),
      nil,
      popup.editable_popup_opts
    )
  else
    local comment = require("gitlab.actions.comment")
    popup.set_popup_keymaps(
      edit_popup,
      comment.confirm_edit_comment(tostring(root_node.id), tonumber(note_node.root_note_id or note_node.id), unlinked),
      nil,
      popup.editable_popup_opts
    )
  end
end

-- This function (settings.keymaps.discussion_tree.toggle_discussion_resolved) will toggle the resolved status of the current discussion and send the change to the Go server
M.toggle_discussion_resolved = function(tree)
  local note = tree:get_node()
  if note == nil then
    return
  end

  -- Switch to the root node to enable toggling from child nodes and note bodies
  if not note.resolvable and common.is_node_note(note) then
    note = common.get_root_node(tree, note)
  end
  if note == nil then
    return
  end

  local body = {
    discussion_id = note.id,
    resolved = not note.resolved,
  }

  job.run_job("/mr/discussions/resolve", "PUT", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    local unlinked = tree.bufnr == M.unlinked_bufnr
    M.rebuild_view(unlinked)
  end)
end

---Opens a popup prompting the user to choose an emoji to attach to the current node
---@param tree any
---@param unlinked boolean
M.add_emoji_to_note = function(tree, unlinked)
  local node = tree:get_node()
  local note_node = common.get_note_node(tree, node)
  local root_node = common.get_root_node(tree, node)
  local note_id = tonumber(note_node.is_root and root_node.root_note_id or note_node.id)
  local emojis = require("gitlab.emoji").emoji_list
  emoji.pick_emoji(emojis, function(name)
    local body = { emoji = name, note_id = note_id }
    job.run_job("/mr/awardable/note/", "POST", body, function()
      u.notify("Emoji added", vim.log.levels.INFO)
      M.rebuild_view(unlinked)
    end)
  end)
end

---Opens a popup prompting the user to choose an emoji to remove from the current node
---@param tree any
---@param unlinked boolean
M.delete_emoji_from_note = function(tree, unlinked)
  local node = tree:get_node()
  local note_node = common.get_note_node(tree, node)
  local root_node = common.get_root_node(tree, node)
  local note_id = tonumber(note_node.is_root and root_node.root_note_id or note_node.id)
  local note_id_str = tostring(note_id)

  local e = require("gitlab.emoji")

  local emojis = {}
  local current_emojis = state.DISCUSSION_DATA.emojis[note_id_str]
  for _, current_emoji in ipairs(current_emojis) do
    if state.USER.id == current_emoji.user.id then
      table.insert(emojis, e.emoji_map[current_emoji.name])
    end
  end

  emoji.pick_emoji(emojis, function(name)
    local awardable_id
    for _, current_emoji in ipairs(current_emojis) do
      if current_emoji.name == name and current_emoji.user.id == state.USER.id then
        awardable_id = current_emoji.id
        break
      end
    end
    job.run_job(string.format("/mr/awardable/note/%d/%d", note_id, awardable_id), "DELETE", nil, function()
      u.notify("Emoji removed", vim.log.levels.INFO)
      M.rebuild_view(unlinked)
    end)
  end)
end

--
-- 🌲 Helper Functions
--

---Used to collect all nodes in a tree prior to rebuilding it, so that they
---can be re-expanded before render
---@param tree any
---@return table
M.gather_expanded_node_ids = function(tree)
  -- Gather all nodes for later expansion, after rebuild
  local ids = {}
  for id, node in pairs(tree and tree.nodes.by_id or {}) do
    if node._is_expanded then
      table.insert(ids, id)
    end
  end
  return ids
end

---Rebuilds the discussion tree, which contains all comments and draft comments
---linked to specific places in the code.
M.rebuild_discussion_tree = function()
  if M.linked_bufnr == nil then
    return
  end

  local current_node = discussions_tree.get_node_at_cursor(M.discussion_tree, M.last_node_at_cursor)

  local expanded_node_ids = M.gather_expanded_node_ids(M.discussion_tree)
  common.switch_can_edit_bufs(true, M.linked_bufnr, M.unlinked_bufnr)

  vim.api.nvim_buf_set_lines(M.linked_bufnr, 0, -1, false, {})
  local existing_comment_nodes = discussions_tree.add_discussions_to_table(state.DISCUSSION_DATA.discussions, false)
  local draft_comment_nodes = draft_notes.add_draft_notes_to_table(false)

  -- Combine inline draft notes with regular comments
  local all_nodes = u.join(draft_comment_nodes, existing_comment_nodes)

  local discussion_tree = NuiTree({
    nodes = all_nodes,
    bufnr = M.linked_bufnr,
    prepare_node = tree_utils.nui_tree_prepare_node,
  })

  -- Re-expand already expanded nodes
  for _, id in ipairs(expanded_node_ids) do
    tree_utils.open_node_by_id(discussion_tree, id)
  end
  discussion_tree:render()
  discussions_tree.restore_cursor_position(M.split.winid, discussion_tree, current_node)

  M.set_tree_keymaps(discussion_tree, M.linked_bufnr, false)
  M.discussion_tree = discussion_tree
  common.switch_can_edit_bufs(false, M.linked_bufnr, M.unlinked_bufnr)
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.linked_bufnr })
  state.discussion_tree.resolved_expanded = false
  state.discussion_tree.unresolved_expanded = false
end

---Rebuilds the unlinked discussion tree, which contains all notes and draft notes.
M.rebuild_unlinked_discussion_tree = function()
  if M.unlinked_bufnr == nil then
    return
  end

  local current_node = discussions_tree.get_node_at_cursor(M.unlinked_discussion_tree, M.last_node_at_cursor)

  local expanded_node_ids = M.gather_expanded_node_ids(M.unlinked_discussion_tree)
  common.switch_can_edit_bufs(true, M.linked_bufnr, M.unlinked_bufnr)
  vim.api.nvim_buf_set_lines(M.unlinked_bufnr, 0, -1, false, {})
  local existing_note_nodes =
    discussions_tree.add_discussions_to_table(state.DISCUSSION_DATA.unlinked_discussions, true)
  local draft_comment_nodes = draft_notes.add_draft_notes_to_table(true)

  -- Combine draft notes with regular notes
  local all_nodes = u.join(draft_comment_nodes, existing_note_nodes)

  local unlinked_discussion_tree = NuiTree({
    nodes = all_nodes,
    bufnr = M.unlinked_bufnr,
    prepare_node = tree_utils.nui_tree_prepare_node,
  })

  -- Re-expand already expanded nodes
  for _, id in ipairs(expanded_node_ids) do
    tree_utils.open_node_by_id(unlinked_discussion_tree, id)
  end
  unlinked_discussion_tree:render()
  discussions_tree.restore_cursor_position(M.split.winid, unlinked_discussion_tree, current_node)

  M.set_tree_keymaps(unlinked_discussion_tree, M.unlinked_bufnr, true)
  M.unlinked_discussion_tree = unlinked_discussion_tree
  common.switch_can_edit_bufs(false, M.linked_bufnr, M.unlinked_bufnr)
  state.unlinked_discussion_tree.resolved_expanded = false
  state.unlinked_discussion_tree.unresolved_expanded = false
end

---Adds a discussion to the global state. Works for both notes (unlinked) and diff-linked comments,
M.add_discussion = function(arg)
  local discussion = arg.data.discussion
  if arg.unlinked then
    if type(state.DISCUSSION_DATA.unlinked_discussions) ~= "table" then
      state.DISCUSSION_DATA.unlinked_discussions = {}
    end
    table.insert(state.DISCUSSION_DATA.unlinked_discussions, 1, discussion)
    M.rebuild_unlinked_discussion_tree()
  else
    if type(state.DISCUSSION_DATA.discussions) ~= "table" then
      state.DISCUSSION_DATA.discussions = {}
    end
    table.insert(state.DISCUSSION_DATA.discussions, 1, discussion)
    M.rebuild_discussion_tree()
  end
end

---Creates the split for the discussion tree and returns it, with both buffer numbers
---@return NuiSplit
---@return integer
---@return integer
M.create_split_and_bufs = function()
  local position = state.settings.discussion_tree.position
  local size = state.settings.discussion_tree.size
  local relative = state.settings.discussion_tree.relative

  local split = Split({
    relative = relative,
    position = position,
    size = size,
  })

  local linked_bufnr = vim.api.nvim_create_buf(true, false)
  local unlinked_bufnr = vim.api.nvim_create_buf(true, false)

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = linked_bufnr,
    callback = function()
      M.last_row, M.last_column = unpack(vim.api.nvim_win_get_cursor(0))
      M.last_node_at_cursor = M.discussion_tree and M.discussion_tree:get_node() or nil
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = unlinked_bufnr,
    callback = function()
      M.last_node_at_cursor = M.unlinked_discussion_tree and M.unlinked_discussion_tree:get_node() or nil
    end,
  })

  return split, linked_bufnr, unlinked_bufnr
end

---Check if type of current node is note or note body
---@param tree NuiTree
---@return boolean
M.is_current_node_note = function(tree)
  return common.is_node_note(tree:get_node())
end

M.set_tree_keymaps = function(tree, bufnr, unlinked)
  -- Require keymaps only after user settings have been merged with defaults
  local keymaps = require("gitlab.state").settings.keymaps
  if keymaps.disable_all or keymaps.discussion_tree.disable_all then
    return
  end

  ---Keybindings only relevant for linked (comment) view
  if not unlinked then
    if keymaps.discussion_tree.jump_to_file then
      vim.keymap.set("n", keymaps.discussion_tree.jump_to_file, function()
        if M.is_current_node_note(tree) then
          common.jump_to_file(tree)
        end
      end, { buffer = bufnr, desc = "Jump to file", nowait = keymaps.discussion_tree.jump_to_file_nowait })
    end

    if keymaps.discussion_tree.jump_to_reviewer then
      vim.keymap.set("n", keymaps.discussion_tree.jump_to_reviewer, function()
        if M.is_current_node_note(tree) then
          common.jump_to_reviewer(tree, M.refresh_diagnostics)
        end
      end, { buffer = bufnr, desc = "Jump to reviewer", nowait = keymaps.discussion_tree.jump_to_reviewer_nowait })
    end

    if keymaps.discussion_tree.toggle_tree_type then
      vim.keymap.set("n", keymaps.discussion_tree.toggle_tree_type, function()
        M.toggle_tree_type()
      end, {
        buffer = bufnr,
        desc = "Change tree type between `simple` and `by_file_name`",
        nowait = keymaps.discussion_tree.toggle_tree_type_nowait,
      })
    end
  end

  if keymaps.discussion_tree.refresh_data then
    vim.keymap.set("n", keymaps.discussion_tree.refresh_data, function()
      draft_notes.rebuild_view(unlinked, false)
    end, {
      buffer = bufnr,
      desc = "Refresh the view with Gitlab's APIs",
      nowait = keymaps.discussion_tree.refresh_data_nowait,
    })
  end

  if keymaps.discussion_tree.edit_comment then
    vim.keymap.set("n", keymaps.discussion_tree.edit_comment, function()
      if M.is_current_node_note(tree) then
        M.edit_comment(tree, unlinked)
      end
    end, { buffer = bufnr, desc = "Edit comment", nowait = keymaps.discussion_tree.edit_comment_nowait })
  end

  if keymaps.discussion_tree.publish_draft then
    vim.keymap.set("n", keymaps.discussion_tree.publish_draft, function()
      if M.is_draft_note(tree) then
        draft_notes.publish_draft(tree)
      end
    end, { buffer = bufnr, desc = "Publish draft", nowait = keymaps.discussion_tree.publish_draft_nowait })
  end

  if keymaps.discussion_tree.delete_comment then
    vim.keymap.set("n", keymaps.discussion_tree.delete_comment, function()
      if M.is_current_node_note(tree) then
        M.delete_comment(tree, unlinked)
      end
    end, { buffer = bufnr, desc = "Delete comment", nowait = keymaps.discussion_tree.delete_comment_nowait })
  end

  if keymaps.discussion_tree.toggle_draft_mode then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_draft_mode, function()
      M.toggle_draft_mode()
    end, {
      buffer = bufnr,
      desc = "Toggle between draft mode and live mode",
      nowait = keymaps.discussion_tree.toggle_draft_mode_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_sort_method then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_sort_method, function()
      M.toggle_sort_method()
    end, {
      buffer = bufnr,
      desc = "Toggle sort method",
      nowait = keymaps.discussion_tree.toggle_sort_method_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_resolved then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_resolved, function()
      if M.is_current_node_note(tree) and not M.is_draft_note(tree) then
        M.toggle_discussion_resolved(tree)
      end
    end, { buffer = bufnr, desc = "Toggle resolved", nowait = keymaps.discussion_tree.toggle_resolved_nowait })
  end

  if keymaps.discussion_tree.toggle_node then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_node, function()
      tree_utils.toggle_node(tree)
    end, { buffer = bufnr, desc = "Toggle node", nowait = keymaps.discussion_tree.toggle_node_nowait })
  end

  if keymaps.discussion_tree.toggle_all_discussions then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_all_discussions, function()
      tree_utils.toggle_nodes(M.split.winid, tree, unlinked, {
        toggle_resolved = true,
        toggle_unresolved = true,
        keep_current_open = state.settings.discussion_tree.keep_current_open,
      })
    end, {
      buffer = bufnr,
      desc = "Toggle all nodes",
      nowait = keymaps.discussion_tree.toggle_all_discussions_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_resolved_discussions then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_resolved_discussions, function()
      tree_utils.toggle_nodes(M.split.winid, tree, unlinked, {
        toggle_resolved = true,
        toggle_unresolved = false,
        keep_current_open = state.settings.discussion_tree.keep_current_open,
      })
    end, {
      buffer = bufnr,
      desc = "Toggle resolved nodes",
      nowait = keymaps.discussion_tree.toggle_resolved_discussions_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_unresolved_discussions then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_unresolved_discussions, function()
      tree_utils.toggle_nodes(M.split.winid, tree, unlinked, {
        toggle_resolved = false,
        toggle_unresolved = true,
        keep_current_open = state.settings.discussion_tree.keep_current_open,
      })
    end, {
      buffer = bufnr,
      desc = "Toggle unresolved nodes",
      nowait = keymaps.discussion_tree.toggle_unresolved_discussions_nowait,
    })
  end

  if keymaps.discussion_tree.reply then
    vim.keymap.set("n", keymaps.discussion_tree.reply, function()
      if M.is_current_node_note(tree) then
        M.reply(tree)
      end
    end, { buffer = bufnr, desc = "Reply", nowait = keymaps.discussion_tree.reply_nowait })
  end

  if keymaps.discussion_tree.switch_view then
    vim.keymap.set("n", keymaps.discussion_tree.switch_view, function()
      winbar.switch_view_type()
    end, {
      buffer = bufnr,
      desc = "Change view type between discussions and notes",
      nowait = keymaps.discussion_tree.switch_view_nowait,
    })
  end

  if keymaps.help then
    vim.keymap.set("n", keymaps.help, function()
      help.open()
    end, { buffer = bufnr, desc = "Open help popup", nowait = keymaps.help_nowait })
  end

  if keymaps.discussion_tree.open_in_browser then
    vim.keymap.set("n", keymaps.discussion_tree.open_in_browser, function()
      common.open_in_browser(tree)
    end, {
      buffer = bufnr,
      desc = "Open the note in your browser",
      nowait = keymaps.discussion_tree.open_in_browser_nowait,
    })
  end

  if keymaps.discussion_tree.copy_node_url then
    vim.keymap.set("n", keymaps.discussion_tree.copy_node_url, function()
      common.copy_node_url(tree)
    end, {
      buffer = bufnr,
      desc = "Copy the URL of the current node to clipboard",
      nowait = keymaps.discussion_tree.copy_node_url_nowait,
    })
  end

  if keymaps.discussion_tree.add_emoji then
    vim.keymap.set("n", keymaps.discussion_tree.add_emoji, function()
      M.add_emoji_to_note(tree, unlinked)
    end, {
      buffer = bufnr,
      desc = "Add an emoji reaction to the note/comment",
      nowait = keymaps.discussion_tree.add_emoji_nowait,
    })
  end

  if keymaps.discussion_tree.delete_emoji then
    vim.keymap.set("n", keymaps.discussion_tree.delete_emoji, function()
      M.delete_emoji_from_note(tree, unlinked)
    end, {
      buffer = bufnr,
      desc = "Remove an emoji reaction from the note/comment",
      nowait = keymaps.discussion_tree.delete_emoji_nowait,
    })
  end

  emoji.init_popup(tree, bufnr)
end

---Toggle comments tree type between "simple" and "by_file_name"
M.toggle_tree_type = function()
  if state.settings.discussion_tree.tree_type == "simple" then
    state.settings.discussion_tree.tree_type = "by_file_name"
  else
    state.settings.discussion_tree.tree_type = "simple"
  end
  M.rebuild_discussion_tree()
end

---Toggle between draft mode (comments posted as drafts) and live mode (comments are posted immediately)
M.toggle_draft_mode = function()
  state.settings.discussion_tree.draft_mode = not state.settings.discussion_tree.draft_mode
end

---Toggle between sorting by "original comment" (oldest at the top) or "latest reply" (newest at the
---top).
M.toggle_sort_method = function()
  if state.settings.discussion_tree.sort_by == "original_comment" then
    state.settings.discussion_tree.sort_by = "latest_reply"
  else
    state.settings.discussion_tree.sort_by = "original_comment"
  end
  winbar.update_winbar()
  M.rebuild_view(false, true)
end

---Indicates whether the node under the cursor is a draft note or not
---@param tree NuiTree
---@return boolean
M.is_draft_note = function(tree)
  local current_node = tree:get_node()
  local note_node = common.get_note_node(tree, current_node)
  if note_node and note_node.is_draft then
    return true
  end
  local root_node = common.get_root_node(tree, current_node)
  return root_node ~= nil and root_node.is_draft
end

return M
