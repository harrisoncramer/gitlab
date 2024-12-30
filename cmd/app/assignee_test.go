package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeAssigneeClient struct {
	testBase
}

func (f fakeAssigneeClient) UpdateMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.MergeRequest{}, resp, nil
}

func TestAssigneeHandler(t *testing.T) {
	var updatePayload = AssigneeUpdateRequest{Ids: []int{1, 2}}

	t.Run("Updates assignees", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/assignee", updatePayload)
		svc := middleware(
			assigneesService{testProjectData, fakeAssigneeClient{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPut: newPayload[AssigneeUpdateRequest]}),
			withMethodCheck(http.MethodPut),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Assignees updated")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/assignee", updatePayload)
		client := fakeAssigneeClient{testBase{errFromGitlab: true}}
		svc := middleware(
			assigneesService{testProjectData, client},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPut: newPayload[AssigneeUpdateRequest]}),
			withMethodCheck(http.MethodPut),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not modify merge request assignees")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/assignee", updatePayload)
		client := fakeAssigneeClient{testBase{status: http.StatusSeeOther}}
		svc := middleware(
			assigneesService{testProjectData, client},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{http.MethodPut: newPayload[AssigneeUpdateRequest]}),
			withMethodCheck(http.MethodPut),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not modify merge request assignees", "/mr/assignee")
	})
}
