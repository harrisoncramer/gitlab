package app

import (
	"net/http"
	"strings"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeMergeRequestListerByUsername struct {
	testBase
	emptyResponse bool
}

func (f fakeMergeRequestListerByUsername) ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	if f.emptyResponse {
		return []*gitlab.MergeRequest{}, resp, err
	}

	return []*gitlab.MergeRequest{{IID: 10}}, resp, err
}

func TestListMergeRequestByUsername(t *testing.T) {
	var testListMrsByUsernamePayload = MergeRequestByUsernameRequest{Username: "hcramer", UserId: 1234, State: "opened"}
	t.Run("Gets merge requests by username", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[MergeRequestByUsernameRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Merge requests fetched for hcramer")
	})

	t.Run("Should handle no merge requests", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{emptyResponse: true}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[MergeRequestByUsernameRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "No MRs found")
		assert(t, data.Details, "hcramer did not have any MRs")
		assert(t, status, http.StatusNotFound)
	})

	t.Run("Should require username", func(t *testing.T) {
		missingUsernamePayload := testListMrsByUsernamePayload
		missingUsernamePayload.Username = ""
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", missingUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[MergeRequestByUsernameRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "Username is required")
		assert(t, status, http.StatusBadRequest)
	})

	t.Run("Should require User ID for assignee call", func(t *testing.T) {
		missingUsernamePayload := testListMrsByUsernamePayload
		missingUsernamePayload.UserId = 0
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", missingUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[MergeRequestByUsernameRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "UserId is required")
		assert(t, status, http.StatusBadRequest)
	})

	t.Run("Should handle error from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{testBase: testBase{errFromGitlab: true}}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[MergeRequestByUsernameRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "An error occurred")
		assert(t, data.Details, strings.Repeat("some error from Gitlab; ", 3))
		assert(t, status, http.StatusInternalServerError)
	})

	t.Run("Handles non-200 from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{testBase: testBase{status: http.StatusSeeOther}}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[MergeRequestByUsernameRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "An error occurred")
		assert(t, data.Details, strings.Repeat("An error occurred on the /merge_requests_by_username endpoint; ", 3))
		assert(t, status, http.StatusInternalServerError)
	})
}
