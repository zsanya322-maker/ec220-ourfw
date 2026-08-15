// hy2-ec220 is an isolated size/resource prototype. It is NOT shipped in OURFW.
// The lab copies this file under the upstream Hysteria app module so it may use
// Hysteria's internal Linux TPROXY package without importing the monolithic cmd.
package main

import (
	"crypto/x509"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/apernet/hysteria/app/v2/internal/tproxy"
	"github.com/apernet/hysteria/core/v2/client"
	"github.com/apernet/hysteria/extras/v2/obfs"
)

var buildVersion = "lab"

type salamanderFactory struct {
	password string
}

func (f *salamanderFactory) New(_ net.Addr) (net.PacketConn, error) {
	conn, err := net.ListenUDP("udp", nil)
	if err != nil {
		return nil, err
	}
	wrapped, err := obfs.WrapPacketConnSalamander(conn, []byte(f.password))
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	return wrapped, nil
}

func splitServer(s string) (host, hostPort string, err error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", "", errors.New("server is required")
	}
	if h, p, e := net.SplitHostPort(s); e == nil {
		if h == "" || p == "" {
			return "", "", errors.New("invalid server")
		}
		return h, s, nil
	}
	// A bare IPv6 literal contains multiple colons and needs brackets.
	if ip := net.ParseIP(s); ip != nil && strings.Contains(s, ":") {
		return s, net.JoinHostPort(s, "443"), nil
	}
	if strings.Contains(s, ":") {
		return "", "", errors.New("invalid server host:port")
	}
	return s, net.JoinHostPort(s, "443"), nil
}

func loadRoots(path string) (*x509.CertPool, error) {
	if path == "" {
		return nil, nil
	}
	pem, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pem) {
		return nil, errors.New("CA file contains no usable certificates")
	}
	return pool, nil
}

func main() {
	server := flag.String("server", "", "Hysteria2 server host[:port]")
	auth := flag.String("auth", "", "Hysteria2 authentication string")
	sni := flag.String("sni", "", "TLS SNI; defaults to server hostname")
	insecure := flag.Bool("insecure", false, "skip TLS certificate verification")
	caFile := flag.String("ca", "/etc/ssl/cert.pem", "PEM CA bundle; empty uses Go defaults")
	obfsPassword := flag.String("obfs-password", "", "Salamander obfuscation password")
	tcpListen := flag.String("tcp-tproxy", "0.0.0.0:25080", "TCP TPROXY listen address; empty disables TCP")
	udpListen := flag.String("udp-tproxy", "0.0.0.0:25080", "UDP TPROXY listen address; empty disables UDP")
	streamWindow := flag.Uint64("stream-window", 512*1024, "QUIC stream receive window bytes")
	connWindow := flag.Uint64("conn-window", 2*1024*1024, "QUIC connection receive window bytes")
	version := flag.Bool("version", false, "print lab build version")
	flag.Parse()

	if *version {
		fmt.Println(buildVersion)
		return
	}

	host, hostPort, err := splitServer(*server)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	if *sni == "" {
		*sni = host
	}
	roots, err := loadRoots(*caFile)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ca:", err)
		os.Exit(2)
	}
	if *tcpListen == "" && *udpListen == "" {
		fmt.Fprintln(os.Stderr, "config: at least one TPROXY listener is required")
		os.Exit(2)
	}

	configFunc := func() (*client.Config, error) {
		addr, err := net.ResolveUDPAddr("udp", hostPort)
		if err != nil {
			return nil, err
		}
		cfg := &client.Config{
			ServerAddr: addr,
			Auth:       *auth,
			TLSConfig: client.TLSConfig{
				ServerName:         *sni,
				InsecureSkipVerify: *insecure,
				RootCAs:            roots,
			},
			QUICConfig: client.QUICConfig{
				InitialStreamReceiveWindow:     *streamWindow,
				MaxStreamReceiveWindow:         *streamWindow,
				InitialConnectionReceiveWindow: *connWindow,
				MaxConnectionReceiveWindow:     *connWindow,
				MaxIdleTimeout:                 30 * time.Second,
				KeepAlivePeriod:                10 * time.Second,
				DisablePathMTUDiscovery:        true,
			},
		}
		if *obfsPassword != "" {
			cfg.ConnFactory = &salamanderFactory{password: *obfsPassword}
		}
		return cfg, nil
	}

	hy, err := client.NewReconnectableClient(configFunc, nil, false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "connect:", err)
		os.Exit(3)
	}
	defer hy.Close()

	errCh := make(chan error, 2)
	listeners := 0
	if *tcpListen != "" {
		addr, err := net.ResolveTCPAddr("tcp", *tcpListen)
		if err != nil {
			fmt.Fprintln(os.Stderr, "tcp-tproxy:", err)
			os.Exit(2)
		}
		listeners++
		go func() {
			errCh <- (&tproxy.TCPTProxy{HyClient: hy}).ListenAndServe(addr)
		}()
	}
	if *udpListen != "" {
		addr, err := net.ResolveUDPAddr("udp", *udpListen)
		if err != nil {
			fmt.Fprintln(os.Stderr, "udp-tproxy:", err)
			os.Exit(2)
		}
		listeners++
		go func() {
			errCh <- (&tproxy.UDPTProxy{HyClient: hy, Timeout: 60 * time.Second}).ListenAndServe(addr)
		}()
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(sigCh)

	for listeners > 0 {
		select {
		case sig := <-sigCh:
			fmt.Fprintln(os.Stderr, "signal:", sig)
			return
		case err := <-errCh:
			listeners--
			if err != nil {
				fmt.Fprintln(os.Stderr, "tproxy:", err)
				os.Exit(4)
			}
		}
	}
}
