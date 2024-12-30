package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type MergeRequestApprover interface {
	ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error)
}

type mergeRequestApproverService struct {
	data
	client MergeRequestApprover
}

/* approveHandler approves a merge request. */
func (a mergeRequestApproverService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	_, res, err := a.client.ApproveMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, nil, nil)

	if err != nil {
		handleError(w, err, "Could not approve merge request", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not approve merge request", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: "Approved MR"}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
