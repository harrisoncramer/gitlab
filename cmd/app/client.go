package app

import (
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
	"github.com/hashicorp/go-retryablehttp"
	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type ProjectInfo struct {
	ProjectId string
	MergeId   int
}

/* The Client struct embeds all the methods from Gitlab for the different services */
type Client struct {
	*gitlab.MergeRequestsService
	*gitlab.MergeRequestApprovalsService
	*gitlab.DiscussionsService
	*gitlab.ProjectsService
	*gitlab.ProjectMembersService
	*gitlab.JobsService
	*gitlab.PipelinesService
	*gitlab.LabelsService
	*gitlab.AwardEmojiService
	*gitlab.UsersService
	*gitlab.DraftNotesService
}

/* NewClient parses and validates the project settings and initializes the Gitlab client. */
func NewClient() (*Client, error) {

	if pluginOptions.GitlabUrl == "" {
		return nil, errors.New("GitLab instance URL cannot be empty")
	}

	var apiCustUrl = fmt.Sprintf("%s/api/v4", pluginOptions.GitlabUrl)

	gitlabOptions := []gitlab.ClientOptionFunc{
		gitlab.WithBaseURL(apiCustUrl),
	}

	if pluginOptions.Debug.GitlabRequest {
		gitlabOptions = append(gitlabOptions, gitlab.WithRequestLogHook(
			func(l retryablehttp.Logger, r *http.Request, i int) {
				logRequest("REQUEST TO GITLAB", r)
			},
		))
	}

	if pluginOptions.Debug.GitlabResponse {
		gitlabOptions = append(gitlabOptions, gitlab.WithResponseLogHook(func(l retryablehttp.Logger, response *http.Response) {
			logResponse("RESPONSE FROM GITLAB", response)
		},
		))
	}

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: pluginOptions.ConnectionSettings.Insecure,
		},
	}

	retryClient := retryablehttp.NewClient()
	retryClient.HTTPClient.Transport = tr
	retryClient.RetryMax = 0
	gitlabOptions = append(gitlabOptions, gitlab.WithHTTPClient(retryClient.HTTPClient))

	client, err := gitlab.NewClient(pluginOptions.AuthToken, gitlabOptions...)

	if err != nil {
		return nil, fmt.Errorf("failed to create client: %v", err)
	}

	return &Client{
		MergeRequestsService:         client.MergeRequests,
		MergeRequestApprovalsService: client.MergeRequestApprovals,
		DiscussionsService:           client.Discussions,
		ProjectsService:              client.Projects,
		ProjectMembersService:        client.ProjectMembers,
		JobsService:                  client.Jobs,
		PipelinesService:             client.Pipelines,
		LabelsService:                client.Labels,
		AwardEmojiService:            client.AwardEmoji,
		UsersService:                 client.Users,
		DraftNotesService:            client.DraftNotes,
	}, nil
}

/* InitProjectSettings fetch the project ID using the client */
func InitProjectSettings(c *Client, gitInfo git.GitData) (*ProjectInfo, error) {

	opt := gitlab.GetProjectOptions{}
	project, _, err := c.GetProject(gitInfo.ProjectPath(), &opt)

	if err != nil {
		return nil, fmt.Errorf(fmt.Sprintf("Error getting project at %s", gitInfo.RemoteUrl), err)
	}

	if project == nil {
		return nil, fmt.Errorf(fmt.Sprintf("Could not find project at %s", gitInfo.RemoteUrl), err)
	}

	projectId := fmt.Sprint(project.ID)

	return &ProjectInfo{
		ProjectId: projectId,
	}, nil
}

/* handleError is a utililty handler that returns errors to the client along with their statuses and messages */
func handleError(w http.ResponseWriter, err error, message string, status int) {
	w.WriteHeader(status)
	response := ErrorResponse{
		Message: message,
		Details: err.Error(),
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode error response", http.StatusInternalServerError)
	}
}
