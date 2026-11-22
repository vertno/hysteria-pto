package cmd

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
	"go.uber.org/zap/zaptest/observer"

	"github.com/apernet/hysteria/core/v2/server"
)

func TestConnectionAuditOptIn(t *testing.T) {
	previous := logger
	t.Cleanup(func() { logger = previous })
	for _, level := range []zap.AtomicLevel{zap.NewAtomicLevelAt(zap.InfoLevel), zap.NewAtomicLevelAt(zap.WarnLevel)} {
		core, _ := observer.New(level)
		logger = zap.New(core)
		for _, enabled := range []bool{false, true} {
			c := serverConfig{ConnectionAudit: enabled}
			s := &server.Config{}
			require.NoError(t, c.fillEventLogger(s))
			require.Equal(t, enabled && level.Enabled(zap.InfoLevel), s.TCPConnectionLogger != nil)
			require.Nil(t, s.TrafficLogger)
		}
	}
}

func TestConnectionAuditMetadata(t *testing.T) {
	old := logger
	defer func() { logger = old }()
	core, logs := observer.New(zap.InfoLevel)
	logger = zap.New(core)
	l := &serverLogger{}
	e := server.TCPConnectionEvent{ID: "flow", OpenedAt: time.Now(), ClientAddr: "[::1]:23456", LocalAddr: "127.0.0.1:34567", RemoteAddr: "127.0.0.1:443"}
	l.LogTCPConnection(e, false, nil)
	l.LogTCPConnection(e, true, nil)
	require.Len(t, logs.All(), 2)
	for i, entry := range logs.All() {
		m := entry.ContextMap()
		require.Equal(t, "hy2-flow-v1", m["schema"])
		require.Equal(t, []string{"open", "close"}[i], m["event"])
		require.Equal(t, e.ID, m["flow_id"])
		require.Equal(t, e.ClientAddr, m["client_addr"])
		require.NotContains(t, m, "auth")
		require.NotContains(t, m, "auth_id")
		require.NotContains(t, m, "request_addr")
	}
}
