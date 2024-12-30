package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/go-playground/validator/v10"
	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type mw func(http.Handler) http.Handler

type payload string

// Wraps a series of middleware around the base handler. Functions are called from bottom to top.
// The middlewares should call the serveHTTP method on their http.Handler argument to pass along the request.
func middleware(h http.Handler, middlewares ...mw) http.HandlerFunc {
	for _, middleware := range middlewares {
		h = middleware(h)
	}
	return h.ServeHTTP
}

var validate = validator.New()

type methodToPayload map[string]func() any

// Generic factory function to create new payload instances per request
func newPayload[T any]() any {
	var p T
	return &p
}

type validatorMiddleware struct {
	validate        *validator.Validate
	methodToPayload methodToPayload
}

// Validates the fields in a payload and then attaches the validated payload to the request context so that
// subsequent handlers can use it.
func (p validatorMiddleware) handle(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		constructor, exists := p.methodToPayload[r.Method]
		if !exists { // If no payload to validate for this method type...
			next.ServeHTTP(w, r)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			handleError(w, err, "Could not read request body", http.StatusBadRequest)
			return
		}

		// Create a new instance for this request
		pl := constructor()

		err = json.Unmarshal(body, &pl)

		if err != nil {
			handleError(w, err, "Could not parse JSON request body", http.StatusBadRequest)
			return
		}

		err = p.validate.Struct(pl)
		if err != nil {
			switch err := err.(type) {
			case validator.ValidationErrors:
				handleError(w, formatValidationErrors(err), "Invalid payload", http.StatusBadRequest)
				return
			case *validator.InvalidValidationError:
				handleError(w, err, "Invalid validation error", http.StatusInternalServerError)
				return
			}
		}

		// Pass the parsed data so we don't have to re-parse it in the handler
		ctx := context.WithValue(r.Context(), payload("payload"), pl)
		r = r.WithContext(ctx)

		next.ServeHTTP(w, r)
	})
}

func withPayloadValidation(mtp methodToPayload) mw {
	return validatorMiddleware{validate: validate, methodToPayload: mtp}.handle
}

type withMrMiddleware struct {
	data   data
	client MergeRequestLister
}

// Gets the current merge request ID and attaches it to the projectInfo
func (m withMrMiddleware) handle(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// If the merge request is already attached, skip the middleware logic
		if m.data.projectInfo.MergeId == 0 {
			options := gitlab.ListProjectMergeRequestsOptions{
				Scope:        gitlab.Ptr("all"),
				SourceBranch: &m.data.gitInfo.BranchName,
			}

			if pluginOptions.ChosenMrIID != 0 {
				options.IIDs = gitlab.Ptr([]int{pluginOptions.ChosenMrIID})
			}

			mergeRequests, _, err := m.client.ListProjectMergeRequests(m.data.projectInfo.ProjectId, &options)
			if err != nil {
				handleError(w, fmt.Errorf("failed to list merge requests: %w", err), "Failed to list merge requests", http.StatusInternalServerError)
				return
			}

			if len(mergeRequests) == 0 {
				err := fmt.Errorf("branch '%s' does not have any merge requests", m.data.gitInfo.BranchName)
				handleError(w, err, "No MRs Found", http.StatusNotFound)
				return
			}

			if len(mergeRequests) > 1 {
				err := errors.New("please call gitlab.choose_merge_request()")
				handleError(w, err, "Multiple MRs found", http.StatusBadRequest)
				return
			}

			mergeIdInt := mergeRequests[0].IID
			m.data.projectInfo.MergeId = mergeIdInt
		}

		// Call the next handler if middleware succeeds
		next.ServeHTTP(w, r)
	})
}

// Att
func withMr(data data, client MergeRequestLister) mw {
	return withMrMiddleware{data, client}.handle
}

type methodMiddleware struct {
	methods []string
}

func (m methodMiddleware) handle(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method := r.Method
		for _, acceptableMethod := range m.methods {
			if method == acceptableMethod {
				next.ServeHTTP(w, r)
				return
			}
		}

		w.Header().Set("Access-Control-Allow-Methods", http.MethodPut)
		handleError(w, InvalidRequestError{fmt.Sprintf("Expected: %s", strings.Join(m.methods, "; "))}, "Invalid request type", http.StatusMethodNotAllowed)
	})
}

func withMethodCheck(methods ...string) mw {
	return methodMiddleware{methods: methods}.handle
}

// Helper function to format validation errors into more readable strings
func formatValidationErrors(errs validator.ValidationErrors) error {
	var s strings.Builder
	for i, e := range errs {
		if i > 0 {
			s.WriteString("; ")
		}
		switch e.Tag() {
		case "required":
			s.WriteString(fmt.Sprintf("%s is required", e.Field()))
		default:
			s.WriteString(fmt.Sprintf("The field '%s' failed on validation on the '%s' tag", e.Field(), e.Tag()))
		}
	}

	return errors.New(s.String())
}
