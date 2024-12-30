package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeDraftNotePublisher struct {
	testBase
}

func (f fakeDraftNotePublisher) PublishAllDraftNotes(pid interface{}, mergeRequest int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.handleGitlabError()
}
func (f fakeDraftNotePublisher) PublishDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.handleGitlabError()
}

func TestPublishDraftNote(t *testing.T) {
	var testDraftNotePublishRequest = DraftNotePublishRequest{Note: 3}
	t.Run("Publishes draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := middleware(
			draftNotePublisherService{testProjectData, fakeDraftNotePublisher{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DraftNotePublishRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Draft note(s) published")
	})
	t.Run("Handles error from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := middleware(
			draftNotePublisherService{testProjectData, fakeDraftNotePublisher{testBase: testBase{errFromGitlab: true}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DraftNotePublishRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not publish draft note(s)")
	})
}

func TestPublishAllDraftNotes(t *testing.T) {
	var testDraftNotePublishRequest = DraftNotePublishRequest{}
	t.Run("Should publish all draft notes", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := middleware(
			draftNotePublisherService{testProjectData, fakeDraftNotePublisher{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DraftNotePublishRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Draft note(s) published")
	})
	t.Run("Handles error from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := middleware(
			draftNotePublisherService{testProjectData, fakeDraftNotePublisher{testBase: testBase{errFromGitlab: true}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DraftNotePublishRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not publish draft note(s)")
	})
}
