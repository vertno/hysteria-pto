package server

import (
	"net"
	"testing"

	"github.com/stretchr/testify/require"
)

type auditTestConn struct {
	net.Conn
	local, remote net.Addr
}

func (c auditTestConn) LocalAddr() net.Addr { return c.local }

func (c auditTestConn) RemoteAddr() net.Addr {
	if c.local == nil {
		panic("queried a fast-open peer before the socket existed")
	}
	return c.remote
}

func TestConnectionAuditDeferredAddresses(t *testing.T) {
	var e TCPConnectionEvent
	e.setOutboundAddrs(auditTestConn{})
	require.Empty(t, e.LocalAddr)
	require.Empty(t, e.RemoteAddr)
	conn := auditTestConn{local: &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 51234}}
	e.setOutboundAddrs(conn)
	require.Equal(t, conn.local.String(), e.LocalAddr)
	require.Empty(t, e.RemoteAddr)
	conn.remote = &net.TCPAddr{IP: net.IPv6loopback, Port: 443}
	e.setOutboundAddrs(conn)
	require.Equal(t, "[::1]:443", e.RemoteAddr)
}
