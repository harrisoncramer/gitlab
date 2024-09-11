package app

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
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

func (a mergeRequestListerService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var listMergeRequestRequest gitlab.ListProjectMergeRequestsOptions
	err = json.Unmarshal(body, &listMergeRequestRequest)
	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	if listMergeRequestRequest.State == nil {
		listMergeRequestRequest.State = gitlab.Ptr("opened")
	}

	if listMergeRequestRequest.Scope == nil {
		listMergeRequestRequest.Scope = gitlab.Ptr("all")
	}

	mergeRequests, res, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, &listMergeRequestRequest)

	if err != nil {
		handleError(w, err, "Failed to list merge requests", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/merge_requests"}, "Failed to list merge requests", res.StatusCode)
		return
	}

	if len(mergeRequests) == 0 {
		handleError(w, errors.New("No merge requests found"), "No merge requests found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ListMergeRequestResponse{
		SuccessResponse: SuccessResponse{Message: "Merge requests fetched successfully"},
		MergeRequests:   mergeRequests,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
