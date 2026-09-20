package raycore

import (
	"context"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/protocol/direct"
	"github.com/sagernet/sing/common"
	"github.com/sagernet/sing/service"
)

// sing-box's direct outbound asks the interface monitor for this device's own
// addresses once the box is up, to recognise traffic that loops back to it.
// On Android an unprivileged process cannot open the netlink socket that
// monitor needs, so sing-box leaves the monitor nil — and that lookup then
// dereferences it. Every sing-box server (SSH, TUIC, and now AnyTLS,
// Hysteria and DNSTT) crashed the app the moment it connected, because the
// config always carries a direct outbound for the bypass rules.
//
// The stock outbound is kept and only that one lookup is skipped, and only
// when there is genuinely no monitor to ask, so platforms that do have one
// behave exactly as before.
func registerGuardedDirect(registry *outbound.Registry) {
	outbound.Register[option.DirectOutboundOptions](registry, C.TypeDirect, newGuardedDirect)
}

type guardedDirect struct {
	adapter.Outbound
	ctx context.Context
}

func newGuardedDirect(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options option.DirectOutboundOptions) (adapter.Outbound, error) {
	inner, err := direct.NewOutbound(ctx, router, logger, tag, options)
	if err != nil {
		return nil, err
	}
	return &guardedDirect{Outbound: inner, ctx: ctx}, nil
}

// hasInterfaceMonitor reports whether anything can answer which interfaces
// this device has.
func (d *guardedDirect) hasInterfaceMonitor() bool {
	network := service.FromContext[adapter.NetworkManager](d.ctx)
	return network != nil && network.InterfaceMonitor() != nil
}

func (d *guardedDirect) Start(stage adapter.StartStage) error {
	switch stage {
	case adapter.StartStatePostStart, adapter.StartStateStarted:
		if !d.hasInterfaceMonitor() {
			return nil
		}
	}
	return adapter.LegacyStart(d.Outbound, stage)
}

func (d *guardedDirect) Close() error {
	return common.Close(d.Outbound)
}

// InterfaceUpdated reaches the inner outbound only where a monitor exists to
// raise it, but the guard keeps it safe if one appears later.
func (d *guardedDirect) InterfaceUpdated(ctx context.Context) {
	if !d.hasInterfaceMonitor() {
		return
	}
	if listener, ok := d.Outbound.(adapter.InterfaceUpdateListener); ok {
		listener.InterfaceUpdated(ctx)
	}
}
