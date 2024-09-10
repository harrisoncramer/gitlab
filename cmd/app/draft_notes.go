package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/xanzy/go-gitlab"
)

/* The data coming from the client when creating a draft note is the same,
as when they are creating a normal comment, but the Gitlab
endpoints + resources we handle are different */

type PostDraftNoteRequest struct {
	Comment      string `json:"comment"`
	DiscussionId string `json:"discussion_id,omitempty"`
	PositionData
}

type UpdateDraftNoteRequest struct {
	Note     string `json:"note"`
	Position gitlab.PositionOptions
}

type DraftNotePublishRequest struct {
	Note       int  `json:"note,omitempty"`
	PublishAll bool `json:"publish_all"`
}

type DraftNoteResponse struct {
	SuccessResponse
	DraftNote *gitlab.DraftNote `json:"draft_note"`
}

type ListDraftNotesResponse struct {
	SuccessResponse
	DraftNotes []*gitlab.DraftNote `json:"draft_notes"`
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
	default:
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s, %s, %s", http.MethodDelete, http.MethodPost, http.MethodPatch, http.MethodGet))
		handleError(w, InvalidRequestError{}, "Expected DELETE, GET, POST or PATCH", http.StatusMethodNotAllowed)
	}
}

/* listDraftNotes lists all draft notes for the currently authenticated user */
func (a draftNoteService) listDraftNotes(w http.ResponseWriter, _ *http.Request) {

	opt := gitlab.ListDraftNotesOptions{}
	draftNotes, res, err := a.client.ListDraftNotes(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opt)

	if err != nil {
		handleError(w, err, "Could not get draft notes", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/draft_notes/"}, "Could not get draft notes", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ListDraftNotesResponse{
		SuccessResponse: SuccessResponse{
			Message: "Draft notes fetched successfully",
			Status:  http.StatusOK,
		},
		DraftNotes: draftNotes,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/* postDraftNote creates a draft note */
func (a draftNoteService) postDraftNote(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var postDraftNoteRequest PostDraftNoteRequest
	err = json.Unmarshal(body, &postDraftNoteRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	opt := gitlab.CreateDraftNoteOptions{
		Note: &postDraftNoteRequest.Comment,
	}

	// Draft notes can be posted in "response" to existing discussions
	if postDraftNoteRequest.DiscussionId != "" {
		opt.InReplyToDiscussionID = gitlab.Ptr(postDraftNoteRequest.DiscussionId)
	}

	if postDraftNoteRequest.FileName != "" {
		draftNoteWithPosition := DraftNoteWithPosition{postDraftNoteRequest.PositionData}
		opt.Position = buildCommentPosition(draftNoteWithPosition)
	}

	draftNote, res, err := a.client.CreateDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opt)

	if err != nil {
		handleError(w, err, "Could not create draft note", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/draft_notes/"}, "Could not create draft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := DraftNoteResponse{
		SuccessResponse: SuccessResponse{
			Message: "Draft note created successfully",
			Status:  http.StatusOK,
		},
		DraftNote: draftNote,
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
		handleError(w, GenericError{endpoint: fmt.Sprintf("/mr/draft_notes/%d", id)}, "Could not delete draft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Draft note deleted",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/* updateDraftNote edits the text of a draft comment */
func (a draftNoteService) updateDraftNote(w http.ResponseWriter, r *http.Request) {
	suffix := strings.TrimPrefix(r.URL.Path, "/mr/draft_notes/")
	id, err := strconv.Atoi(suffix)
	if err != nil {
		handleError(w, err, "Could not parse draft note ID", http.StatusBadRequest)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var updateDraftNoteRequest UpdateDraftNoteRequest
	err = json.Unmarshal(body, &updateDraftNoteRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	if updateDraftNoteRequest.Note == "" {
		handleError(w, errors.New("Draft note text missing"), "Must provide draft note text", http.StatusBadRequest)
		return
	}

	opt := gitlab.UpdateDraftNoteOptions{
		Note:     &updateDraftNoteRequest.Note,
		Position: &updateDraftNoteRequest.Position,
	}

	draftNote, res, err := a.client.UpdateDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, id, &opt)

	if err != nil {
		handleError(w, err, "Could not update draft note", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: fmt.Sprintf("/mr/draft_notes/%d", id)}, "Could not update draft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := DraftNoteResponse{
		SuccessResponse: SuccessResponse{
			Message: "Draft note updated",
			Status:  http.StatusOK,
		},
		DraftNote: draftNote,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
