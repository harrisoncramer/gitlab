package app

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeDiscussionsLister struct {
	testBase
	badEmojiResponse bool
}

func (f fakeDiscussionsLister) ListMergeRequestDiscussions(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	timePointers := make([]*time.Time, 6)
	timePointers[0] = new(time.Time)
	*timePointers[0] = time.Now()
	for i := 1; i < len(timePointers); i++ {
		timePointers[i] = new(time.Time)
		*timePointers[i] = timePointers[i-1].Add(time.Second * 100)
	}

	type Author struct {
		ID        int    `json:"id"`
		Username  string `json:"username"`
		Email     string `json:"email"`
		Name      string `json:"name"`
		State     string `json:"state"`
		AvatarURL string `json:"avatar_url"`
		WebURL    string `json:"web_url"`
	}

	testListDiscussionsResponse := []*gitlab.Discussion{
		{Notes: []*gitlab.Note{
			{CreatedAt: timePointers[0], Type: "DiffNote", Author: Author{Username: "hcramer0"}},
			{CreatedAt: timePointers[4], Type: "DiffNote", Author: Author{Username: "hcramer1"}},
		}},
		{Notes: []*gitlab.Note{
			{CreatedAt: timePointers[2], Type: "DiffNote", Author: Author{Username: "hcramer2"}},
			{CreatedAt: timePointers[3], Type: "DiffNote", Author: Author{Username: "hcramer3"}},
		}},
		{Notes: []*gitlab.Note{
			{CreatedAt: timePointers[1], Type: "DiffNote", Author: Author{Username: "hcramer4"}},
			{CreatedAt: timePointers[5], Type: "DiffNote", Author: Author{Username: "hcramer5"}},
		}},
	}
	return testListDiscussionsResponse, resp, err
}

func (f fakeDiscussionsLister) ListMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID int, noteID int, opt *gitlab.ListAwardEmojiOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.AwardEmoji, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	if f.badEmojiResponse {
		return nil, nil, errors.New("Some error from emoji service")
	}
	return []*gitlab.AwardEmoji{}, resp, err
}

func getDiscussionsList(t *testing.T, svc http.Handler, request *http.Request) DiscussionsResponse {
	res := httptest.NewRecorder()
	svc.ServeHTTP(res, request)

	var data DiscussionsResponse
	err := json.Unmarshal(res.Body.Bytes(), &data)
	if err != nil {
		t.Error(err)
	}
	return data
}

func TestListDiscussions(t *testing.T) {
	t.Run("Returns discussions sorted by latest reply", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{}, SortBy: "latest_reply"})
		svc := middleware(
			discussionsListerService{testProjectData, fakeDiscussionsLister{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DiscussionsRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data := getDiscussionsList(t, svc, request)
		assert(t, data.Message, "Discussions retrieved")
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer4") /* Sorting applied */
		assert(t, data.Discussions[1].Notes[0].Author.Username, "hcramer0")
		assert(t, data.Discussions[2].Notes[0].Author.Username, "hcramer2")
	})

	t.Run("Returns discussions sorted by original comment", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{}, SortBy: "original_comment"})
		svc := middleware(
			discussionsListerService{testProjectData, fakeDiscussionsLister{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DiscussionsRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data := getDiscussionsList(t, svc, request)
		assert(t, data.Message, "Discussions retrieved")
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer0") /* Sorting applied */
		assert(t, data.Discussions[1].Notes[0].Author.Username, "hcramer4")
		assert(t, data.Discussions[2].Notes[0].Author.Username, "hcramer2")
	})

	t.Run("Uses blacklist to filter unwanted authors", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{"hcramer0"}, SortBy: "latest_reply"})
		svc := middleware(
			discussionsListerService{testProjectData, fakeDiscussionsLister{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DiscussionsRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data := getDiscussionsList(t, svc, request)
		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, len(data.Discussions), 2)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer4")
		assert(t, data.Discussions[1].Notes[0].Author.Username, "hcramer2")
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{}})
		svc := middleware(
			discussionsListerService{testProjectData, fakeDiscussionsLister{testBase: testBase{errFromGitlab: true}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DiscussionsRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not list discussions")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{}})
		svc := middleware(
			discussionsListerService{testProjectData, fakeDiscussionsLister{testBase: testBase{status: http.StatusSeeOther}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DiscussionsRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not list discussions", "/mr/discussions/list")
	})
	t.Run("Handles error from emoji service", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{}})
		svc := middleware(
			discussionsListerService{testProjectData, fakeDiscussionsLister{badEmojiResponse: true, testBase: testBase{}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[DiscussionsRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		assert(t, data.Message, "Could not fetch emojis")
		assert(t, data.Details, "Some error from emoji service")
	})
}
