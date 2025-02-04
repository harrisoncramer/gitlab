local u = require("gitlab.utils")
local state = require("gitlab.state")
local List = require("gitlab.utils.list")

local M = {}

---@class NoteWithValues
---@field position NotePosition
---@field resolvable boolean|nil
---@field resolved boolean|nil
---@field created_at string|nil

---Return true if discussion has a placeable diagnostic, false otherwise.
---@param note NoteWithValues
---@param file string
---@return boolean
local filter_discussions_and_notes = function(note)
  ---Do not include unlinked notes
  return note.position ~= nil
    ---Skip resolved discussions if user wants to
    and not (state.settings.discussion_signs.skip_resolved_discussion and note.resolvable and note.resolved)
    ---Skip discussions from old revisions
    and not (
      state.settings.discussion_signs.skip_old_revision_discussion
      and note.created_at ~= nil
      and u.from_iso_format_date_to_timestamp(note.created_at)
        <= u.from_iso_format_date_to_timestamp(state.MR_REVISIONS[1].created_at)
    )
end

---Filter all discussions and drafts which have placeable signs and diagnostics.
---@return Discussion|DraftNote[]
M.filter_placeable_discussions = function()
  local discussions = u.ensure_table(state.DISCUSSION_DATA and state.DISCUSSION_DATA.discussions or {})
  if type(discussions) ~= "table" then
    discussions = {}
  end

  local draft_notes = u.ensure_table(state.DRAFT_NOTES)
  if type(draft_notes) ~= "table" then
    draft_notes = {}
  end

  local filtered_discussions = List.new(discussions):filter(function(discussion)
    local first_note = discussion.notes[1]
    return type(first_note.position) == "table" and filter_discussions_and_notes(first_note)
  end)

  local filtered_draft_notes = List.new(draft_notes):filter(function(note)
    return filter_discussions_and_notes(note)
  end)

  return u.join(filtered_discussions, filtered_draft_notes)
end

M.parse_line_code = function(line_code)
  local line_code_regex = "%w+_(%d+)_(%d+)"
  local old_line, new_line = line_code:match(line_code_regex)
  return tonumber(old_line), tonumber(new_line)
end

---@param d_or_n Discussion|DraftNote
---@return boolean
M.is_old_sha = function(d_or_n)
  local position = M.get_first_note(d_or_n).position
  local old_start_line = position.line_range ~= nil and M.parse_line_code(position.line_range.start.line_code) or nil
  return position.old_line ~= nil and old_start_line ~= 0
end

---@param discussion Discussion|DraftNote
---@return boolean
M.is_new_sha = function(discussion)
  return not M.is_old_sha(discussion)
end

---@param d_or_n Discussion|DraftNote
---@return boolean
M.is_single_line = function(d_or_n)
  local first_note = M.get_first_note(d_or_n)
  local line_range = first_note.position and first_note.position.line_range
  return line_range == nil
end

---@param discussion Discussion
---@return boolean
M.is_multi_line = function(discussion)
  return not M.is_single_line(discussion)
end

---@param d_or_n Discussion|DraftNote
---@return Note|DraftNote
M.get_first_note = function(d_or_n)
  return d_or_n.notes and d_or_n.notes[1] or d_or_n
end

return M
