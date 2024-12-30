package app

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type JobTraceRequest struct {
	JobId int `json:"job_id" validate:"required"`
}

type JobTraceResponse struct {
	SuccessResponse
	File string `json:"file"`
}

type TraceFileGetter interface {
	GetTraceFile(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error)
}

type traceFileService struct {
	data
	client TraceFileGetter
}

/* jobHandler returns a string that shows the output of a specific job run in a Gitlab pipeline */
func (a traceFileService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	payload := r.Context().Value(payload("payload")).(*JobTraceRequest)

	reader, res, err := a.client.GetTraceFile(a.projectInfo.ProjectId, payload.JobId)

	if err != nil {
		handleError(w, err, "Could not get trace file for job", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not get trace file for job", res.StatusCode)
		return
	}

	file, err := io.ReadAll(reader)

	if err != nil {
		handleError(w, err, "Could not read job trace file", http.StatusBadRequest)
		return
	}

	response := JobTraceResponse{
		SuccessResponse: SuccessResponse{Message: "Log file read"},
		File:            string(file),
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
