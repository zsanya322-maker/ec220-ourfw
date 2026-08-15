//go:build !salamander

package main

import (
	"errors"
	"net"

	hyclient "github.com/apernet/hysteria/core/v2/client"
)

type packetConnFactory struct {
	password string
}

func newPacketConnFactory(password string) hyclient.ConnFactory {
	return &packetConnFactory{password: password}
}

func (f *packetConnFactory) New(_ net.Addr) (net.PacketConn, error) {
	if f.password != "" {
		return nil, errors.New("this binary was built without Salamander support")
	}
	return net.ListenUDP("udp", nil)
}
