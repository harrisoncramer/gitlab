package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type InfoResponse struct {
	SuccessResponse
	Info *gitlab.MergeRequest `json:"info"`
}

type MergeRequestGetter interface {
	GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
}

type infoService struct {
	data
	client MergeRequestGetter
}

/* infoHandler fetches infomation about the current git project. The data returned here is used in many other API calls */
func (a infoService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	mr, res, err := a.client.GetMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.GetMergeRequestsOptions{})
	if err != nil {
		handleError(w, err, "Could not get project info", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not get project info", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := InfoResponse{
		SuccessResponse: SuccessResponse{Message: "Merge requests retrieved"},
		Info:            mr,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
