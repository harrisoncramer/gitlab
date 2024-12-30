package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type ReviewerUpdateRequest struct {
	Ids []int `json:"ids" validate:"required"`
}

type ReviewerUpdateResponse struct {
	SuccessResponse
	Reviewers []*gitlab.BasicUser `json:"reviewers"`
}

type ReviewersRequestResponse struct {
	SuccessResponse
	Reviewers []int `json:"reviewers"`
}

type MergeRequestUpdater interface {
	UpdateMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
}

type reviewerService struct {
	data
	client MergeRequestUpdater
}

/* reviewersHandler adds or removes reviewers from an MR */
func (a reviewerService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*ReviewerUpdateRequest)

	mr, res, err := a.client.UpdateMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.UpdateMergeRequestOptions{
		ReviewerIDs: &payload.Ids,
	})

	if err != nil {
		handleError(w, err, "Could not modify merge request reviewers", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not modify merge request reviewers", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ReviewerUpdateResponse{
		SuccessResponse: SuccessResponse{Message: "Reviewers updated"},
		Reviewers:       mr.Reviewers,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
