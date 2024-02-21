local state = require("gitlab.state")
local u = require("gitlab.utils")
local M = {}

---@class Hunk
---@field old_line integer
---@field old_range integer
---@field new_line integer
---@field new_range integer

---@class HunksAndDiff
---@field hunks Hunk[] list of hunks
---@field all_diff_output table The data from the git diff command

---Turn hunk line into Lua table
---@param line table
---@return Hunk|nil
local parse_possible_hunk_headers = function(line)
  if line:sub(1, 2) == "@@" then
    -- match:
    --  @@ -23 +23 @@ ...
    --  @@ -23,0 +23 @@ ...
    --  @@ -41,0 +42,4 @@ ...
    local old_start, old_range, new_start, new_range = line:match("@@+ %-(%d+),?(%d*) %+(%d+),?(%d*) @@+")

    return {
      old_line = tonumber(old_start),
      old_range = tonumber(old_range) or 0,
      new_line = tonumber(new_start),
      new_range = tonumber(new_range) or 0,
    }
  end
end
---@param linnr number
---@param hunk Hunk
---@param all_diff_output table
local line_was_removed = function(linnr, hunk, all_diff_output)
  for matching_line_index, line in ipairs(all_diff_output) do
    local found_hunk = parse_possible_hunk_headers(line)
    if found_hunk ~= nil and vim.deep_equal(found_hunk, hunk) then
      -- We found a matching hunk, now we need to iterate over the lines from the raw diff output
      -- at that hunk until we reach the line we are looking for. When the indexes match we check
      -- to see if that line is deleted or not.
      for hunk_line_index = found_hunk.old_line, hunk.old_line + hunk.old_range - 1, 1 do
        local line_content = all_diff_output[matching_line_index + 1]
        if hunk_line_index == linnr then
          if string.match(line_content, "^%-") then
            return "deleted"
          end
        end
      end
    end
  end
end

---@param linnr number
---@param hunk Hunk
---@param all_diff_output table
local line_was_added = function(linnr, hunk, all_diff_output)
  for matching_line_index, line in ipairs(all_diff_output) do
    local found_hunk = parse_possible_hunk_headers(line)
    if found_hunk ~= nil and vim.deep_equal(found_hunk, hunk) then
      -- For added lines, we only want to iterate over the part of the diff that has has new lines,
      -- so we skip over the old range. We then keep track of the increment to the original new line index,
      -- and iterate until we reach the end of the total range of this hunk. If we arrive at the matching
      -- index for the line number, we check to see if the line was added.
      local i = 0
      local old_range = (found_hunk.old_range == 0 and found_hunk.old_line ~= 0) and 1 or found_hunk.old_range
      for hunk_line_index = matching_line_index + old_range + 1, matching_line_index + old_range + found_hunk.new_range, 1 do
        local line_content = all_diff_output[hunk_line_index]
        if (found_hunk.new_line + i) == linnr then
          if string.match(line_content, "^%+") then
            return "added"
          end
        end
        i = i + 1
      end
    end
  end
end

---Returns whether the comment is on a deleted line, added line, or unmodified line.
---This is in order to build the payload for Gitlab correctly by setting the old line and new line.
---@param old_line number
---@param new_line number
---@param current_file string
---@return string|nil
function M.get_modification_type(old_line, new_line, current_file)
  local hunk_and_diff_data = M.parse_hunks_and_diff(current_file, state.INFO.target_branch)
  if hunk_and_diff_data.hunks == nil then
    u.notify("Could not parse hunks", vim.log.levels.ERROR)
    return
  end

  local hunks = hunk_and_diff_data.hunks
  local all_diff_output = hunk_and_diff_data.all_diff_output

  local is_current_sha = require("gitlab.reviewer").is_current_sha()

  for _, hunk in ipairs(hunks) do
    local old_line_end = hunk.old_line + hunk.old_range
    local new_line_end = hunk.new_line + hunk.new_range

    if is_current_sha then
      -- If it is a single line change and neither hunk has a range, then it's added
      if new_line >= hunk.new_line and new_line <= new_line_end then
        if hunk.new_range == 0 and hunk.old_range == 0 then
          return "added"
        end
        -- If leaving a comment on the new window, we may be commenting on an added line
        -- or on an unmodified line. To tell, we have to check whether the line itself is
        -- prefixed with "+" and only return "added" if it is.
        if line_was_added(new_line, hunk, all_diff_output) then
          return "added"
        end
      end
    else
      -- It's a deletion if it's in the range of the hunks and the new
      -- range is zero, since that is only a deletion hunk, or if we find
      -- a match in another hunk with a range, and the corresponding line is prefixed
      -- with a "-" only. If it is, then it's a deletion.
      if old_line >= hunk.old_line and old_line <= old_line_end and hunk.old_range == 0 then
        return "deleted"
      end
      if
          (old_line >= hunk.old_line and old_line <= old_line_end)
          or (old_line >= hunk.new_line and new_line <= new_line_end)
      then
        if line_was_removed(old_line, hunk, all_diff_output) then
          return "deleted"
        end
      end
    end
  end

  -- If we can't find the line, this means the user is either trying to leave
  -- a comment on an unchanged line in the new or old file SHA. This is only
  -- allowed in the old file
  local result = is_current_sha and "bad_file_unmodified" or "unmodified"
  if result == "bad_file_unmodified" then
    u.notify("Comments on unmodified lines will be placed in the old file", vim.log.levels.WARN)
  end
  return result
end

---Parse git diff hunks.
---@param file_path string Path to file.
---@param base_branch string Git base branch of merge request.
---@return HunksAndDiff
M.parse_hunks_and_diff = function(file_path, base_branch)
  local hunks = {}
  local all_diff_output = {}

  local Job = require("plenary.job")

  local diff_job = Job:new({
    command = "git",
    args = { "diff", "--minimal", "--unified=0", "--no-color", base_branch, "--", file_path },
    on_exit = function(j, return_code)
      if return_code == 0 then
        all_diff_output = j:result()
        for _, line in ipairs(all_diff_output) do
          local hunk = parse_possible_hunk_headers(line)
          if hunk ~= nil then
            table.insert(hunks, hunk)
          end
        end
      else
        M.notify("Failed to get git diff: " .. j:stderr(), vim.log.levels.WARN)
      end
    end,
  })

  diff_job:sync()

  return { hunks = hunks, all_diff_output = all_diff_output }
end

---@class LineDiffInfo
---@field old_line integer
---@field new_line integer
---@field in_hunk boolean

---Search git diff hunks to find old and new line number corresponding to target line.
---This function does not check if target line is outside of boundaries of file.
---@param hunks Hunk[] git diff parsed hunks.
---@param target_line integer line number to search for - based on is_new paramter the search is
---either in new lines or old lines of hunks.
---@param is_new boolean whether to search for new line or old line
---@return LineDiffInfo
M.get_lines_from_hunks = function(hunks, target_line, is_new)
  if #hunks == 0 then
    -- If there are zero hunks, return target_line for both old and new lines
    return { old_line = target_line, new_line = target_line, in_hunk = false }
  end
  local current_new_line = 0
  local current_old_line = 0
  if is_new then
    for _, hunk in ipairs(hunks) do
      -- target line is before current hunk
      if target_line < hunk.new_line then
        return {
          old_line = current_old_line + (target_line - current_new_line),
          new_line = target_line,
          in_hunk = false,
        }
        -- target line is within the current hunk
      elseif hunk.new_line <= target_line and target_line <= (hunk.new_line + hunk.new_range) then
        -- this is interesting magic of gitlab calculation
        return {
          old_line = hunk.old_line + hunk.old_range + 1,
          new_line = target_line,
          in_hunk = true,
        }
        -- target line is after the current hunk
      else
        current_new_line = hunk.new_line + hunk.new_range
        current_old_line = hunk.old_line + hunk.old_range
      end
    end
    -- target line is after last hunk
    return {
      old_line = current_old_line + (target_line - current_new_line),
      new_line = target_line,
      in_hunk = false,
    }
  else
    for _, hunk in ipairs(hunks) do
      -- target line is before current hunk
      if target_line < hunk.old_line then
        return {
          old_line = target_line,
          new_line = current_new_line + (target_line - current_old_line),
          in_hunk = false,
        }
        -- target line is within the current hunk
      elseif hunk.old_line <= target_line and target_line <= (hunk.old_line + hunk.old_range) then
        return {
          old_line = target_line,
          new_line = hunk.new_line,
          in_hunk = true,
        }
        -- target line is after the current hunk
      else
        current_new_line = hunk.new_line + hunk.new_range
        current_old_line = hunk.old_line + hunk.old_range
      end
    end
    -- target line is after last hunk
    return {
      old_line = current_old_line + (target_line - current_new_line),
      new_line = target_line,
      in_hunk = false,
    }
  end
end

return M