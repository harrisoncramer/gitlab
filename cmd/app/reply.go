package app

import (
	"encoding/json"
	"net/http"
	"time"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type ReplyRequest struct {
	DiscussionId string `json:"discussion_id" validate:"required"`
	Reply        string `json:"reply" validate:"required"`
	IsDraft      bool   `json:"is_draft"`
}

type ReplyResponse struct {
	SuccessResponse
	Note *gitlab.Note `json:"note"`
}

type ReplyManager interface {
	AddMergeRequestDiscussionNote(interface{}, int, string, *gitlab.AddMergeRequestDiscussionNoteOptions, ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error)
}

type replyService struct {
	data
	client ReplyManager
}

/* replyHandler sends a reply to a note or comment */
func (a replyService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	replyRequest := r.Context().Value(payload("payload")).(*ReplyRequest)

	now := time.Now()
	options := gitlab.AddMergeRequestDiscussionNoteOptions{
		Body:      gitlab.Ptr(replyRequest.Reply),
		CreatedAt: &now,
	}

	note, res, err := a.client.AddMergeRequestDiscussionNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, replyRequest.DiscussionId, &options)

	if err != nil {
		handleError(w, err, "Could not leave reply", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not leave reply", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ReplyResponse{
		SuccessResponse: SuccessResponse{Message: "Replied to comment"},
		Note:            note,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
