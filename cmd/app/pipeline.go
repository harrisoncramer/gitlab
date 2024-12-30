package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type RetriggerPipelineResponse struct {
	SuccessResponse
	LatestPipeline *gitlab.Pipeline `json:"latest_pipeline"`
}

type PipelineWithJobs struct {
	Jobs           []*gitlab.Job        `json:"jobs"`
	LatestPipeline *gitlab.PipelineInfo `json:"latest_pipeline"`
}

type GetPipelineAndJobsResponse struct {
	SuccessResponse
	Pipeline PipelineWithJobs `json:"latest_pipeline"`
}

type PipelineManager interface {
	ListProjectPipelines(pid interface{}, opt *gitlab.ListProjectPipelinesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.PipelineInfo, *gitlab.Response, error)
	ListPipelineJobs(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error)
	RetryPipelineBuild(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error)
}

type pipelineService struct {
	data
	client     PipelineManager
	gitService git.GitManager
}

/*
pipelineHandler fetches information about the current pipeline, and retriggers a pipeline run. For more detailed information
about a given job in a pipeline, see the jobHandler function
*/
func (a pipelineService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.GetPipelineAndJobs(w, r)
	case http.MethodPost:
		a.RetriggerPipeline(w, r)
	}
}

/* Gets the latest pipeline for a given commit, returns an error if there is no pipeline */
func (a pipelineService) GetLastPipeline(commit string) (*gitlab.PipelineInfo, error) {

	l := &gitlab.ListProjectPipelinesOptions{
		SHA:  gitlab.Ptr(commit),
		Sort: gitlab.Ptr("desc"),
	}

	pipes, res, err := a.client.ListProjectPipelines(a.projectInfo.ProjectId, l)

	if err != nil {
		return nil, err
	}

	if res.StatusCode >= 300 {
		return nil, errors.New("could not get pipelines")
	}

	if len(pipes) == 0 {
		return nil, errors.New("No pipeline running or available for commit " + commit)
	}

	return pipes[0], nil
}

/* Gets the latest pipeline and job information for the current branch */
func (a pipelineService) GetPipelineAndJobs(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	commit, err := a.gitService.GetLatestCommitOnRemote(pluginOptions.ConnectionSettings.Remote, a.gitInfo.BranchName)

	if err != nil {
		handleError(w, err, "Error getting commit on remote branch", http.StatusInternalServerError)
		return
	}

	pipeline, err := a.GetLastPipeline(commit)

	if err != nil {
		handleError(w, err, fmt.Sprintf("Failed to get latest pipeline for %s branch", a.gitInfo.BranchName), http.StatusInternalServerError)
		return
	}

	if pipeline == nil {
		handleError(w, GenericError{r.URL.Path}, fmt.Sprintf("No pipeline found for %s branch", a.gitInfo.BranchName), http.StatusInternalServerError)
		return
	}

	jobs, res, err := a.client.ListPipelineJobs(a.projectInfo.ProjectId, pipeline.ID, &gitlab.ListJobsOptions{})

	if err != nil {
		handleError(w, err, "Could not get pipeline jobs", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not get pipeline jobs", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := GetPipelineAndJobsResponse{
		SuccessResponse: SuccessResponse{Message: "Pipeline retrieved"},
		Pipeline: PipelineWithJobs{
			LatestPipeline: pipeline,
			Jobs:           jobs,
		},
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

func (a pipelineService) RetriggerPipeline(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	id := strings.TrimPrefix(r.URL.Path, "/pipeline/trigger/")

	idInt, err := strconv.Atoi(id)
	if err != nil {
		handleError(w, err, "Could not convert pipeline ID to integer", http.StatusBadRequest)
		return
	}

	pipeline, res, err := a.client.RetryPipelineBuild(a.projectInfo.ProjectId, idInt)

	if err != nil {
		handleError(w, err, "Could not retrigger pipeline", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not retrigger pipeline", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := RetriggerPipelineResponse{
		SuccessResponse: SuccessResponse{Message: "Pipeline retriggered"},
		LatestPipeline:  pipeline,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
