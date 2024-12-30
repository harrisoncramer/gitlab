package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type ProjectMembersResponse struct {
	SuccessResponse
	ProjectMembers []*gitlab.ProjectMember
}

type ProjectMemberLister interface {
	ListAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error)
}

type projectMemberService struct {
	data
	client ProjectMemberLister
}

/* projectMembersHandler returns all members of the current Gitlab project */
func (a projectMemberService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	projectMemberOptions := gitlab.ListProjectMembersOptions{
		ListOptions: gitlab.ListOptions{
			PerPage: 100,
		},
	}

	projectMembers, res, err := a.client.ListAllProjectMembers(a.projectInfo.ProjectId, &projectMemberOptions)

	if err != nil {
		handleError(w, err, "Could not retrieve project members", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not retrieve project members", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := ProjectMembersResponse{
		SuccessResponse: SuccessResponse{Message: "Project members retrieved"},
		ProjectMembers:  projectMembers,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
