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
