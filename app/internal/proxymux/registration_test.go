package proxymux

import (
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// Registering the first sub-listener must wake a manager already waiting with
// no registered protocols. Closing it must release the port without a client.
func TestLateRegistrationRelease(t *testing.T) {
	base, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	defer base.Close()
	deleted := make(chan struct{})
	ml := newMuxListener(base, func() { close(deleted) })
	// Allow the manager to enter its initial select before registration.
	time.Sleep(20 * time.Millisecond)
	sub, err := ml.ListenHTTP()
	require.NoError(t, err)
	require.NoError(t, sub.Close())
	select {
	case <-deleted:
	case <-time.After(time.Second):
		t.Fatal("manager did not observe the newly registered listener closing")
	}
}
