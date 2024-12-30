package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeApproverClient struct {
	testBase
}

func (f fakeApproverClient) ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.MergeRequestApprovals{}, resp, nil
}

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApproverClient{}
		svc := middleware(
			mergeRequestApproverService{testProjectData, client},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Approved MR")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApproverClient{testBase{errFromGitlab: true}}
		svc := middleware(
			mergeRequestApproverService{testProjectData, client},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not approve merge request")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApproverClient{testBase{status: http.StatusSeeOther}}
		svc := middleware(
			mergeRequestApproverService{testProjectData, client},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not approve merge request", "/mr/approve")
	})
}
