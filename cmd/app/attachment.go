package app

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type FileReader interface {
	ReadFile(path string) (io.Reader, error)
}

type AttachmentRequest struct {
	FilePath string `json:"file_path" validate:"required"`
	FileName string `json:"file_name" validate:"required"`
}

type AttachmentResponse struct {
	SuccessResponse
	Markdown string `json:"markdown"`
	Alt      string `json:"alt"`
	Url      string `json:"url"`
}

type attachmentReader struct{}

func (ar attachmentReader) ReadFile(path string) (io.Reader, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}

	data, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}

	defer file.Close()

	reader := bytes.NewReader(data)

	return reader, nil
}

type FileUploader interface {
	UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error)
}

type attachmentService struct {
	data
	fileReader FileReader
	client     FileUploader
}

/* attachmentHandler uploads an attachment (file, image, etc) to Gitlab and returns metadata about the upload. */
func (a attachmentService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*AttachmentRequest)

	file, err := a.fileReader.ReadFile(payload.FilePath)
	if err != nil || file == nil {
		handleError(w, err, fmt.Sprintf("Could not read %s file", payload.FileName), http.StatusInternalServerError)
		return
	}

	projectFile, res, err := a.client.UploadFile(a.projectInfo.ProjectId, file, payload.FileName)
	if err != nil {
		handleError(w, err, fmt.Sprintf("Could not upload %s to Gitlab", payload.FileName), http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, fmt.Sprintf("Could not upload %s to Gitlab", payload.FileName), res.StatusCode)
		return
	}

	response := AttachmentResponse{
		SuccessResponse: SuccessResponse{Message: "File uploaded successfully"},
		Markdown:        projectFile.Markdown,
		Alt:             projectFile.Alt,
		Url:             projectFile.URL,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
