package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type MergeRequestRevoker interface {
	UnapproveMergeRequest(interface{}, int, ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
}

type mergeRequestRevokerService struct {
	data
	client MergeRequestRevoker
}

/* revokeHandler revokes approval for the current merge request */
func (a mergeRequestRevokerService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	res, err := a.client.UnapproveMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, nil, nil)

	if err != nil {
		handleError(w, err, "Could not revoke approval", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not revoke approval", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: "Success! Revoked MR approval"}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
