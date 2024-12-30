package app

import (
	"crypto/sha1"
	"fmt"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

/* LinePosition represents a position in a line range. Unlike the Gitlab struct, this does not contain LineCode with a sha1 of the filename */
type LinePosition struct {
	Type    string `json:"type"`
	OldLine int    `json:"old_line"`
	NewLine int    `json:"new_line"`
}

/* LineRange represents the range of a note. */
type LineRange struct {
	StartRange *LinePosition `json:"start"`
	EndRange   *LinePosition `json:"end"`
}

/* PositionData represents the position of a comment or note (relative to a file diff) */
type PositionData struct {
	FileName       string     `json:"file_name"`
	OldFileName    string     `json:"old_file_name"`
	NewLine        *int       `json:"new_line,omitempty"`
	OldLine        *int       `json:"old_line,omitempty"`
	HeadCommitSHA  string     `json:"head_commit_sha"`
	BaseCommitSHA  string     `json:"base_commit_sha"`
	StartCommitSHA string     `json:"start_commit_sha"`
	Type           string     `json:"type"`
	LineRange      *LineRange `json:"line_range,omitempty"`
}

/* RequestWithPosition is an interface that abstracts the handling of position data for a comment or a draft comment */
type RequestWithPosition interface {
	GetPositionData() PositionData
}

/* buildCommentPosition takes a comment or draft comment request and builds the position data necessary for a location-based comment */
func buildCommentPosition(commentWithPositionData RequestWithPosition) *gitlab.PositionOptions {
	positionData := commentWithPositionData.GetPositionData()

	// If the file has been renamed, then this is a relevant part of the payload
	oldFileName := positionData.OldFileName
	if oldFileName == "" {
		oldFileName = positionData.FileName
	}

	opt := &gitlab.PositionOptions{
		PositionType: &positionData.Type,
		StartSHA:     &positionData.StartCommitSHA,
		HeadSHA:      &positionData.HeadCommitSHA,
		BaseSHA:      &positionData.BaseCommitSHA,
		NewPath:      &positionData.FileName,
		OldPath:      &oldFileName,
		NewLine:      positionData.NewLine,
		OldLine:      positionData.OldLine,
	}

	if positionData.LineRange != nil {
		shaFormat := "%x_%d_%d"
		startFilenameSha := fmt.Sprintf(
			shaFormat,
			sha1.Sum([]byte(positionData.FileName)),
			positionData.LineRange.StartRange.OldLine,
			positionData.LineRange.StartRange.NewLine,
		)
		endFilenameSha := fmt.Sprintf(
			shaFormat,
			sha1.Sum([]byte(positionData.FileName)),
			positionData.LineRange.EndRange.OldLine,
			positionData.LineRange.EndRange.NewLine,
		)
		opt.LineRange = &gitlab.LineRangeOptions{
			Start: &gitlab.LinePositionOptions{
				Type:     &positionData.LineRange.StartRange.Type,
				LineCode: &startFilenameSha,
			},
			End: &gitlab.LinePositionOptions{
				Type:     &positionData.LineRange.EndRange.Type,
				LineCode: &endFilenameSha,
			},
		}
	}

	return opt
}
