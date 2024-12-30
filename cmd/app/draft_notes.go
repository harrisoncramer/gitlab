package app

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

/* The data coming from the client when creating a draft note is the same
as when they are creating a normal comment, but the Gitlab
endpoints + resources we handle are different */

type DraftNoteResponse struct {
	SuccessResponse
	DraftNote *gitlab.DraftNote `json:"draft_note"`
}

/* DraftNoteWithPosition is a draft comment with an (optional) position data value embedded in it. The position data will be non-nil for range-based draft comments. */
type DraftNoteWithPosition struct {
	PositionData PositionData
}

func (draftNote DraftNoteWithPosition) GetPositionData() PositionData {
	return draftNote.PositionData
}

type DraftNoteManager interface {
	ListDraftNotes(pid interface{}, mergeRequest int, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error)
	CreateDraftNote(pid interface{}, mergeRequest int, opt *gitlab.CreateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error)
	DeleteDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	UpdateDraftNote(pid interface{}, mergeRequest int, note int, opt *gitlab.UpdateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error)
}

type draftNoteService struct {
	data
	client DraftNoteManager
}

/* draftNoteHandler creates, edits, and deletes draft notes */
func (a draftNoteService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodGet:
		a.listDraftNotes(w, r)
	case http.MethodPost:
		a.postDraftNote(w, r)
	case http.MethodPatch:
		a.updateDraftNote(w, r)
	case http.MethodDelete:
		a.deleteDraftNote(w, r)
	}
}

type ListDraftNotesResponse struct {
	SuccessResponse
	DraftNotes []*gitlab.DraftNote `json:"draft_notes"`
}

/* listDraftNotes lists all draft notes for the currently authenticated user */
func (a draftNoteService) listDraftNotes(w http.ResponseWriter, r *http.Request) {

	opt := gitlab.ListDraftNotesOptions{}
	draftNotes, res, err := a.client.ListDraftNotes(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opt)

	if err != nil {
		handleError(w, err, "Could not get draft notes", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not get draft notes", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ListDraftNotesResponse{
		SuccessResponse: SuccessResponse{Message: "Draft notes fetched successfully"},
		DraftNotes:      draftNotes,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

type PostDraftNoteRequest struct {
	Comment      string `json:"comment" validate:"required"`
	DiscussionId string `json:"discussion_id,omitempty"`
	PositionData        // TODO: How to add validations to data from external package???
}

/* postDraftNote creates a draft note */
func (a draftNoteService) postDraftNote(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*PostDraftNoteRequest)

	opt := gitlab.CreateDraftNoteOptions{
		Note: &payload.Comment,
	}

	// Draft notes can be posted in "response" to existing discussions
	if payload.DiscussionId != "" {
		opt.InReplyToDiscussionID = gitlab.Ptr(payload.DiscussionId)
	}

	if payload.FileName != "" {
		draftNoteWithPosition := DraftNoteWithPosition{payload.PositionData}
		opt.Position = buildCommentPosition(draftNoteWithPosition)
	}

	draftNote, res, err := a.client.CreateDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opt)

	if err != nil {
		handleError(w, err, "Could not create draft note", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not create draft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := DraftNoteResponse{
		SuccessResponse: SuccessResponse{Message: "Draft note created successfully"},
		DraftNote:       draftNote,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/* deleteDraftNote deletes a draft note */
func (a draftNoteService) deleteDraftNote(w http.ResponseWriter, r *http.Request) {
	suffix := strings.TrimPrefix(r.URL.Path, "/mr/draft_notes/")
	id, err := strconv.Atoi(suffix)
	if err != nil {
		handleError(w, err, "Could not parse draft note ID", http.StatusBadRequest)
		return
	}

	res, err := a.client.DeleteDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, id)

	if err != nil {
		handleError(w, err, "Could not delete draft note", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not delete draft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: "Draft note deleted"}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

type UpdateDraftNoteRequest struct {
	Note     string `json:"note" validate:"required"`
	Position gitlab.PositionOptions
}

/* updateDraftNote edits the text of a draft comment */
func (a draftNoteService) updateDraftNote(w http.ResponseWriter, r *http.Request) {
	suffix := strings.TrimPrefix(r.URL.Path, "/mr/draft_notes/")
	id, err := strconv.Atoi(suffix)
	if err != nil {
		handleError(w, err, "Could not parse draft note ID", http.StatusBadRequest)
		return
	}

	payload := r.Context().Value(payload("payload")).(*UpdateDraftNoteRequest)

	if payload.Note == "" {
		handleError(w, errors.New("draft note text missing"), "Must provide draft note text", http.StatusBadRequest)
		return
	}

	opt := gitlab.UpdateDraftNoteOptions{
		Note:     &payload.Note,
		Position: &payload.Position,
	}

	draftNote, res, err := a.client.UpdateDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, id, &opt)

	if err != nil {
		handleError(w, err, "Could not update draft note", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not update draft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := DraftNoteResponse{
		SuccessResponse: SuccessResponse{Message: "Draft note updated"},
		DraftNote:       draftNote,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
