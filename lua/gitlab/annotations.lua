---@meta diagnostics

---@alias BorderEnum "rounded" | "single" | "double" | "solid"
---@alias SeverityEnum "ERROR" | "WARN" | "INFO" | "HINT"

---@class Author
---@field id integer
---@field username string
---@field email string
---@field name string
---@field state string
---@field avatar_url string
---@field web_url string

---@class LinePosition
---@field line_code string
---@field type string

---@class GitlabLineRange
---@field start LinePosition
---@field end LinePosition

---@class NotePosition
---@field base_sha string
---@field start_sha string
---@field head_sha string
---@field position_type string
---@field new_path string?
---@field new_line integer?
---@field old_path string?
---@field old_line integer?
---@field line_range GitlabLineRange?

---@class Note
---@field id integer
---@field type string
---@field body string
---@field attachment string
---@field title string
---@field file_name string
---@field author Author
---@field system boolean
---@field expires_at string?
---@field updated_at string?
---@field created_at string?
---@field noteable_id integer
---@field noteable_type string
---@field commit_id string
---@field position NotePosition
---@field resolvable boolean
---@field resolved boolean
---@field resolved_by Author
---@field resolved_at string?
---@field noteable_iid integer
---@field url string?

---@class UnlinkedNote: Note
---@field position nil

---@class Discussion
---@field id string
---@field individual_note boolean
---@field notes Note[]

---@class UnlinkedDiscussion: Discussion
---@field notes UnlinkedNote[]

---@class DiscussionData
---@field discussions Discussion[]
---@field unlinked_discussions UnlinkedDiscussion[]

---@class EmojiMap: table<string, Emoji>
---@class Emoji
---@field	unicode           string
---@field	unicodeAlternates string[]
---@field	name              string
---@field	shortname         string
---@field	category          string
---@field	aliases           string[]
---@field	aliasesASCII      string[]
---@field	keywords          string[]
---@field	moji              string

---@class WinbarTable
---@field view_type string
---@field resolvable_discussions number
---@field resolved_discussions number
---@field non_resolvable_discussions number
---@field inline_draft_notes number
---@field unlinked_draft_notes number
---@field resolvable_notes number
---@field resolved_notes number
---@field non_resolvable_notes number
---@field help_keymap string
---@field updated string
---
---@class SignTable
---@field name string
---@field group string
---@field priority number
---@field id number
---@field lnum number
---@field buffer number?
---
---@class DiagnosticTable
---@field message string
---@field col number
---@field severity number
---@field user_data table
---@field source string
---@field code string?

---@class LineRange
---@field start_line integer
---@field end_line integer

---@class DiffviewInfo
---@field modification_type string
---@field file_name string
---Relevant for renamed files only, the name of the file in the previous commit
---@field old_file_name string
---@field current_bufnr integer
---@field new_sha_win_id integer
---@field old_sha_win_id integer
---@field opposite_bufnr integer
---@field new_line_from_buf integer
---@field old_line_from_buf integer

---@class LocationData
---@field old_line integer | nil
---@field new_line integer | nil
---@field line_range ReviewerRangeInfo|nil

---@class DraftNote
---@field note string
---@field id integer
---@field author_id integer
---@field merge_request_id integer
---@field resolve_discussion boolean
---@field discussion_id string -- This will always be ""
---@field commit_id string  -- This will always be ""
---@field line_code string
---@field position NotePosition
---
---
--- Plugin Settings
---
---@class Settings
---@field port? number -- The port of the Go server, which runs in the background, if omitted or `nil` the port will be chosen automatically
---@field remote_branch "origin" | string -- The remote, "origin" by default
---@field log_path? string -- Log path for the Go server
---@field string? any -- Custom path for `.gitlab.nvim` file, please read the "Connecting to Gitlab" section
---@field debug? DebugSettings -- Which values to log
---@field attachment_dir? string, -- The local directory for files (see the "summary" section)
---@field reviewer_settings? ReviewerSettings -- Settings for the reviewer view
---@field connection_settings? ConnectionSettings -- Settings for the connection to Gitlab
---@field keymaps? Keymaps -- Keymaps for the plugin
---@field popup? PopupSettings -- Settings for the popup windows
---@field discussion_tree? DiscussionSettings -- Settings for the popup windows
---@field choose_merge_request? ChooseMergeRequestSettings -- Default settings when choosing a merge request
---@field info? InfoSettings -- Settings for the "info" or "summary" view
---@field discussion_signs? DiscussionSigns -- The settings for discussion signs/diagnostics
---@field pipeline? PipelineSettings -- The settings for the pipeline popup
---@field create_mr? CreateMrSettings -- The settings when creating an MR
---@field colors? ColorSettings --- Colors settings for the plugin

---@class DiscussionSigns: table
---@field enabled? boolean -- Show diagnostics for gitlab comments in the reviewer
---@field skip_resolved_discussion? boolean -- Show diagnostics for resolved discussions
---@field severity? SeverityEnum
---@field virtual_text? boolean -- Whether to show the comment text inline as floating virtual text
---@field use_diagnostic_signs? boolean -- Show diagnostic sign (depending on the `severity` setting) along with the comment icon
---@field priority? number -- Higher will override LSP warnings, etc
---@field icons? IconsOpts -- Customize the icons shown with comments or notes

---@class ColorSettings: table
---@field discussion_tree? DiscussionTreeColors -- Colors for elements in the discussion tree

---@class DiscussionTreeColors
--- @field username? string
--- @field mention? string
--- @field date? string
--- @field expander? string
--- @field directory? string
--- @field directory_icon? string
--- @field file_name? string
--- @field resolved? string
--- @field unresolved? string
--- @field draft? string

---@class CreateMrSettings: table
---@field target? string -- Default branch to target when creating an MR
---@field template_file? string -- Default MR template in .gitlab/merge_request_templates
---@field delete_branch? boolean -- Whether the source branch will be marked for deletion
---@field squash? boolean -- Whether the commits will be marked for squashing
---@field title_input? TitleInputSettings
---@field fork? ForkSettings

---@class ForkSettings: table
---@field enabled? boolean -- If making an MR from a fork
---@field forked_project_id? number -- The Gitlab ID of the project you are merging into. If nil, will be prompted.

---@class TitleInputSettings: table
---@field width? number
---@field border? BorderEnum

---@class PipelineSettings: table
---@field created? string -- What to show for this pipeline status, by default "",
---@field pending? string -- What to show for this pipeline status, by default "",
---@field preparing? string -- What to show for this pipeline status, by default "",
---@field scheduled? string -- What to show for this pipeline status, by default "",
---@field running? string -- What to show for this pipeline status, by default "",
---@field canceled? string -- What to show for this pipeline status, by default "↪",
---@field skipped? string -- What to show for this pipeline status, by default "↪",
---@field success? string -- What to show for this pipeline status, by default "✓",
---@field failed? string -- What to show for this pipeline status, by default "",

---@class IconsOpts: table
---@field comment? string -- The icon for comments, by default "→|",
---@field range? string -- The icon for lines in ranged comments, by default " |"

---@class ReviewerSettings: table
---@field diffview? SettingsDiffview -- Settings for diffview (the dependency)

---@class SettingsDiffview: table
---@field imply_local? boolean -- If true, will attempt to use --imply_local option when calling |:DiffviewOpen|

---@class ConnectionSettings: table
---@field insecure? boolean -- Like curl's --insecure option, ignore bad x509 certificates on connection

---@class DebugSettings: table
---@field go_request? boolean -- Log the requests to Gitlab sent by the Go server
---@field go_response? boolean -- Log the responses received from Gitlab to the Go server
---@field request? boolean -- Log the requests to the Go server
---@field response? boolean -- Log the responses from the Go server

---@class PopupSettings: table
---@field width? string -- The width of the popup, by default "40%"
---@field height? string The width of the popup, by default "60%"
---@field border? BorderEnum
---@field opacity? number -- From 0.0 (fully transparent) to 1.0 (fully opaque)
---@field comment? table -- Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 },
---@field edit? table -- Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field note? table -- Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field pipeline? table -- Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field reply? table -- Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field squash_message? string The default message when squashing a commit
---@field temp_registers? string[]  -- List of registers for backing up popup content (see `:h gitlab.nvim.temp-registers`)

---@class ChooseMergeRequestSettings
---@field open_reviewer? boolean -- Open the reviewer window automatically after switching merge requests

---@class InfoSettings
---@field horizontal? boolean -- Display metadata to the left of the summary rather than underneath
---@field fields? ("author" | "created_at" | "updated_at" | "merge_status" | "draft" | "conflicts" | "assignees" | "reviewers" | "pipeline" | "branch" | "target_branch" | "delete_branch" | "squash" | "labels")[]

---@class DiscussionSettings: table
---@field expanders? ExpanderOpts -- Customize the expander icons in the discussion tree
---@field auto_open? boolean -- Automatically open when the reviewer is opened
---@field default_view? string - Show "discussions" or "notes" by default
---@field blacklist? table<string> -- List of usernames to remove from tree (bots, CI, etc)
---@field keep_current_open? boolean -- If true, current discussion stays open even if it should otherwise be closed when toggling
---@field position? "top" | "right" | "bottom" | "left"
---@field size? string -- Size of split, default to "20%"
---@field relative? "editor" | "window" -- Relative position of tree split
---@field resolved? string -- Symbol to show next to resolved discussions
---@field unresolved? '-', -- Symbol to show next to unresolved discussions
---@field tree_type? string -- Type of discussion tree - "simple" means just list of discussions, "by_file_name" means file tree with discussions under file
---@field draft_mode? boolean -- Whether comments are posted as drafts as part of a review
---@field winbar? function -- Custom function to return winbar title, should return a string. Provided with WinbarTable (defined in annotations.lua)

---@class ExpanderOpts: table<string string>
---@field expanded? string -- Icon for expanded discussion thread
---@field collapsed? string -- Icon for collapsed discussion thread
---@field indentation? string -- Indentation Icon

---@class Keymaps
---@field help? string -- Open a help popup for local keymaps when a relevant view is focused (popup, discussion panel, etc)
---@field global? KeymapsGlobal -- Global keybindings which will apply everywhere in Neovim
---@field popup? KeymapsPopup -- Keymaps for the popups (creating a comment, reading the summary, etc)
---@field discussion_tree? KeymapsDiscussionTree -- Keymaps for the discussion tree pane
---@field reviewer? KeymapsReviewer -- Keymaps for the reviewer view

---@class KeymapTable: table<string, table<string, string | boolean>>
---@field disable_all? boolean -- Disable all built-in keymaps

---@class KeymapsPopup: KeymapTable
---@field next_field? string -- Cycle to the next field. Accepts |count|.
---@field prev_field? string -- Cycle to the previous field. Accepts |count|.
---@field perform_action? string -- Once in normal mode, does action (like saving comment or applying description edit, etc)
---@field perform_linewise_action? string -- Once in normal mode, does the linewise action (see logs for this job, etc)
---@field discard_changes? string -- Quit the popup discarding changes, the popup content isnot? saved to the `temp_registers` (see `:h gitlab.nvim.temp-registers`)
---
---@class KeymapsDiscussionTree: KeymapTable
---@field add_emoji? string -- Add an emoji to the note/comment
---@field delete_emoji? string -- Remove an emoji from a note/comment
---@field delete_comment? string -- Delete comment
---@field edit_comment? string -- Edit comment
---@field reply? string -- Reply to comment
---@field toggle_resolved? string -- Toggle the resolved? status of the whole discussion
---@field jump_to_file? string -- Jump to comment location in file
---@field jump_to_reviewer? string -- Jump to the comment location in the reviewer window
---@field open_in_browser? string -- Jump to the URL of the current note/discussion
---@field copy_node_url? string -- Copy the URL of the current node to clipboard
---@field switch_view? string -- Toggle between the notes and discussions views
---@field toggle_tree_type? string or "by_file_name"
---@field publish_draft? string -- Publish the currently focused note/comment
---@field toggle_draft_mode? string -- Toggle between draft mode (comments posted as drafts) and live mode (comments are posted immediately)
---@field toggle_node? string -- Open or close the discussion
---@field toggle_all_discussions? string -- Open or close? separately both resolved and unresolved discussions
---@field toggle_resolved_discussions? string -- Open or close all resolved discussions
---@field toggle_unresolved_discussions? string -- Open or close all unresolved discussions
---@field refresh_data? string -- Refresh the data in the view by hitting Gitlab's APIs again
---@field print_node? string -- Print the current node (for debugging)
---
---@class KeymapsReviewer: KeymapTable
---@field create_comment? string -- Create a comment for the lines that the following {motion} moves over. Repeat the key(s) for creating comment for the current line
---@field create_suggestion? string -- Creates suggestion for the lines that the following {motion} moves over. Repeat the key(s) for creating comment for the current line
---@field move_to_discussion_tree? string -- Jump to the comment in the discussion tree
---
---@class KeymapsGlobal: KeymapTable
---@field add_assignee? string -- Add an assignee to the merge request
---@field delete_assignee? string -- Delete an assignee from the merge request
---@field add_label? string -- Add a label from the merge request
---@field delete_label? string -- Remove a label from the merge request
---@field add_reviewer? string -- Add a reviewer to the merge request
---@field delete_reviewer? string -- Delete a reviewer from the merge request
---@field approve? string -- Approve MR
---@field revoke? string -- Revoke MR approval
---@field merge? string -- Merge the feature branch to the target branch and close MR
---@field create_mr? string -- Create a new MR for currently checked-out feature branch
---@field choose_merge_request? string -- Chose MR for review (if necessary check out the feature branch)
---@field start_review? string -- Start review for the currently checked-out branch
---@field summary? string -- Show the editable summary of the MR
---@field copy_mr_url? string -- Copy the URL of the MR to the system clipboard
---@field open_in_browser? string -- Openthe URL of the MR in the default Internet browser
---@field create_note? string -- Create a note (comment not linked toa specific line)
---@field pipeline? string -- Show the pipeline status
---@field toggle_discussions? string -- Toggle the discussions window
---@field toggle_draft_mode? string -- Toggle between draft mode (comments posted as drafts) and live mode (comments are posted immediately)
---@field publish_all_drafts? string -- Publish all draft comments/notes

---@class Settings: KeymapTable
---@field next_field? string -- Cycle to the next field. Accepts |count|.
---@field prev_field? string -- Cycle to the previous field. Accepts |count|.
---@field perform_action? string -- Once in normal mode, does action (like saving comment or applying description edit, etc)
---@field perform_linewise_action? string -- Once in normal mode, does the linewise action (see logs for this job, etc)
---@field discard_changes? string -- Quit the popup discarding changes, the popup content is not? saved to the `temp_registers` (see `:h gitlab.nvim.temp-registers`)

---@class List The base class for all list objects
---@field new function -- Creates a new List from a table
---@field map function -- Mutates a given list
---@field filter function -- Filters a given list
---@field partition function -- Partitions a given list into two lists
---@field reduce function -- Applies a function to reduce the list to a single value
---@field sort function -- Sorts the list in place based on a comparator function
---@field find function -- Returns the first element that satisfies the callback
---@field slice function -- Returns a portion of the list between start and end indices
---@field includes function -- Returns true if any of the elements can satisfy the callback
---@field values function -- Returns an iterator over the list's values
