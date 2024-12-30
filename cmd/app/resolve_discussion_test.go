package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeDiscussionResolver struct {
	testBase
}

func (f fakeDiscussionResolver) ResolveMergeRequestDiscussion(pid interface{}, mergeRequest int, discussion string, opt *gitlab.ResolveMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return &gitlab.Discussion{}, resp, err
}

func TestResolveDiscussion(t *testing.T) {
	var testResolveMergeRequestPayload = DiscussionResolveRequest{
		DiscussionID: "abc123",
		Resolved:     true,
	}

	t.Run("Resolves a discussion", func(t *testing.T) {
		svc := middleware(
			discussionsResolutionService{testProjectData, fakeDiscussionResolver{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPut: newPayload[DiscussionResolveRequest]}),
			withMethodCheck(http.MethodPut),
		)
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", testResolveMergeRequestPayload)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Discussion resolved")
	})

	t.Run("Unresolves a discussion", func(t *testing.T) {
		payload := testResolveMergeRequestPayload
		payload.Resolved = false
		svc := middleware(
			discussionsResolutionService{testProjectData, fakeDiscussionResolver{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPut: newPayload[DiscussionResolveRequest]}),
			withMethodCheck(http.MethodPut),
		)
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", payload)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Discussion unresolved")
	})

	t.Run("Requires a discussion ID", func(t *testing.T) {
		payload := testResolveMergeRequestPayload
		payload.DiscussionID = ""
		svc := middleware(
			discussionsResolutionService{testProjectData, fakeDiscussionResolver{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPut: newPayload[DiscussionResolveRequest]}),
			withMethodCheck(http.MethodPut),
		)
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", payload)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "DiscussionID is required")
		assert(t, status, http.StatusBadRequest)
	})

	t.Run("Handles error from Gitlab", func(t *testing.T) {
		svc := middleware(
			discussionsResolutionService{testProjectData, fakeDiscussionResolver{testBase: testBase{errFromGitlab: true}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPut: newPayload[DiscussionResolveRequest]}),
			withMethodCheck(http.MethodPut),
		)
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", testResolveMergeRequestPayload)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "Could not resolve discussion")
		assert(t, data.Details, "some error from Gitlab")
		assert(t, status, http.StatusInternalServerError)
	})
}
