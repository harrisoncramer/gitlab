---@meta diagnostics

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
---@field inline_draft_notes number
---@field unlinked_draft_notes number
---@field resolvable_notes number
---@field resolved_notes number
---@field help_keymap string
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

---@class RootNode: NuiTree.Node
---@field range table
---@field old_line integer|nil
---@field new_line integer|nil
---@field id string
---@field text string
---@field type "note"
---@field is_root boolean
---@field root_note_id string
---@field file_name string
---@field resolvable boolean
---@field resolved boolean
---@field url string
