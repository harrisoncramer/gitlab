package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeMergeRequestLister struct {
	testBase
	emptyResponse bool
	multipleMrs   bool
}

func (f fakeMergeRequestLister) ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	if f.emptyResponse {
		return []*gitlab.MergeRequest{}, resp, err
	}

	if f.multipleMrs {
		return []*gitlab.MergeRequest{{IID: 10}, {IID: 11}}, resp, err
	}

	return []*gitlab.MergeRequest{{IID: 10}}, resp, err
}

func TestMergeRequestHandler(t *testing.T) {
	var testListMergeRequestsRequest = gitlab.ListProjectMergeRequestsOptions{}
	t.Run("Should fetch merge requests", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := middleware(
			mergeRequestListerService{testProjectData, fakeMergeRequestLister{}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[gitlab.ListProjectMergeRequestsOptions]}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Merge requests fetched successfully")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := middleware(
			mergeRequestListerService{testProjectData, fakeMergeRequestLister{testBase: testBase{errFromGitlab: true}}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[gitlab.ListProjectMergeRequestsOptions]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Failed to list merge requests")
		assert(t, status, http.StatusInternalServerError)
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := middleware(
			mergeRequestListerService{testProjectData, fakeMergeRequestLister{testBase: testBase{status: http.StatusSeeOther}}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[gitlab.ListProjectMergeRequestsOptions]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		checkNon200(t, data, "Failed to list merge requests", "/merge_requests")
		assert(t, status, http.StatusSeeOther)
	})
	t.Run("Should handle not having any merge requests with 404", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := middleware(
			mergeRequestListerService{testProjectData, fakeMergeRequestLister{emptyResponse: true}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[gitlab.ListProjectMergeRequestsOptions]}),
			withMethodCheck(http.MethodPost),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "No merge requests found")
		assert(t, status, http.StatusNotFound)
	})
}
