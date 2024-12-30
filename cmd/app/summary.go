package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type SummaryUpdateRequest struct {
	Title       string `json:"title" validate:"required"`
	Description string `json:"description"`
}

type SummaryUpdateResponse struct {
	SuccessResponse
	MergeRequest *gitlab.MergeRequest `json:"mr"`
}

type summaryService struct {
	data
	client MergeRequestUpdater
}

func (a summaryService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	payload := r.Context().Value(payload("payload")).(*SummaryUpdateRequest)

	mr, res, err := a.client.UpdateMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.UpdateMergeRequestOptions{
		Description: &payload.Description,
		Title:       &payload.Title,
	})

	if err != nil {
		handleError(w, err, "Could not edit merge request summary", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not edit merge request summary", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := SummaryUpdateResponse{
		SuccessResponse: SuccessResponse{Message: "Summary updated"},
		MergeRequest:    mr,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}
