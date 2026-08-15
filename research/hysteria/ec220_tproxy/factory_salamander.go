//go:build salamander

package main

import (
	"net"

	hyclient "github.com/apernet/hysteria/core/v2/client"
	"github.com/apernet/hysteria/extras/v2/obfs"
)

type packetConnFactory struct {
	password string
}

func newPacketConnFactory(password string) hyclient.ConnFactory {
	return &packetConnFactory{password: password}
}

func (f *packetConnFactory) New(_ net.Addr) (net.PacketConn, error) {
	conn, err := net.ListenUDP("udp", nil)
	if err != nil {
		return nil, err
	}
	if f.password == "" {
		return conn, nil
	}
	wrapped, err := obfs.WrapPacketConnSalamander(conn, []byte(f.password))
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	return wrapped, nil
}
