package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeMergeCreatorClient struct {
	testBase
}

func (f fakeMergeCreatorClient) CreateMergeRequest(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.MergeRequest{}, resp, nil
}

func TestCreateMr(t *testing.T) {
	var testCreateMrRequestData = CreateMrRequest{
		Title:        "Some title",
		Description:  "Some description",
		TargetBranch: "main",
		DeleteBranch: false,
		Squash:       false,
	}
	t.Run("Creates an MR", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/create_mr", testCreateMrRequestData)
		svc := middleware(
			mergeRequestCreatorService{testProjectData, fakeMergeCreatorClient{}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[CreateMrRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "MR 'Some title' created")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/create_mr", testCreateMrRequestData)
		svc := middleware(
			mergeRequestCreatorService{testProjectData, fakeMergeCreatorClient{testBase{errFromGitlab: true}}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[CreateMrRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not create MR")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/create_mr", testCreateMrRequestData)
		svc := middleware(
			mergeRequestCreatorService{testProjectData, fakeMergeCreatorClient{testBase{status: http.StatusSeeOther}}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[CreateMrRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not create MR", "/create_mr")
	})

	t.Run("Handles missing titles", func(t *testing.T) {
		reqData := testCreateMrRequestData
		reqData.Title = ""
		request := makeRequest(t, http.MethodPost, "/create_mr", reqData)
		svc := middleware(
			mergeRequestCreatorService{testProjectData, fakeMergeCreatorClient{}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[CreateMrRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "Title is required")
	})

	t.Run("Handles missing target branch", func(t *testing.T) {
		reqData := testCreateMrRequestData
		reqData.TargetBranch = ""
		request := makeRequest(t, http.MethodPost, "/create_mr", reqData)
		svc := middleware(
			mergeRequestCreatorService{testProjectData, fakeMergeCreatorClient{}},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[CreateMrRequest]}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "TargetBranch is required")
	})
}
