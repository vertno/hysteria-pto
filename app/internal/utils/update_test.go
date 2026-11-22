package utils

import (
	"io"
	"net/http"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

type releaseTransport func(*http.Request) (*http.Response, error)

func (f releaseTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestPatchedUpdateFeed(t *testing.T) {
	for _, tc := range []struct {
		current, latest string
		update, invalid bool
	}{
		{"v2.9.0-patched", "v2.14.0-patched", true, false},
		{"v2.14.0-patched", "v2.14.0-patched", false, false},
		{"v2.15.0-patched", "v2.14.0-patched", false, false},
		{"v2.14.0-patched", "", false, true},
	} {
		checker := NewServerUpdateChecker(tc.current, "linux", "amd64", "release")
		checker.Client.Transport = releaseTransport(func(r *http.Request) (*http.Response, error) {
			require.Equal(t, updateCheckEndpoint, r.URL.String())
			body := io.NopCloser(strings.NewReader(`{"lver":"` + tc.latest + `","url":"https://example.com/release","urgent":true}`))
			return &http.Response{StatusCode: 200, Body: body}, nil
		})
		resp, err := checker.Check()
		if tc.invalid {
			require.Error(t, err)
			continue
		}
		require.NoError(t, err)
		require.Equal(t, tc.update, resp.HasUpdate)
		require.Equal(t, "https://example.com/release", resp.URL)
		require.True(t, resp.Urgent)
	}
}
