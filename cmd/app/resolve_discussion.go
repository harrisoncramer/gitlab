package app

import (
	"encoding/json"
	"fmt"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type DiscussionResolver interface {
	ResolveMergeRequestDiscussion(pid interface{}, mergeRequest int, discussion string, opt *gitlab.ResolveMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error)
}

type discussionsResolutionService struct {
	data
	client DiscussionResolver
}

type DiscussionResolveRequest struct {
	DiscussionID string `json:"discussion_id" validate:"required"`
	Resolved     bool   `json:"resolved"`
}

/* discussionsResolveHandler sets a discussion to be "resolved" or not resolved, depending on the payload */
func (a discussionsResolutionService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*DiscussionResolveRequest)

	_, res, err := a.client.ResolveMergeRequestDiscussion(
		a.projectInfo.ProjectId,
		a.projectInfo.MergeId,
		payload.DiscussionID,
		&gitlab.ResolveMergeRequestDiscussionOptions{Resolved: &payload.Resolved},
	)

	friendlyName := "unresolve"
	if payload.Resolved {
		friendlyName = "resolve"
	}

	if err != nil {
		handleError(w, err, fmt.Sprintf("Could not %s discussion", friendlyName), http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, fmt.Sprintf("Could not %s discussion", friendlyName), res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: fmt.Sprintf("Discussion %sd", friendlyName)}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
