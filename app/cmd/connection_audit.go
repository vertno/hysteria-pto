package cmd

import (
	"time"

	"go.uber.org/zap"

	"github.com/apernet/hysteria/core/v2/server"
)

type tcpConnectionLogger struct{}

func (*tcpConnectionLogger) LogTCPConnection(e server.TCPConnectionEvent, closed bool, err error) {
	event := "open"
	duration := int64(0)
	if closed {
		event = "close"
		duration = time.Since(e.OpenedAt).Milliseconds()
	}
	logger.Info("TCP connection audit",
		zap.String("schema", "hy2-flow-v1"), zap.String("event", event),
		zap.String("flow_id", e.ID), zap.String("opened_at", e.OpenedAt.UTC().Format(time.RFC3339Nano)),
		zap.String("client_addr", e.ClientAddr), zap.String("quic_local_addr", e.QUICLocalAddr),
		zap.String("local_addr", e.LocalAddr), zap.String("remote_addr", e.RemoteAddr),
		zap.Uint32("quic_id", e.QUICID), zap.Int64("stream_id", e.StreamID),
		zap.Int64("duration_ms", duration), zap.Bool("copy_ended_with_error", err != nil))
}
