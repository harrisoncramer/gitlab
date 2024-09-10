package app

import (
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
	"github.com/hashicorp/go-retryablehttp"
	"github.com/xanzy/go-gitlab"
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
func NewClient() (error, *Client) {

	if pluginOptions.GitlabUrl == "" {
		return errors.New("GitLab instance URL cannot be empty"), nil
	}

	var apiCustUrl = fmt.Sprintf(pluginOptions.GitlabUrl + "/api/v4")

	gitlabOptions := []gitlab.ClientOptionFunc{
		gitlab.WithBaseURL(apiCustUrl),
	}

	if pluginOptions.Debug.GitlabRequest {
		gitlabOptions = append(gitlabOptions, gitlab.WithRequestLogHook(
			func(l retryablehttp.Logger, r *http.Request, i int) {
				logRequest(r)
			},
		))
	}

	if pluginOptions.Debug.GitlabResponse {
		gitlabOptions = append(gitlabOptions, gitlab.WithResponseLogHook(func(l retryablehttp.Logger, response *http.Response) {
			logResponse(response)
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
	gitlabOptions = append(gitlabOptions, gitlab.WithHTTPClient(retryClient.HTTPClient))

	client, err := gitlab.NewClient(pluginOptions.AuthToken, gitlabOptions...)

	if err != nil {
		return fmt.Errorf("Failed to create client: %v", err), nil
	}

	return nil, &Client{
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
	}
}

/* InitProjectSettings fetch the project ID using the client */
func InitProjectSettings(c *Client, gitInfo git.GitData) (error, *ProjectInfo) {

	opt := gitlab.GetProjectOptions{}
	project, _, err := c.GetProject(gitInfo.ProjectPath(), &opt)

	if err != nil {
		return fmt.Errorf(fmt.Sprintf("Error getting project at %s", gitInfo.RemoteUrl), err), nil
	}

	if project == nil {
		return fmt.Errorf(fmt.Sprintf("Could not find project at %s", gitInfo.RemoteUrl), err), nil
	}

	projectId := fmt.Sprint(project.ID)

	return nil, &ProjectInfo{
		ProjectId: projectId,
	}

}

/* handleError is a utililty handler that returns errors to the client along with their statuses and messages */
func handleError(w http.ResponseWriter, err error, message string, status int) {
	w.WriteHeader(status)
	response := ErrorResponse{
		Message: message,
		Details: err.Error(),
		Status:  status,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode error response", http.StatusInternalServerError)
	}
}

func openLogFile() *os.File {
	file, err := os.OpenFile(pluginOptions.LogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Log file %s does not exist", pluginOptions.LogPath)
		} else if os.IsPermission(err) {
			log.Printf("Permission denied for log file %s", pluginOptions.LogPath)
		} else {
			log.Printf("Error opening log file %s: %v", pluginOptions.LogPath, err)
		}

		os.Exit(1)
	}

	return file
}
