package utils

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"time"

	"golang.org/x/mod/semver"

	"github.com/apernet/hysteria/core/v2/client"
)

const (
	updateCheckEndpoint = "https://github.com/vertno/hysteria-pto/releases/latest/download/update.json"
	updateCheckTimeout  = 10 * time.Second
)

type UpdateChecker struct {
	CurrentVersion string
	Platform       string
	Architecture   string
	Channel        string
	Side           string
	Client         *http.Client
}

func NewServerUpdateChecker(currentVersion, platform, architecture, channel string) *UpdateChecker {
	return &UpdateChecker{
		CurrentVersion: currentVersion,
		Platform:       platform,
		Architecture:   architecture,
		Channel:        channel,
		Side:           "server",
		Client: &http.Client{
			Timeout: updateCheckTimeout,
		},
	}
}

// NewClientUpdateChecker ensures that update checks are routed through a HyClient,
// not being sent directly. This safeguard is CRITICAL, especially in scenarios where
// users use Hysteria to bypass censorship. Making direct HTTPS requests to the API
// endpoint could be easily spotted by censors (through SNI, for example), and could
// serve as a signal to identify and penalize Hysteria users.
func NewClientUpdateChecker(currentVersion, platform, architecture, channel string, hyClient client.Client) *UpdateChecker {
	return &UpdateChecker{
		CurrentVersion: currentVersion,
		Platform:       platform,
		Architecture:   architecture,
		Channel:        channel,
		Side:           "client",
		Client: &http.Client{
			Timeout: updateCheckTimeout,
			Transport: &http.Transport{
				DialContext: func(_ context.Context, network, addr string) (net.Conn, error) {
					// Unfortunately HyClient doesn't support context for now
					return hyClient.TCP(addr)
				},
			},
		},
	}
}

type UpdateResponse struct {
	HasUpdate     bool   `json:"update"`
	LatestVersion string `json:"lver"`
	URL           string `json:"url"`
	Urgent        bool   `json:"urgent"`
}

func (uc *UpdateChecker) Check() (*UpdateResponse, error) {
	resp, err := uc.Client.Get(updateCheckEndpoint)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}
	var uResp UpdateResponse
	decoder := json.NewDecoder(resp.Body)
	if err := decoder.Decode(&uResp); err != nil {
		return nil, err
	}
	if !semver.IsValid(uResp.LatestVersion) {
		return nil, fmt.Errorf("invalid update version %q", uResp.LatestVersion)
	}
	uResp.HasUpdate = semver.IsValid(uc.CurrentVersion) && semver.Compare(uc.CurrentVersion, uResp.LatestVersion) < 0
	return &uResp, nil
}
