package app

import (
	"encoding/json"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type UserResponse struct {
	SuccessResponse
	User *gitlab.User `json:"user"`
}

type MeGetter interface {
	CurrentUser(options ...gitlab.RequestOptionFunc) (*gitlab.User, *gitlab.Response, error)
}

type meService struct {
	data
	client MeGetter
}

func (a meService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	user, res, err := a.client.CurrentUser()

	if err != nil {
		handleError(w, err, "Failed to get current user", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, err, "User API returned non-200 status", res.StatusCode)
		return
	}

	response := UserResponse{
		SuccessResponse: SuccessResponse{Message: "User fetched successfully"},
		User:            user,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
