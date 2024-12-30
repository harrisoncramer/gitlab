package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeMemberLister struct {
	testBase
}

func (f fakeMemberLister) ListAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return []*gitlab.ProjectMember{}, resp, err
}

func TestMembersHandler(t *testing.T) {
	t.Run("Returns project members", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		svc := middleware(
			projectMemberService{testProjectData, fakeMemberLister{}},
			withMethodCheck(http.MethodGet),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Project members retrieved")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		svc := middleware(
			projectMemberService{testProjectData, fakeMemberLister{testBase{errFromGitlab: true}}},
			withMethodCheck(http.MethodGet),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not retrieve project members")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		svc := middleware(
			projectMemberService{testProjectData, fakeMemberLister{testBase{status: http.StatusSeeOther}}},
			withMethodCheck(http.MethodGet),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not retrieve project members", "/project/members")
	})
}
