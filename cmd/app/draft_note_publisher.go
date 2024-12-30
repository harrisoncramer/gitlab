package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type DraftNotePublisher interface {
	PublishAllDraftNotes(pid interface{}, mergeRequest int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	PublishDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
}

type draftNotePublisherService struct {
	data
	client DraftNotePublisher
}

type DraftNotePublishRequest struct {
	Note int `json:"note,omitempty"`
}

func (a draftNotePublisherService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*DraftNotePublishRequest)

	var res *gitlab.Response
	var err error
	if payload.Note != 0 {
		res, err = a.client.PublishDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, payload.Note)
	} else {
		res, err = a.client.PublishAllDraftNotes(a.projectInfo.ProjectId, a.projectInfo.MergeId)
	}

	if err != nil {
		handleError(w, err, "Could not publish draft note(s)", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not publish dfaft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: "Draft note(s) published"}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
