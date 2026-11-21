package integration_tests

import (
	"bytes"
	"io"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/apernet/hysteria/core/v2/client"
	"github.com/apernet/hysteria/core/v2/internal/integration_tests/mocks"
	"github.com/apernet/hysteria/core/v2/server"
)

type connectionAuditEntry struct {
	event  server.TCPConnectionEvent
	closed bool
}

type connectionAuditRecorder chan connectionAuditEntry

func (r connectionAuditRecorder) LogTCPConnection(e server.TCPConnectionEvent, closed bool, _ error) {
	r <- connectionAuditEntry{e, closed}
}

func TestClientServerConnectionAudit(t *testing.T) {
	for _, addr := range []string{"127.0.0.1:0", "[::1]:0"} {
		t.Run(addr, func(t *testing.T) {
			u, err := net.ListenPacket("udp", addr)
			require.NoError(t, err)
			auth := mocks.NewMockAuthenticator(t)
			auth.EXPECT().Authenticate(mock.Anything, mock.Anything, mock.Anything).Return(true, "private-user-id")
			recorder := make(connectionAuditRecorder, 2)
			s, err := server.NewServer(&server.Config{TLSConfig: serverTLSConfig(), Conn: u, Authenticator: auth, TCPConnectionLogger: recorder})
			require.NoError(t, err)
			defer s.Close()
			go s.Serve()
			listener, err := net.Listen("tcp", addr)
			require.NoError(t, err)
			defer listener.Close()
			peer := make(chan string, 1)
			go func() {
				conn, err := listener.Accept()
				if err != nil {
					return
				}
				defer conn.Close()
				_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
				peer <- conn.RemoteAddr().String()
				_, _ = io.Copy(conn, conn)
			}()
			c, _, err := client.NewClient(&client.Config{ServerAddr: u.LocalAddr(), TLSConfig: client.TLSConfig{InsecureSkipVerify: true}})
			require.NoError(t, err)
			defer c.Close()
			conn, err := c.TCP(listener.Addr().String())
			require.NoError(t, err)
			defer conn.Close()
			_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
			body := bytes.Repeat([]byte("audit-fast-path"), 1024)
			_, err = conn.Write(body)
			require.NoError(t, err)
			actual := make([]byte, len(body))
			_, err = io.ReadFull(conn, actual)
			require.NoError(t, err)
			require.Equal(t, body, actual)
			var opened connectionAuditEntry
			select {
			case opened = <-recorder:
			case <-time.After(5 * time.Second):
				t.Fatal("no open event")
			}
			require.False(t, opened.closed)
			require.NotEmpty(t, opened.event.ID)
			require.Equal(t, listener.Addr().String(), opened.event.RemoteAddr)
			require.Equal(t, u.LocalAddr().String(), opened.event.QUICLocalAddr)
			clientAddr, err := net.ResolveUDPAddr("udp", opened.event.ClientAddr)
			require.NoError(t, err)
			require.True(t, clientAddr.IP.IsLoopback())
			require.Positive(t, clientAddr.Port)
			select {
			case actualPeer := <-peer:
				require.Equal(t, actualPeer, opened.event.LocalAddr)
			case <-time.After(5 * time.Second):
				t.Fatal("no accepted socket")
			}
			require.NoError(t, conn.Close())
			select {
			case closed := <-recorder:
				require.True(t, closed.closed)
				require.Equal(t, opened.event, closed.event)
			case <-time.After(5 * time.Second):
				t.Fatal("no close event")
			}
		})
	}
}
