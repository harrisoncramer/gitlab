package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type RevisionsResponse struct {
	SuccessResponse
	Revisions []*gitlab.MergeRequestDiffVersion
}

type RevisionsGetter interface {
	GetMergeRequestDiffVersions(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestDiffVersionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequestDiffVersion, *gitlab.Response, error)
}

type revisionsService struct {
	data
	client RevisionsGetter
}

/*
revisionsHandler gets revision information about the current MR. This data is not used directly but is
a precursor API call for other functionality
*/
func (a revisionsService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	versionInfo, res, err := a.client.GetMergeRequestDiffVersions(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.GetMergeRequestDiffVersionsOptions{})
	if err != nil {
		handleError(w, err, "Could not get diff version info", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not get diff version info", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := RevisionsResponse{
		SuccessResponse: SuccessResponse{Message: "Revisions fetched successfully"},
		Revisions:       versionInfo,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}
