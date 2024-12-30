package app

import (
	"encoding/json"
	"fmt"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type CreateMrRequest struct {
	Title           string `json:"title" validate:"required"`
	TargetBranch    string `json:"target_branch" validate:"required"`
	Description     string `json:"description"`
	TargetProjectID int    `json:"forked_project_id,omitempty"`
	DeleteBranch    bool   `json:"delete_branch"`
	Squash          bool   `json:"squash"`
}

type MergeRequestCreator interface {
	CreateMergeRequest(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestCreatorService struct {
	data
	client MergeRequestCreator
}

/* createMr creates a merge request */
func (a mergeRequestCreatorService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	createMrRequest := r.Context().Value(payload("payload")).(*CreateMrRequest)

	opts := gitlab.CreateMergeRequestOptions{
		Title:              &createMrRequest.Title,
		Description:        &createMrRequest.Description,
		TargetBranch:       &createMrRequest.TargetBranch,
		SourceBranch:       &a.gitInfo.BranchName,
		RemoveSourceBranch: &createMrRequest.DeleteBranch,
		Squash:             &createMrRequest.Squash,
	}

	if createMrRequest.TargetProjectID != 0 {
		opts.TargetProjectID = gitlab.Ptr(createMrRequest.TargetProjectID)
	}

	_, res, err := a.client.CreateMergeRequest(a.projectInfo.ProjectId, &opts)

	if err != nil {
		handleError(w, err, "Could not create MR", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not create MR", res.StatusCode)
		return
	}

	response := SuccessResponse{Message: fmt.Sprintf("MR '%s' created", createMrRequest.Title)}

	w.WriteHeader(http.StatusOK)

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
