package app

import (
	"encoding/json"
	"errors"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type AssigneeUpdateRequest struct {
	Ids []int `json:"ids" validate:"required"`
}

type AssigneeUpdateResponse struct {
	SuccessResponse
	Assignees []*gitlab.BasicUser `json:"assignees"`
}

type assigneesService struct {
	data
	client MergeRequestUpdater
}

/* assigneesHandler adds or removes assignees from a merge request. */
func (a assigneesService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	assigneeUpdateRequest, ok := r.Context().Value(payload("payload")).(*AssigneeUpdateRequest)

	if !ok {
		handleError(w, errors.New("could not get payload from context"), "Bad payload", http.StatusInternalServerError)
		return
	}

	mr, res, err := a.client.UpdateMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.UpdateMergeRequestOptions{
		AssigneeIDs: &assigneeUpdateRequest.Ids,
	})

	if err != nil {
		handleError(w, err, "Could not modify merge request assignees", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not modify merge request assignees", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := AssigneeUpdateResponse{
		SuccessResponse: SuccessResponse{Message: "Assignees updated"},
		Assignees:       mr.Assignees,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
