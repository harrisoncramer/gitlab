package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
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
		svc := middleware(withMr(discussionsResolutionService{testProjectData, fakeDiscussionResolver{}}, testProjectData, fakeMergeRequestLister{}),
			logMiddleware,
			validateMethods(http.MethodPut),
			validatePayload(&DiscussionResolveRequest{}))
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", testResolveMergeRequestPayload)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Discussion resolved")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Unresolves a discussion", func(t *testing.T) {
		payload := testResolveMergeRequestPayload
		payload.Resolved = false
		svc := middleware(withMr(discussionsResolutionService{testProjectData, fakeDiscussionResolver{}}, testProjectData, fakeMergeRequestLister{}),
			logMiddleware,
			validateMethods(http.MethodPut),
			validatePayload(&DiscussionResolveRequest{}))
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", payload)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Discussion unresolved")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Requires a discussion ID", func(t *testing.T) {
		payload := testResolveMergeRequestPayload
		payload.DiscussionID = ""
		svc := middleware(withMr(discussionsResolutionService{testProjectData, fakeDiscussionResolver{}}, testProjectData, fakeMergeRequestLister{}),
			logMiddleware,
			validateMethods(http.MethodPut),
			validatePayload(&DiscussionResolveRequest{}))
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", payload)
		data := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "DiscussionID is required")
		assert(t, data.Status, http.StatusBadRequest)
	})

	t.Run("Disallows non-PUT method", func(t *testing.T) {
		svc := middleware(withMr(discussionsResolutionService{testProjectData, fakeDiscussionResolver{}}, testProjectData, fakeMergeRequestLister{}),
			logMiddleware,
			validateMethods(http.MethodGet),
			validatePayload(&DiscussionResolveRequest{}))
		request := makeRequest(t, http.MethodPut, "/mr/discussions/resolve", testResolveMergeRequestPayload)
		data := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid request type")
		assert(t, data.Details, "Expected: GET")
		assert(t, data.Status, http.StatusMethodNotAllowed)
	})
}
