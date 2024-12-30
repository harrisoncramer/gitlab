package app

import (
	"encoding/json"
	"io"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type LabelUpdateRequest struct {
	Labels []string `json:"labels"`
}

type Label struct {
	Name  string
	Color string
}

type LabelUpdateResponse struct {
	SuccessResponse
	Labels gitlab.Labels `json:"labels"`
}

type LabelsRequestResponse struct {
	SuccessResponse
	Labels []Label `json:"labels"`
}

type LabelManager interface {
	UpdateMergeRequest(interface{}, int, *gitlab.UpdateMergeRequestOptions, ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
	ListLabels(interface{}, *gitlab.ListLabelsOptions, ...gitlab.RequestOptionFunc) ([]*gitlab.Label, *gitlab.Response, error)
}

type labelService struct {
	data
	client LabelManager
}

/* labelsHandler adds or removes labels from a merge request, and returns all labels for the current project */
func (a labelService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.getLabels(w, r)
	case http.MethodPut:
		a.updateLabels(w, r)
	}
}

func (a labelService) getLabels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	labels, res, err := a.client.ListLabels(a.projectInfo.ProjectId, &gitlab.ListLabelsOptions{})

	if err != nil {
		handleError(w, err, "Could not modify merge request labels", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not modify merge request labels", res.StatusCode)
		return
	}

	/* Hacky, but convert them to the correct response */
	convertedLabels := make([]Label, len(labels))
	for i, labelPtr := range labels {
		convertedLabels[i] = Label{
			Name:  labelPtr.Name,
			Color: labelPtr.Color,
		}
	}

	w.WriteHeader(http.StatusOK)
	response := LabelsRequestResponse{
		SuccessResponse: SuccessResponse{Message: "Labels updated"},
		Labels:          convertedLabels,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}

func (a labelService) updateLabels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var labelUpdateRequest LabelUpdateRequest
	err = json.Unmarshal(body, &labelUpdateRequest)

	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	var labels = gitlab.LabelOptions(labelUpdateRequest.Labels)
	mr, res, err := a.client.UpdateMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.UpdateMergeRequestOptions{
		Labels: &labels,
	})

	if err != nil {
		handleError(w, err, "Could not modify merge request labels", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not modify merge request labels", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := LabelUpdateResponse{
		SuccessResponse: SuccessResponse{Message: "Labels updated"},
		Labels:          mr.Labels,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
