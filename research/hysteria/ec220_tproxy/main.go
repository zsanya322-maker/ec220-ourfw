package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	appTProxy "github.com/apernet/hysteria/app/v2/internal/tproxy"
	hyclient "github.com/apernet/hysteria/core/v2/client"
)

const maxURIFileBytes = 4096

type nodeConfig struct {
	server       string
	auth         string
	sni          string
	insecure     bool
	obfsType     string
	obfsPassword string
	pinSHA256    []byte
	echConfig    []byte
}

func main() {
	server := flag.String("server", "", "Hysteria2 server host:port")
	auth := flag.String("auth", "", "Hysteria2 authentication string")
	sni := flag.String("sni", "", "TLS SNI; defaults to server host")
	insecure := flag.Bool("insecure", false, "skip TLS certificate verification")
	obfsPassword := flag.String("obfs-password", "", "Salamander password (salamander build only)")
	uriFile := flag.String("uri-file", "", "read one hysteria2:// or hy2:// URI from a protected file")
	checkConfig := flag.Bool("check-config", false, "validate resolved node settings without connecting")
	listen := flag.String("listen", ":2500", "local TCP+UDP TPROXY listen address")
	udpTimeout := flag.Duration("udp-timeout", 60*time.Second, "idle UDP TPROXY flow timeout")
	disablePMTUD := flag.Bool("disable-pmtud", false, "disable QUIC path MTU discovery")
	disableChromeParrot := flag.Bool("disable-chrome-parrot", false, "disable Chrome QUIC fingerprint parroting")
	flag.Parse()

	node := nodeConfig{
		server:       *server,
		auth:         *auth,
		sni:          *sni,
		insecure:     *insecure,
		obfsPassword: *obfsPassword,
	}
	if node.obfsPassword != "" {
		node.obfsType = "salamander"
	}

	if *uriFile != "" {
		if *server != "" || *auth != "" || *sni != "" || *insecure || *obfsPassword != "" {
			fatalf("--uri-file cannot be mixed with server/auth/TLS/obfs secret flags")
		}
		var err error
		node, err = loadURIFile(*uriFile)
		if err != nil {
			fatalf("URI file: %v", err)
		}
	}
	if node.server == "" {
		fatalf("--server or --uri-file is required")
	}

	serverAddr, hostForSNI, err := resolveServer(node.server)
	if err != nil {
		fatalf("resolve server: %v", err)
	}
	if node.sni == "" && net.ParseIP(hostForSNI) == nil {
		node.sni = hostForSNI
	}

	if *checkConfig {
		fmt.Printf("CONFIG_CHECK=OK SERVER_HOST=%s SERVER_NETWORK=%s AUTH=%t SNI=%t INSECURE=%t OBFS=%s PIN_SHA256=%t ECH=%t\n",
			hostForSNI, serverAddr.Network(), node.auth != "", node.sni != "", node.insecure,
			normalizedObfsName(node.obfsType), len(node.pinSHA256) == sha256.Size, len(node.echConfig) != 0)
		return
	}

	cfg := &hyclient.Config{
		ConnFactory: newPacketConnFactory(node.obfsType, node.obfsPassword),
		ServerAddr:  serverAddr,
		Auth:        node.auth,
		TLSConfig: hyclient.TLSConfig{
			ServerName:         node.sni,
			InsecureSkipVerify: node.insecure,
			ECHConfigList:      node.echConfig,
		},
		QUICConfig: hyclient.QUICConfig{
			DisablePathMTUDiscovery: *disablePMTUD,
			DisableChromeParrot:     *disableChromeParrot,
		},
	}
	if len(node.pinSHA256) != 0 {
		expected := append([]byte(nil), node.pinSHA256...)
		cfg.TLSConfig.VerifyPeerCertificate = func(rawCerts [][]byte, _ [][]*x509.Certificate) error {
			if len(rawCerts) == 0 {
				return errors.New("server supplied no certificate")
			}
			sum := sha256.Sum256(rawCerts[0])
			if subtle.ConstantTimeCompare(sum[:], expected) != 1 {
				return errors.New("server certificate SHA256 pin mismatch")
			}
			return nil
		}
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

func loadURIFile(path string) (nodeConfig, error) {
	st, err := os.Stat(path)
	if err != nil {
		return nodeConfig{}, err
	}
	if !st.Mode().IsRegular() {
		return nodeConfig{}, errors.New("not a regular file")
	}
	if st.Size() <= 0 || st.Size() > maxURIFileBytes {
		return nodeConfig{}, errors.New("size outside accepted range")
	}
	if st.Mode().Perm()&0o077 != 0 {
		return nodeConfig{}, errors.New("secret file permissions must not allow group/other access")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nodeConfig{}, err
	}
	return parseURI(strings.TrimSpace(string(b)))
}

func parseURI(raw string) (nodeConfig, error) {
	if raw == "" || strings.ContainsAny(raw, "\r\n\x00") {
		return nodeConfig{}, errors.New("URI is empty or contains control separators")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return nodeConfig{}, err
	}
	if u.Scheme != "hysteria2" && u.Scheme != "hy2" {
		return nodeConfig{}, errors.New("unsupported URI scheme")
	}
	if u.Host == "" {
		return nodeConfig{}, errors.New("missing server host")
	}

	n := nodeConfig{server: u.Host}
	if u.User != nil {
		auth, err := url.QueryUnescape(u.User.String())
		if err != nil {
			return nodeConfig{}, errors.New("invalid escaped auth")
		}
		n.auth = auth
	}

	q := u.Query()
	n.sni = q.Get("sni")
	if v := q.Get("insecure"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return nodeConfig{}, errors.New("invalid insecure flag")
		}
		n.insecure = b
	}
	n.obfsType = strings.ToLower(strings.TrimSpace(q.Get("obfs")))
	n.obfsPassword = q.Get("obfs-password")
	switch n.obfsType {
	case "", "plain":
		n.obfsType = ""
		if n.obfsPassword != "" {
			return nodeConfig{}, errors.New("obfs-password supplied without supported obfs type")
		}
	case "salamander":
		if n.obfsPassword == "" {
			return nodeConfig{}, errors.New("salamander requires obfs-password")
		}
	default:
		return nodeConfig{}, fmt.Errorf("unsupported obfs type %q", n.obfsType)
	}

	if pin := strings.TrimSpace(q.Get("pinSHA256")); pin != "" {
		pin = strings.ReplaceAll(pin, ":", "")
		decoded, err := hex.DecodeString(pin)
		if err != nil || len(decoded) != sha256.Size {
			return nodeConfig{}, errors.New("invalid pinSHA256")
		}
		n.pinSHA256 = decoded
	}
	if ech := strings.TrimSpace(q.Get("ech")); ech != "" {
		decoded, err := base64.StdEncoding.DecodeString(ech)
		if err != nil || len(decoded) == 0 || len(decoded) > 4096 {
			return nodeConfig{}, errors.New("invalid ECH config list")
		}
		n.echConfig = decoded
	}
	return n, nil
}

func resolveServer(server string) (net.Addr, string, error) {
	host, port, err := net.SplitHostPort(server)
	if err != nil {
		// URI host without an explicit port defaults to 443. Raw IPv6 must be
		// bracketed by the URI parser, so Hostname remains safe here.
		if strings.Contains(server, ":") {
			return nil, "", errors.New("invalid host:port or unsupported port-hopping address")
		}
		host = server
		port = "443"
	}
	if host == "" {
		return nil, "", errors.New("empty host")
	}
	if strings.ContainsAny(port, ",- ") {
		return nil, "", errors.New("port hopping is not enabled in the EC220 minimal engine yet")
	}
	p, err := strconv.Atoi(port)
	if err != nil || p < 1 || p > 65535 {
		return nil, "", errors.New("invalid UDP port")
	}
	addr, err := net.ResolveUDPAddr("udp", net.JoinHostPort(strings.Trim(host, "[]"), port))
	return addr, strings.Trim(host, "[]"), err
}

func normalizedObfsName(v string) string {
	if v == "" {
		return "plain"
	}
	return v
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "ec220-hy2: "+format+"\n", args...)
	os.Exit(1)
}
