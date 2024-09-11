package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeMergeRequestAccepter struct {
	testBase
}

func (f fakeMergeRequestAccepter) AcceptMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.AcceptMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return &gitlab.MergeRequest{}, resp, err
}

func TestAcceptAndMergeHandler(t *testing.T) {
	var testAcceptMergeRequestPayload = AcceptMergeRequestRequest{Squash: false, SquashMessage: "Squash me!", DeleteBranch: false}
	t.Run("Accepts and merges a merge request", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/merge", testAcceptMergeRequestPayload)
		svc := middleware(
			mergeRequestAccepterService{testProjectData, fakeMergeRequestAccepter{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			validatePayloads(methodToPayload{
				http.MethodPost: &AcceptMergeRequestRequest{},
			}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "MR merged successfully")
	})
	t.Run("Disallows non-POST methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/merge", testAcceptMergeRequestPayload)
		svc := middleware(
			mergeRequestAccepterService{testProjectData, fakeMergeRequestAccepter{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			validatePayloads(methodToPayload{
				http.MethodPost: &AcceptMergeRequestRequest{},
			}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodPost)
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/merge", testAcceptMergeRequestPayload)
		svc := middleware(
			mergeRequestAccepterService{testProjectData, fakeMergeRequestAccepter{testBase{errFromGitlab: true}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			validatePayloads(methodToPayload{
				http.MethodPost: &AcceptMergeRequestRequest{},
			}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not merge MR")
	})
	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/merge", testAcceptMergeRequestPayload)
		svc := middleware(
			mergeRequestAccepterService{testProjectData, fakeMergeRequestAccepter{testBase{status: http.StatusSeeOther}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			validatePayloads(methodToPayload{
				http.MethodPost: &AcceptMergeRequestRequest{},
			}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not merge MR", "/mr/merge")
	})
}
