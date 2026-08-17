//go:build !salamander

package main

import (
	"errors"
	"net"
	"strings"

	hyclient "github.com/apernet/hysteria/core/v2/client"
)

type packetConnFactory struct {
	obfsType string
	password string
}

func newPacketConnFactory(obfsType, password string) hyclient.ConnFactory {
	return &packetConnFactory{obfsType: strings.ToLower(strings.TrimSpace(obfsType)), password: password}
}

func (f *packetConnFactory) New(_ net.Addr) (net.PacketConn, error) {
	switch f.obfsType {
	case "", "plain":
		if f.password != "" {
			return nil, errors.New("obfs password supplied for plain transport")
		}
		return net.ListenUDP("udp", nil)
	case "salamander":
		return nil, errors.New("this binary was built without Salamander support")
	default:
		return nil, errors.New("unsupported obfs type")
	}
}
