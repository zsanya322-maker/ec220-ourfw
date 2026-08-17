//go:build salamander

package main

import (
	"errors"
	"net"
	"strings"

	hyclient "github.com/apernet/hysteria/core/v2/client"
	"github.com/apernet/hysteria/extras/v2/obfs"
)

type packetConnFactory struct {
	obfsType string
	password string
}

func newPacketConnFactory(obfsType, password string) hyclient.ConnFactory {
	return &packetConnFactory{obfsType: strings.ToLower(strings.TrimSpace(obfsType)), password: password}
}

func (f *packetConnFactory) New(_ net.Addr) (net.PacketConn, error) {
	conn, err := net.ListenUDP("udp", nil)
	if err != nil {
		return nil, err
	}
	switch f.obfsType {
	case "", "plain":
		if f.password != "" {
			_ = conn.Close()
			return nil, errors.New("obfs password supplied for plain transport")
		}
		return conn, nil
	case "salamander":
		if f.password == "" {
			_ = conn.Close()
			return nil, errors.New("Salamander requires a password")
		}
		wrapped, err := obfs.WrapPacketConnSalamander(conn, []byte(f.password))
		if err != nil {
			_ = conn.Close()
			return nil, err
		}
		return wrapped, nil
	default:
		_ = conn.Close()
		return nil, errors.New("unsupported obfs type")
	}
}
