// Package raycore bundles Xray-core (via libXray) and sing-box into one Go
// runtime so the iOS app can use either core from a single framework.
// Xray handles VLESS/VMess/Trojan/Shadowsocks/Hysteria2/WireGuard; sing-box
// covers SSH and TUIC.
package raycore

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"
	libxray "github.com/xtls/libxray"
)

// XrayInvoke forwards to libXray's JSON API (kept for callers that only see this package).
func XrayInvoke(requestJSON string) string { return libxray.Invoke(requestJSON) }

// SetEnv sets a process environment variable from within the Go runtime
// itself. On Android, android.system.Os.setenv() (called from Kotlin) only
// updates the JVM/libc-visible environ; the Go runtime embedded in this
// gomobile .so has already snapshotted its own environment by the time that
// JNI call would run, so xray-core's XRAY_LOCATION_ASSET lookup (used to
// find geoip.dat/geosite.dat) never sees it. Calling os.Setenv here, before
// starting Xray, updates the same environment table xray-core reads from.
func SetEnv(key string, value string) { os.Setenv(key, value) }

var (
	sbMu       sync.Mutex
	sbInstance *box.Box
	sbCancel   context.CancelFunc
)

func newContext() context.Context {
	ctx := context.Background()
	// DNSTT is ours, not sing-box's, so it is registered onto the stock
	// outbound registry rather than shipped by a forked core.
	outbounds := include.OutboundRegistry()
	registerDnstt(outbounds)
	ctx = box.Context(ctx, include.InboundRegistry(), outbounds, include.EndpointRegistry(), include.DNSTransportRegistry(), include.ServiceRegistry(), include.CertificateProviderRegistry())
	return ctx
}

func parseOptions(ctx context.Context, configJSON string) (option.Options, error) {
	var options option.Options
	if err := options.UnmarshalJSONContext(ctx, []byte(configJSON)); err != nil {
		return options, err
	}
	return options, nil
}

// SingboxStart starts a sing-box instance from a full JSON configuration.
func SingboxStart(configJSON string) error {
	sbMu.Lock()
	defer sbMu.Unlock()
	if sbInstance != nil {
		return errors.New("sing-box is already running")
	}
	// Same memory discipline libXray applies on iOS: the tunnel extension has ~50 MB.
	debug.SetGCPercent(10)
	debug.SetMemoryLimit(40 * 1024 * 1024)

	ctx, cancel := context.WithCancel(newContext())
	options, err := parseOptions(ctx, configJSON)
	if err != nil {
		cancel()
		return err
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		cancel()
		return err
	}
	if err := instance.Start(); err != nil {
		_ = instance.Close()
		cancel()
		return err
	}
	sbInstance = instance
	sbCancel = cancel
	debug.FreeOSMemory()
	return nil
}

// SingboxStop stops the running sing-box instance, if any.
func SingboxStop() error {
	sbMu.Lock()
	defer sbMu.Unlock()
	if sbInstance == nil {
		return nil
	}
	err := sbInstance.Close()
	sbCancel()
	sbInstance = nil
	sbCancel = nil
	debug.FreeOSMemory()
	return err
}

// SingboxRunning reports whether a sing-box instance is active.
func SingboxRunning() bool {
	sbMu.Lock()
	defer sbMu.Unlock()
	return sbInstance != nil
}

// SingboxVersion returns the embedded sing-box version.
func SingboxVersion() string {
	return C.Version
}

// SingboxTest validates a full configuration without starting it.
func SingboxTest(configJSON string) error {
	ctx, cancel := context.WithCancel(newContext())
	defer cancel()
	options, err := parseOptions(ctx, configJSON)
	if err != nil {
		return err
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return err
	}
	return instance.Close()
}

// SingboxPing measures an HTTP round trip through a single outbound (JSON of one
// outbound object). Returns the delay in milliseconds, or an error.
func SingboxPing(outboundJSON string, url string, timeoutMs int) (int64, error) {
	if timeoutMs <= 0 {
		timeoutMs = 8000
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(outboundJSON), &raw); err != nil {
		return 0, err
	}
	raw["tag"] = json.RawMessage(`"probe"`)
	outbound, _ := json.Marshal(raw)
	configJSON := fmt.Sprintf(`{"log":{"level":"error"},"outbounds":[%s]}`, string(outbound))

	ctx, cancel := context.WithTimeout(newContext(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()
	options, err := parseOptions(ctx, configJSON)
	if err != nil {
		return 0, err
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return 0, err
	}
	if err := instance.Start(); err != nil {
		_ = instance.Close()
		return 0, err
	}
	defer instance.Close()

	manager := service.FromContext[adapter.OutboundManager](ctx)
	if manager == nil {
		return 0, errors.New("outbound manager unavailable")
	}
	out, found := manager.Outbound("probe")
	if !found {
		return 0, errors.New("probe outbound not found")
	}
	dialer, ok := out.(N.Dialer)
	if !ok {
		return 0, errors.New("outbound cannot dial")
	}
	client := &http.Client{
		Timeout: time.Duration(timeoutMs) * time.Millisecond,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return dialer.DialContext(ctx, network, M.ParseSocksaddr(addr))
			},
			DisableKeepAlives: true,
		},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	if url == "" {
		url = "https://www.google.com/generate_204"
	}
	start := time.Now()
	resp, err := client.Get(url)
	if err != nil {
		return 0, err
	}
	resp.Body.Close()
	if resp.StatusCode >= 500 {
		return 0, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return time.Since(start).Milliseconds(), nil
}

// SingboxSupports reports whether an outbound type is available in this build.
func SingboxSupports(outboundType string) bool {
	switch strings.ToLower(outboundType) {
	// WireGuard and naive need build tags this AAR/xcframework does not set,
	// so they belong to Xray-core here, not to sing-box.
	case "ssh", "tuic", "hysteria2", "hysteria", "vless", "vmess", "trojan", "shadowsocks", "socks", "http", "anytls", "shadowtls":
		return true
	}
	return false
}
