package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sync"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type MergeRequestListerByUsername interface {
	ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestListerByUsernameService struct {
	data
	client MergeRequestListerByUsername
}

type MergeRequestByUsernameRequest struct {
	UserId   int    `json:"user_id" validate:"required"`
	Username string `json:"username" validate:"required"`
	State    string `json:"state,omitempty"`
}

// Returns a list of merge requests where the given username/id is either an assignee, reviewer, or author
func (a mergeRequestListerByUsernameService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	request := r.Context().Value(payload("payload")).(*MergeRequestByUsernameRequest)

	if request.State == "" {
		request.State = "opened"
	}

	payloads := []gitlab.ListProjectMergeRequestsOptions{
		{
			AuthorUsername: gitlab.Ptr(request.Username),
			State:          gitlab.Ptr(request.State),
			Scope:          gitlab.Ptr("all"),
		},
		{
			ReviewerUsername: gitlab.Ptr(request.Username),
			State:            gitlab.Ptr(request.State),
			Scope:            gitlab.Ptr("all"),
		},
		{
			AssigneeID: gitlab.AssigneeID(request.UserId),
			State:      gitlab.Ptr(request.State),
			Scope:      gitlab.Ptr("all"),
		},
	}

	type apiResponse struct {
		mrs []*gitlab.MergeRequest
		err error
	}

	mrChan := make(chan apiResponse, len(payloads))
	wg := sync.WaitGroup{}
	go func() {
		wg.Wait()
		close(mrChan)
	}()

	for _, payload := range payloads {
		wg.Add(1)
		go func(p gitlab.ListProjectMergeRequestsOptions) {
			defer wg.Done()
			mrs, err := a.getMrs(&p)
			mrChan <- apiResponse{mrs, err}
		}(payload)
	}

	var mergeRequests []*gitlab.MergeRequest
	existingIds := make(map[int]bool)
	var errs []error
	for res := range mrChan {
		if res.err != nil {
			errs = append(errs, res.err)
		} else {
			for _, mr := range res.mrs {
				if !existingIds[mr.ID] {
					mergeRequests = append(mergeRequests, mr)
					existingIds[mr.ID] = true
				}
			}
		}
	}

	if len(errs) > 0 {
		combinedErr := ""
		for _, err := range errs {
			combinedErr += err.Error() + "; "
		}
		handleError(w, errors.New(combinedErr), "An error occurred", http.StatusInternalServerError)
		return
	}

	if len(mergeRequests) == 0 {
		handleError(w, fmt.Errorf("%s did not have any MRs", request.Username), "No MRs found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ListMergeRequestResponse{
		SuccessResponse: SuccessResponse{Message: fmt.Sprintf("Merge requests fetched for %s", request.Username)},
		MergeRequests:   mergeRequests,
	}

	err := json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

func (a mergeRequestListerByUsernameService) getMrs(payload *gitlab.ListProjectMergeRequestsOptions) ([]*gitlab.MergeRequest, error) {
	mrs, res, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, payload)
	if err != nil {
		return []*gitlab.MergeRequest{}, err
	}

	if res.StatusCode >= 300 {
		return []*gitlab.MergeRequest{}, GenericError{endpoint: "/merge_requests_by_username"}
	}

	defer res.Body.Close()

	return mrs, err
}
