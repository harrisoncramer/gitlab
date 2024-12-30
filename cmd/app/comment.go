package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type CommentResponse struct {
	SuccessResponse
	Comment    *gitlab.Note       `json:"note"`
	Discussion *gitlab.Discussion `json:"discussion"`
}

type CommentManager interface {
	CreateMergeRequestDiscussion(pid interface{}, mergeRequest int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error)
	UpdateMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error)
	DeleteMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
}

type commentService struct {
	data
	client CommentManager
}

/* commentHandler creates, edits, and deletes discussions (comments, multi-line comments) */
func (a commentService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodPost:
		a.postComment(w, r)
	case http.MethodPatch:
		a.editComment(w, r)
	case http.MethodDelete:
		a.deleteComment(w, r)
	}
}

type DeleteCommentRequest struct {
	NoteId       int    `json:"note_id" validate:"required"`
	DiscussionId string `json:"discussion_id" validate:"required"`
}

/* deleteComment deletes a note, multiline comment, or comment, which are all considered discussion notes. */
func (a commentService) deleteComment(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*DeleteCommentRequest)

	res, err := a.client.DeleteMergeRequestDiscussionNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, payload.DiscussionId, payload.NoteId)

	if err != nil {
		handleError(w, err, "Could not delete comment", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not delete comment", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: "Comment deleted successfully"}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

type PostCommentRequest struct {
	Comment string `json:"comment" validate:"required"`
	PositionData
}

/* CommentWithPosition is a comment with an (optional) position data value embedded in it. The position data will be non-nil for range-based comments. */
type CommentWithPosition struct {
	PositionData PositionData
}

func (comment CommentWithPosition) GetPositionData() PositionData {
	return comment.PositionData
}

/* postComment creates a note, multiline comment, or comment. */
func (a commentService) postComment(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*PostCommentRequest)

	opt := gitlab.CreateMergeRequestDiscussionOptions{
		Body: &payload.Comment,
	}

	/* If we are leaving a comment on a line, leave position. Otherwise,
	we are leaving a note (unlinked comment) */

	if payload.FileName != "" {
		commentWithPositionData := CommentWithPosition{payload.PositionData}
		opt.Position = buildCommentPosition(commentWithPositionData)
	}

	discussion, res, err := a.client.CreateMergeRequestDiscussion(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opt)

	if err != nil {
		handleError(w, err, "Could not create discussion", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not create discussion", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := CommentResponse{
		SuccessResponse: SuccessResponse{Message: "Comment created successfully"},
		Comment:         discussion.Notes[0],
		Discussion:      discussion,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

type EditCommentRequest struct {
	Comment      string `json:"comment" validate:"required"`
	NoteId       int    `json:"note_id" validate:"required"`
	DiscussionId string `json:"discussion_id" validate:"required"`
	Resolved     bool   `json:"resolved"`
}

/* editComment changes the text of a comment or changes it's resolved status. */
func (a commentService) editComment(w http.ResponseWriter, r *http.Request) {

	payload := r.Context().Value(payload("payload")).(*EditCommentRequest)

	options := gitlab.UpdateMergeRequestDiscussionNoteOptions{
		Body: gitlab.Ptr(payload.Comment),
	}

	note, res, err := a.client.UpdateMergeRequestDiscussionNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, payload.DiscussionId, payload.NoteId, &options)

	if err != nil {
		handleError(w, err, "Could not update comment", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not update comment", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := CommentResponse{
		SuccessResponse: SuccessResponse{Message: "Comment updated successfully"},
		Comment:         note,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
