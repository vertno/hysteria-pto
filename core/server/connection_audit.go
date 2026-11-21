package server

import "time"

// TCPConnectionEvent links an authenticated QUIC stream to the socket opened by
// its outbound. It deliberately contains no auth ID, request address or payload.
// ClientAddr is the address at outbound establishment, not a migration history.
type TCPConnectionEvent struct {
	ID            string
	OpenedAt      time.Time
	ClientAddr    string
	QUICLocalAddr string
	LocalAddr     string
	RemoteAddr    string
	QUICID        uint32
	StreamID      int64
}

// TCPConnectionLogger receives one open and one close event per successful TCP
// dial. Implementations must be safe for concurrent calls and should not block.
// This optional logger leaves the fast copy path and TrafficLogger unchanged.
type TCPConnectionLogger interface {
	LogTCPConnection(event TCPConnectionEvent, closed bool, err error)
}
