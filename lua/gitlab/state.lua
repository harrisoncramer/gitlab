-- This module is responsible for holding and setting shared state between
-- modules, such as keybinding data and other settings and configuration.
-- This module is also responsible for ensuring that the state of the plugin
-- is valid via dependencies

local git = require("gitlab.git")
local u = require("gitlab.utils")
local M = {}

M.emoji_map = nil

---Returns a gitlab token, and a gitlab URL. Used to connect to gitlab.
---@return string|nil, string|nil, string|nil
M.default_auth_provider = function()
  local base_path, err = M.settings.config_path, nil
  if base_path == nil then
    base_path, err = git.base_dir()
  end

  if err ~= nil then
    return "", ""
  end

  local config_file_path = base_path .. M.settings.file_separator .. ".gitlab.nvim"
  local config_file_content = u.read_file(config_file_path, { remove_newlines = true })

  local file_properties = {}
  if config_file_content ~= nil then
    local file = assert(io.open(config_file_path, "r"))
    for line in file:lines() do
      for key, value in string.gmatch(line, "(.-)=(.-)$") do
        file_properties[key] = value
      end
    end
  end

  local auth_token = file_properties.auth_token or os.getenv("GITLAB_TOKEN")
  local gitlab_url = file_properties.gitlab_url or os.getenv("GITLAB_URL")

  return auth_token, gitlab_url, err
end

--- These are the default settings for the plugin
M.settings = {
  auth_provider = M.default_auth_provider,
  port = nil, -- choose random port
  debug = {
    go_request = false,
    go_response = false,
  },
  log_path = (vim.fn.stdpath("cache") .. "/gitlab.nvim.log"),
  config_path = nil,
  reviewer = "diffview",
  reviewer_settings = {
    jump_with_no_diagnostics = false,
    diffview = {
      imply_local = false,
    },
  },
  connection_settings = {
    insecure = false,
    remote = "origin",
  },
  attachment_dir = "",
  keymaps = {
    disable_all = false,
    help = "g?",
    global = {
      disable_all = false,
      add_assignee = "glaa",
      delete_assignee = "glad",
      add_label = "glla",
      delete_label = "glld",
      add_reviewer = "glra",
      delete_reviewer = "glrd",
      approve = "glA",
      revoke = "glR",
      merge = "glM",
      create_mr = "glC",
      choose_merge_request = "glc",
      start_review = "glS",
      summary = "gls",
      copy_mr_url = "glu",
      open_in_browser = "glo",
      create_note = "gln",
      pipeline = "glp",
      toggle_discussions = "gld",
      toggle_draft_mode = "glD",
      publish_all_drafts = "glP",
    },
    popup = {
      disable_all = false,
      next_field = "<Tab>",
      prev_field = "<S-Tab>",
      perform_action = "ZZ",
      perform_linewise_action = "ZA",
      discard_changes = "ZQ",
    },
    discussion_tree = {
      disable_all = false,
      add_emoji = "Ea",
      delete_emoji = "Ed",
      delete_comment = "dd",
      edit_comment = "e",
      reply = "r",
      toggle_resolved = "-",
      jump_to_file = "o",
      jump_to_reviewer = "a",
      open_in_browser = "b",
      copy_node_url = "u",
      switch_view = "c",
      toggle_tree_type = "i",
      publish_draft = "P",
      toggle_draft_mode = "D",
      toggle_node = "t",
      toggle_all_discussions = "T",
      toggle_resolved_discussions = "R",
      toggle_unresolved_discussions = "U",
      refresh_data = "<C-R>",
      print_node = "<leader>p",
    },
    reviewer = {
      disable_all = false,
      create_comment = "c",
      create_suggestion = "s",
      move_to_discussion_tree = "a",
    },
  },
  popup = {
    width = "40%",
    height = "60%",
    border = "rounded",
    opacity = 1.0,
    edit = nil,
    comment = nil,
    note = nil,
    help = nil,
    pipeline = nil,
    reply = nil,
    squash_message = nil,
    temp_registers = {},
  },
  discussion_tree = {
    expanders = {
      expanded = " ",
      collapsed = " ",
      indentation = "  ",
    },
    auto_open = true,
    default_view = "discussions",
    blacklist = {},
    keep_current_open = false,
    position = "left",
    size = "20%",
    relative = "editor",
    resolved = "✓",
    unresolved = "-",
    tree_type = "simple",
    draft_mode = false,
  },
  create_mr = {
    target = nil,
    template_file = nil,
    delete_branch = false,
    squash = false,
    fork = {
      enabled = false,
      forked_project_id = nil,
    },
    title_input = {
      width = 40,
      border = "rounded",
    },
  },
  choose_merge_request = {
    open_reviewer = true,
  },
  info = {
    enabled = true,
    horizontal = false,
    fields = {
      "author",
      "created_at",
      "updated_at",
      "merge_status",
      "draft",
      "conflicts",
      "assignees",
      "reviewers",
      "pipeline",
      "branch",
      "target_branch",
      "delete_branch",
      "squash",
      "labels",
    },
  },
  discussion_signs = {
    enabled = true,
    skip_resolved_discussion = false,
    severity = vim.diagnostic.severity.INFO,
    virtual_text = false,
    use_diagnostic_signs = true,
    priority = 100,
    icons = {
      comment = "→|",
      range = " |",
    },
    skip_old_revision_discussion = false,
  },
  pipeline = {
    created = "",
    pending = "",
    preparing = "",
    scheduled = "",
    running = "",
    canceled = "↪",
    skipped = "↪",
    success = "✓",
    failed = "",
  },
  go_server_running = false,
  is_gitlab_project = false,
  colors = {
    discussion_tree = {
      username = "Keyword",
      mention = "WarningMsg",
      date = "Comment",
      expander = "DiffviewNonText",
      directory = "Directory",
      directory_icon = "DiffviewFolderSign",
      file_name = "Normal",
      resolved = "DiagnosticSignOk",
      unresolved = "DiagnosticSignWarn",
      draft = "DiffviewNonText",
    },
  },
}

-- These are the initial states of the discussion trees
M.discussion_tree = {
  resolved_expanded = false,
  unresolved_expanded = false,
}
M.unlinked_discussion_tree = {
  resolved_expanded = false,
  unresolved_expanded = false,
}

-- These keymaps are set globally when the plugin is initialized
M.set_global_keymaps = function()
  local keymaps = M.settings.keymaps

  if keymaps.disable_all or keymaps.global.disable_all then
    return
  end

  if keymaps.global.start_review then
    vim.keymap.set("n", keymaps.global.start_review, function()
      require("gitlab").review()
    end, { desc = "Start Gitlab review", nowait = keymaps.global.start_review_nowait })
  end

  if keymaps.global.choose_merge_request then
    vim.keymap.set("n", keymaps.global.choose_merge_request, function()
      require("gitlab").choose_merge_request()
    end, { desc = "Choose MR for review", nowait = keymaps.global.choose_merge_request_nowait })
  end

  if keymaps.global.summary then
    vim.keymap.set("n", keymaps.global.summary, function()
      require("gitlab").summary()
    end, { desc = "Show MR summary", nowait = keymaps.global.summary_nowait })
  end

  if keymaps.global.approve then
    vim.keymap.set("n", keymaps.global.approve, function()
      require("gitlab").approve()
    end, { desc = "Approve MR", nowait = keymaps.global.approve_nowait })
  end

  if keymaps.global.revoke then
    vim.keymap.set("n", keymaps.global.revoke, function()
      require("gitlab").revoke()
    end, { desc = "Revoke approval", nowait = keymaps.global.revoke_nowait })
  end

  if keymaps.global.create_mr then
    vim.keymap.set("n", keymaps.global.create_mr, function()
      require("gitlab").create_mr()
    end, { desc = "Create MR", nowait = keymaps.global.create_mr_nowait })
  end

  if keymaps.global.create_note then
    vim.keymap.set("n", keymaps.global.create_note, function()
      require("gitlab").create_note()
    end, { desc = "Create MR note", nowait = keymaps.global.create_note_nowait })
  end

  if keymaps.global.toggle_discussions then
    vim.keymap.set("n", keymaps.global.toggle_discussions, function()
      require("gitlab").toggle_discussions()
    end, { desc = "Toggle MR discussions", nowait = keymaps.global.toggle_discussions_nowait })
  end

  if keymaps.global.add_assignee then
    vim.keymap.set("n", keymaps.global.add_assignee, function()
      require("gitlab").add_assignee()
    end, { desc = "Add MR assignee", nowait = keymaps.global.add_assignee_nowait })
  end

  if keymaps.global.delete_assignee then
    vim.keymap.set("n", keymaps.global.delete_assignee, function()
      require("gitlab").delete_assignee()
    end, { desc = "Delete MR assignee", nowait = keymaps.global.delete_assignee_nowait })
  end

  if keymaps.global.add_label then
    vim.keymap.set("n", keymaps.global.add_label, function()
      require("gitlab").add_label()
    end, { desc = "Add MR label", nowait = keymaps.global.add_label_nowait })
  end

  if keymaps.global.delete_label then
    vim.keymap.set("n", keymaps.global.delete_label, function()
      require("gitlab").delete_label()
    end, { desc = "Delete MR label", nowait = keymaps.global.delete_label_nowait })
  end

  if keymaps.global.add_reviewer then
    vim.keymap.set("n", keymaps.global.add_reviewer, function()
      require("gitlab").add_reviewer()
    end, { desc = "Add MR reviewer", nowait = keymaps.global.add_reviewer_nowait })
  end

  if keymaps.global.delete_reviewer then
    vim.keymap.set("n", keymaps.global.delete_reviewer, function()
      require("gitlab").delete_reviewer()
    end, { desc = "Delete MR reviewer", nowait = keymaps.global.delete_reviewer_nowait })
  end

  if keymaps.global.pipeline then
    vim.keymap.set("n", keymaps.global.pipeline, function()
      require("gitlab").pipeline()
    end, { desc = "Show MR pipeline status", nowait = keymaps.global.pipeline_nowait })
  end

  if keymaps.global.open_in_browser then
    vim.keymap.set("n", keymaps.global.open_in_browser, function()
      require("gitlab").open_in_browser()
    end, { desc = "Open MR in browser", nowait = keymaps.global.open_in_browser_nowait })
  end

  if keymaps.global.merge then
    vim.keymap.set("n", keymaps.global.merge, function()
      require("gitlab").merge()
    end, { desc = "Merge MR", nowait = keymaps.global.merge_nowait })
  end

  if keymaps.global.copy_mr_url then
    vim.keymap.set("n", keymaps.global.copy_mr_url, function()
      require("gitlab").copy_mr_url()
    end, { desc = "Copy MR url", nowait = keymaps.global.copy_mr_url_nowait })
  end

  if keymaps.global.publish_all_drafts then
    vim.keymap.set("n", keymaps.global.publish_all_drafts, function()
      require("gitlab").publish_all_drafts()
    end, { desc = "Publish all MR comment drafts", nowait = keymaps.global.publish_all_drafts_nowait })
  end

  if keymaps.global.toggle_draft_mode then
    vim.keymap.set("n", keymaps.global.toggle_draft_mode, function()
      require("gitlab").toggle_draft_mode()
    end, { desc = "Toggle MR comment draft mode", nowait = keymaps.global.toggle_draft_mode_nowait })
  end
end

-- Merges user settings into the default settings, overriding them
---@param args Settings
---@return Settings
M.merge_settings = function(args)
  M.settings = u.merge(M.settings, args)
  M.settings.file_separator = (u.is_windows() and "\\" or "/")
  return M.settings
end

M.print_settings = function()
  vim.print(M.settings)
end

-- First reads environment variables into the settings module,
-- then attemps to read a `.gitlab.nvim` configuration file.
-- If after doing this, any variables are missing, alerts the user.
-- The `.gitlab.nvim` configuration file takes precedence.
M.setPluginConfiguration = function()
  if M.initialized then
    return true
  end

  local token, url, err = M.settings.auth_provider()
  if err ~= nil then
    return
  end

  M.settings.auth_token = token
  M.settings.gitlab_url = u.trim_slash(url or "https://gitlab.com")

  if M.settings.auth_token == nil then
    vim.notify(
      "Missing authentication token for Gitlab, please provide it as an environment variable or in the .gitlab.nvim file",
      vim.log.levels.ERROR
    )
    return false
  end

  M.initialized = true
  return true
end

local function exit(popup, opts)
  if opts.action_before_exit and opts.cb ~= nil then
    opts.cb()
    popup:unmount()
  else
    popup:unmount()
    if opts.cb ~= nil then
      opts.cb()
    end
  end
end

-- These keymaps are buffer specific and are set dynamically when popups mount
M.set_popup_keymaps = function(popup, action, linewise_action, opts)
  if M.settings.keymaps.disable_all or M.settings.keymaps.popup.disable_all then
    return
  end

  if opts == nil then
    opts = {}
  end
  if action ~= "Help" and M.settings.keymaps.help then -- Don't show help on the help popup
    vim.keymap.set("n", M.settings.keymaps.help, function()
      local help = require("gitlab.actions.help")
      help.open()
    end, { buffer = popup.bufnr, desc = "Open help", nowait = M.settings.keymaps.help_nowait })
  end
  if action ~= nil and M.settings.keymaps.popup.perform_action then
    vim.keymap.set("n", M.settings.keymaps.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      if opts.action_before_close then
        action(text, popup.bufnr)
        exit(popup, opts)
      else
        exit(popup, opts)
        action(text, popup.bufnr)
      end
    end, { buffer = popup.bufnr, desc = "Perform action", nowait = M.settings.keymaps.popup.perform_action_nowait })
  end

  if linewise_action ~= nil and M.settings.keymaps.popup.perform_action then
    vim.keymap.set("n", M.settings.keymaps.popup.perform_linewise_action, function()
      local bufnr = vim.api.nvim_get_current_buf()
      local linnr = vim.api.nvim_win_get_cursor(0)[1]
      local text = u.get_line_content(bufnr, linnr)
      linewise_action(text)
    end, {
      buffer = popup.bufnr,
      desc = "Perform linewise action",
      nowait = M.settings.keymaps.popup.perform_linewise_action_nowait,
    })
  end

  if M.settings.keymaps.popup.discard_changes then
    vim.keymap.set("n", M.settings.keymaps.popup.discard_changes, function()
      local temp_registers = M.settings.popup.temp_registers
      M.settings.popup.temp_registers = {}
      vim.cmd("quit!")
      M.settings.popup.temp_registers = temp_registers
    end, {
      buffer = popup.bufnr,
      desc = "Quit discarding changes",
      nowait = M.settings.keymaps.popup.discard_changes_nowait,
    })
  end

  if opts.save_to_temp_register then
    vim.api.nvim_create_autocmd("BufWinLeave", {
      buffer = popup.bufnr,
      callback = function()
        local text = u.get_buffer_text(popup.bufnr)
        for _, register in ipairs(M.settings.popup.temp_registers) do
          vim.fn.setreg(register, text)
        end
      end,
    })
  end

  if opts.action_before_exit then
    vim.api.nvim_create_autocmd("BufWinLeave", {
      buffer = popup.bufnr,
      callback = function()
        exit(popup, opts)
      end,
    })
  end
end

-- Dependencies
-- These tables are passed to the async.sequence function, which calls them in sequence
-- before calling an action. They are used to set global state that's required
-- for each of the actions to occur. This is necessary because some Gitlab behaviors (like
-- adding a reviewer) requires some initial state.
M.dependencies = {
  user = {
    endpoint = "/users/me",
    key = "user",
    state = "USER",
    refresh = false,
  },
  info = {
    endpoint = "/mr/info",
    key = "info",
    state = "INFO",
    refresh = false,
  },
  latest_pipeline = {
    endpoint = "/pipeline",
    key = "latest_pipeline",
    state = "PIPELINE",
    refresh = true,
  },
  labels = {
    endpoint = "/mr/label",
    key = "labels",
    state = "LABELS",
    refresh = false,
  },
  revisions = {
    endpoint = "/mr/revisions",
    key = "Revisions",
    state = "MR_REVISIONS",
    refresh = false,
  },
  draft_notes = {
    endpoint = "/mr/draft_notes/",
    key = "draft_notes",
    state = "DRAFT_NOTES",
    refresh = false,
  },
  project_members = {
    endpoint = "/project/members",
    key = "ProjectMembers",
    state = "PROJECT_MEMBERS",
    refresh = false,
  },
  merge_requests = {
    endpoint = "/merge_requests",
    key = "merge_requests",
    state = "MERGE_REQUESTS",
    refresh = true,
    method = "POST",
    body = function(opts)
      local listArgs = {
        label = opts and opts.label or {},
        notlabel = opts and opts.notlabel or {},
      }
      for k, v in pairs(listArgs) do
        listArgs[k] = v
      end
      return listArgs
    end,
  },
  discussion_data = {
    -- key is missing here...
    endpoint = "/mr/discussions/list",
    state = "DISCUSSION_DATA",
    refresh = false,
    method = "POST",
    body = function()
      return {
        blacklist = M.settings.discussion_tree.blacklist,
      }
    end,
  },
}

M.load_new_state = function(dep, cb)
  local job = require("gitlab.job")
  local dependency = M.dependencies[dep]
  job.run_job(
    dependency.endpoint,
    dependency.method or "GET",
    dependency.body and dependency.body() or nil,
    function(data)
      if dependency.key then
        M[dependency.state] = u.ensure_table(data[dependency.key])
      end
      if type(cb) == "function" then
        cb(data) -- To set data manually...
      end
    end
  )
end

-- This function clears out all of the previously fetched data. It's used
-- to reset the plugin state when the Go server is restarted
M.clear_data = function()
  M.INFO = nil
  for _, dep in ipairs(M.dependencies) do
    M[dep.state] = nil
  end
end

return M
