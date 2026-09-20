package raycore

import (
	"context"
	"errors"
	"net"
	"strings"
	"sync"
	"sync/atomic"

	vaydns "github.com/net2share/vaydns/client"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/protocol/socks"
	"github.com/sagernet/sing/protocol/socks/socks5"
)

// DNSTT carries traffic inside ordinary DNS queries: the last road out of a
// network where every other protocol is cut, at a few megabits at best. This
// outbound drives the vaydns client (public domain, a descendant of David
// Fifield's dnstt) and speaks SOCKS5 to whatever the tunnel server forwards
// to, so a `dnstt` outbound is a complete proxy on its own with nothing to
// chain in front of it.
//
// The option names follow Hiddify's so a config or link written for their
// app can be pasted straight in.
const TypeDNSTT = "dnstt"

type DnsttOptions struct {
	option.DialerOptions
	PublicKey string `json:"pubkey,omitempty"`
	Domain    string `json:"domain,omitempty"`
	// "8.8.8.8:53" for plain DNS, "https://…/dns-query" for DoH,
	// "tls://host:853" for DoT. Several are raced and the ones that
	// answer are kept.
	Resolvers          []string `json:"resolvers,omitempty"`
	TunnelsPerResolver int      `json:"tunnel-per-resolver,omitempty"`
	DnsttCompat        bool     `json:"dnstt-compat,omitempty"`
	RecordType         string   `json:"record-type,omitempty"`
	// The server's upstream is taken to be a SOCKS5 proxy unless this says
	// "raw", in which case each stream is handed over untouched — which is
	// what an SSH or plain upstream wants.
	Upstream string `json:"upstream,omitempty"`
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
}

func registerDnstt(registry *outbound.Registry) {
	outbound.Register[DnsttOptions](registry, TypeDNSTT, newDnsttOutbound)
}

// One resolver's attempt at a tunnel.
type dnsttAttempt struct {
	tunnel *vaydns.Tunnel
	err    error
}

type dnsttOutbound struct {
	outbound.Adapter
	logger  log.ContextLogger
	options DnsttOptions
	server  vaydns.TunnelServer

	// Held for the length of a build so concurrent dials do not each race
	// their own set of tunnels.
	startMu sync.Mutex
	mu      sync.Mutex
	tunnels []*vaydns.Tunnel
	next    atomic.Uint32
	closed  bool
}

func newDnsttOutbound(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options DnsttOptions) (adapter.Outbound, error) {
	if options.PublicKey == "" {
		return nil, E.New("dnstt: public key is required")
	}
	if options.Domain == "" {
		return nil, E.New("dnstt: domain is required")
	}
	if len(options.Resolvers) == 0 {
		return nil, E.New("dnstt: at least one resolver is required")
	}
	if options.TunnelsPerResolver <= 0 {
		// Two per resolver is as many KCP sessions as the tunnel
		// extension's memory allowance can carry comfortably.
		options.TunnelsPerResolver = 2
	}
	server, err := vaydns.NewTunnelServer(options.Domain, options.PublicKey)
	if err != nil {
		return nil, E.Cause(err, "dnstt")
	}
	server.DnsttCompat = options.DnsttCompat
	server.RecordType = options.RecordType
	return &dnsttOutbound{
		Adapter: outbound.NewAdapterWithDialerOptions(TypeDNSTT, tag, []string{N.NetworkTCP}, options.DialerOptions),
		logger:  logger,
		options: options,
		server:  server,
	}, nil
}

// parseResolver reads one resolver string in any of the three shapes.
func parseResolver(raw string) (vaydns.Resolver, error) {
	trimmed := strings.TrimSpace(raw)
	lower := strings.ToLower(trimmed)
	switch {
	case strings.HasPrefix(lower, "https://"):
		return vaydns.NewResolver(vaydns.ResolverTypeDOH, trimmed)
	case strings.HasPrefix(lower, "tls://"), strings.HasPrefix(lower, "dot://"):
		return vaydns.NewResolver(vaydns.ResolverTypeDOT, withDefaultPort(trimmed[6:], "853"))
	default:
		return vaydns.NewResolver(vaydns.ResolverTypeUDP, withDefaultPort(strings.TrimPrefix(trimmed, "udp://"), "53"))
	}
}

func withDefaultPort(address string, port string) string {
	if _, _, err := net.SplitHostPort(address); err != nil {
		return net.JoinHostPort(address, port)
	}
	return address
}

// openTunnel runs the whole handshake for one resolver: DNS transport, DNS
// framing, KCP, Noise, then smux. vaydns exposes the steps separately so a
// host like this one can own the retry policy.
func (o *dnsttOutbound) openTunnel(resolver vaydns.Resolver) (*vaydns.Tunnel, error) {
	tunnel, err := vaydns.NewTunnel(resolver, o.server)
	if err != nil {
		return nil, err
	}
	steps := []func() error{
		tunnel.InitiateResolverConnection,
		func() error { return tunnel.InitiateDNSPacketConn(o.server.Addr) },
		func() error { return tunnel.InitiateKCPConn(0) },
		tunnel.InitiateNoiseChannel,
		tunnel.InitiateSmuxSession,
	}
	for _, step := range steps {
		if err := step(); err != nil {
			_ = tunnel.Close()
			return nil, err
		}
	}
	return tunnel, nil
}

// ensureTunnels builds the tunnels on first use. Every resolver is raced and
// the first tunnel to come up unblocks the dial; the others join the pool as
// they arrive, so one resolver that is blocked rather than simply absent —
// which is the normal case on a censored network — cannot hold up the
// connection for its whole handshake timeout. Starting is lazy, so a
// subscription that merely lists a dnstt server costs nothing until chosen.
func (o *dnsttOutbound) ensureTunnels() error {
	o.startMu.Lock()
	defer o.startMu.Unlock()

	o.mu.Lock()
	closed, running := o.closed, len(o.tunnels)
	o.mu.Unlock()
	if closed {
		return net.ErrClosed
	}
	if running > 0 {
		return nil
	}

	results := make(chan dnsttAttempt, 1)
	started := 0
	for _, raw := range o.options.Resolvers {
		resolver, err := parseResolver(raw)
		if err != nil {
			o.logger.Warn("dnstt: skipping resolver ", raw, ": ", err)
			continue
		}
		for range o.options.TunnelsPerResolver {
			started++
			go func() {
				tunnel, err := o.openTunnel(resolver)
				results <- dnsttAttempt{tunnel, err}
			}()
		}
	}
	if started == 0 {
		return E.New("dnstt: no usable resolver")
	}

	var firstErr error
	for settled := range started {
		result := <-results
		if result.err != nil {
			if firstErr == nil {
				firstErr = result.err
			}
			continue
		}
		o.addTunnel(result.tunnel)
		o.logger.Info("dnstt: first tunnel up; ", started-settled-1, " still dialling")
		go o.collectTunnels(results, started-settled-1)
		return nil
	}
	if firstErr == nil {
		firstErr = errors.New("no resolver answered")
	}
	return E.Cause(firstErr, "dnstt: no tunnel came up")
}

// collectTunnels takes the tunnels that finished after the dial was already
// unblocked, so the pool grows instead of those handshakes being wasted.
func (o *dnsttOutbound) collectTunnels(results <-chan dnsttAttempt, remaining int) {
	for range remaining {
		if result := <-results; result.err == nil {
			o.addTunnel(result.tunnel)
		}
	}
}

// addTunnel puts a tunnel into the pool, or closes it if the outbound was
// shut down while it was still handshaking.
func (o *dnsttOutbound) addTunnel(tunnel *vaydns.Tunnel) {
	o.mu.Lock()
	if o.closed {
		o.mu.Unlock()
		_ = tunnel.Close()
		return
	}
	o.tunnels = append(o.tunnels, tunnel)
	o.mu.Unlock()
}

// dropTunnel forgets a tunnel whose session died. Once the last one is gone
// the next dial rebuilds them all, which is how a tunnel that outlived its
// resolver recovers without the user reconnecting.
func (o *dnsttOutbound) dropTunnel(dead *vaydns.Tunnel) {
	o.mu.Lock()
	for i, tunnel := range o.tunnels {
		if tunnel == dead {
			o.tunnels = append(o.tunnels[:i], o.tunnels[i+1:]...)
			break
		}
	}
	o.mu.Unlock()
	_ = dead.Close()
}

func (o *dnsttOutbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if network != N.NetworkTCP {
		return nil, E.New("dnstt: only TCP fits through DNS")
	}
	if err := o.ensureTunnels(); err != nil {
		return nil, err
	}
	// The pool can empty between the build and here if the last session died
	// meanwhile, and the counter is unsigned: on a 32-bit device (armeabi-v7a
	// is still shipped) a plain int conversion would go negative past 2^31
	// and index out of range.
	o.mu.Lock()
	if len(o.tunnels) == 0 {
		o.mu.Unlock()
		return nil, E.New("dnstt: no tunnel is up")
	}
	tunnel := o.tunnels[int(o.next.Add(1)%uint32(len(o.tunnels)))]
	o.mu.Unlock()

	stream, err := tunnel.OpenStream()
	if err != nil {
		o.dropTunnel(tunnel)
		return nil, E.Cause(err, "dnstt: open stream")
	}
	if strings.EqualFold(o.options.Upstream, "raw") {
		return stream, nil
	}
	if _, err := socks.ClientHandshake5(stream, socks5.CommandConnect, destination, o.options.Username, o.options.Password); err != nil {
		_ = stream.Close()
		return nil, E.Cause(err, "dnstt: handshake with the server's upstream")
	}
	return stream, nil
}

func (o *dnsttOutbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, E.New("dnstt: UDP is not carried")
}

func (o *dnsttOutbound) Close() error {
	o.mu.Lock()
	tunnels := o.tunnels
	o.tunnels = nil
	o.closed = true
	o.mu.Unlock()
	for _, tunnel := range tunnels {
		_ = tunnel.Close()
	}
	return nil
}
