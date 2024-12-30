package app

import (
	"encoding/json"
	"errors"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type ListMergeRequestResponse struct {
	SuccessResponse
	MergeRequests []*gitlab.MergeRequest `json:"merge_requests"`
}

type MergeRequestLister interface {
	ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestListerService struct {
	data
	client MergeRequestLister
}

// Lists all merge requests in Gitlab according to the provided filters
func (a mergeRequestListerService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	payload := r.Context().Value(payload("payload")).(*gitlab.ListProjectMergeRequestsOptions)

	if payload.State == nil {
		payload.State = gitlab.Ptr("opened")
	}

	if payload.Scope == nil {
		payload.Scope = gitlab.Ptr("all")
	}

	mergeRequests, res, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, payload)

	if err != nil {
		handleError(w, err, "Failed to list merge requests", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Failed to list merge requests", res.StatusCode)
		return
	}

	if len(mergeRequests) == 0 {
		handleError(w, errors.New("no merge requests found"), "No merge requests found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ListMergeRequestResponse{
		SuccessResponse: SuccessResponse{Message: "Merge requests fetched successfully"},
		MergeRequests:   mergeRequests,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "could not encode response", http.StatusInternalServerError)
	}
}
