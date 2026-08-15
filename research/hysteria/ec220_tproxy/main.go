package main

import (
	"flag"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	appTProxy "github.com/apernet/hysteria/app/v2/internal/tproxy"
	hyclient "github.com/apernet/hysteria/core/v2/client"
)

func main() {
	server := flag.String("server", "", "Hysteria2 server host:port")
	auth := flag.String("auth", "", "Hysteria2 authentication string")
	sni := flag.String("sni", "", "TLS SNI; defaults to server host")
	insecure := flag.Bool("insecure", false, "skip TLS certificate verification")
	obfsPassword := flag.String("obfs-password", "", "Salamander password (salamander build only)")
	listen := flag.String("listen", ":2500", "local TCP+UDP TPROXY listen address")
	udpTimeout := flag.Duration("udp-timeout", 60*time.Second, "idle UDP TPROXY flow timeout")
	disablePMTUD := flag.Bool("disable-pmtud", false, "disable QUIC path MTU discovery")
	disableChromeParrot := flag.Bool("disable-chrome-parrot", false, "disable Chrome QUIC fingerprint parroting")
	flag.Parse()

	if *server == "" {
		fatalf("--server is required")
	}

	serverAddr, err := net.ResolveUDPAddr("udp", *server)
	if err != nil {
		fatalf("resolve server: %v", err)
	}

	tlsSNI := *sni
	if tlsSNI == "" {
		host, _, splitErr := net.SplitHostPort(*server)
		if splitErr == nil && net.ParseIP(host) == nil {
			tlsSNI = strings.Trim(host, "[]")
		}
	}

	cfg := &hyclient.Config{
		ConnFactory: newPacketConnFactory(*obfsPassword),
		ServerAddr:  serverAddr,
		Auth:        *auth,
		TLSConfig: hyclient.TLSConfig{
			ServerName:         tlsSNI,
			InsecureSkipVerify: *insecure,
		},
		QUICConfig: hyclient.QUICConfig{
			DisablePathMTUDiscovery: *disablePMTUD,
			DisableChromeParrot:     *disableChromeParrot,
		},
	}

	hy, info, err := hyclient.NewClient(cfg)
	if err != nil {
		fatalf("connect: %v", err)
	}
	defer hy.Close()

	tcpAddr, err := net.ResolveTCPAddr("tcp", *listen)
	if err != nil {
		fatalf("resolve TCP TPROXY listen address: %v", err)
	}
	udpAddr, err := net.ResolveUDPAddr("udp", *listen)
	if err != nil {
		fatalf("resolve UDP TPROXY listen address: %v", err)
	}

	fmt.Fprintf(os.Stderr, "EC220 HY2 connected server=%s udp=%t tproxy=%s\n", info.ServerAddr, info.UDPEnabled, *listen)

	errCh := make(chan error, 2)
	go func() {
		errCh <- (&appTProxy.TCPTProxy{HyClient: hy}).ListenAndServe(tcpAddr)
	}()
	go func() {
		errCh <- (&appTProxy.UDPTProxy{HyClient: hy, Timeout: *udpTimeout}).ListenAndServe(udpAddr)
	}()

	fatalf("TPROXY stopped: %v", <-errCh)
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "ec220-hy2: "+format+"\n", args...)
	os.Exit(1)
}
