package main

import (
	"encoding/json"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type RevisionsResponse struct {
	SuccessResponse
	Revisions []*gitlab.MergeRequestDiffVersion
}

/*
revisionsHandler gets revision information about the current MR. This data is not used directly but is
a precursor API call for other functionality
*/
func (a *api) revisionsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
		handleError(w, InvalidRequestError{}, "Expected GET", http.StatusMethodNotAllowed)
		return
	}

	versionInfo, res, err := a.client.GetMergeRequestDiffVersions(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.GetMergeRequestDiffVersionsOptions{})
	if err != nil {
		handleError(w, err, "Could not get diff version info", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/revisions"}, "Could not get diff version info", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := RevisionsResponse{
		SuccessResponse: SuccessResponse{
			Message: "Revisions fetched successfully",
			Status:  http.StatusOK,
		},
		Revisions: versionInfo,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}
