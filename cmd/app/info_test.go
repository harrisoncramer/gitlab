package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeMergeRequestGetter struct {
	testBase
}

func (f fakeMergeRequestGetter) GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return &gitlab.MergeRequest{}, resp, err
}

func TestInfoHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		svc := middleware(
			infoService{testProjectData, fakeMergeRequestGetter{}},
			withMethodCheck(http.MethodGet),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Merge requests retrieved")
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		svc := middleware(
			infoService{testProjectData, fakeMergeRequestGetter{testBase{errFromGitlab: true}}},
			withMethodCheck(http.MethodGet),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not get project info")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		svc := middleware(
			infoService{testProjectData, fakeMergeRequestGetter{testBase{status: http.StatusSeeOther}}},
			withMethodCheck(http.MethodGet),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not get project info", "/mr/info")
	})
}
