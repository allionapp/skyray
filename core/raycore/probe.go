package raycore

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"
	xrayNet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/session"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf"
)

// A probe is one HTTP request through a server that answers three questions
// at once: is it reachable, how long does it take, and where does the
// traffic come out. Cloudflare's trace endpoint is the target because its
// reply names the exit address and country in two plain lines, with no key,
// no quota and a body a few hundred bytes long.
const DefaultProbeURL = "https://www.cloudflare.com/cdn-cgi/trace"

// One outbound to test, owned by either core.
type probeItem struct {
	Core     string          `json:"core"`
	Outbound json.RawMessage `json:"outbound"`
}

// ProbeResult is what one probe found; Delay is -1 when it failed.
type ProbeResult struct {
	Delay   int64  `json:"delay"`
	IP      string `json:"ip,omitempty"`
	Country string `json:"country,omitempty"`
	Error   string `json:"error,omitempty"`
}

const probeWorkers = 5

// ProbeBatch tests several outbounds and reports each one's delay, exit IP
// and country. `itemsJSON` is an array of {"core":"xray"|"singbox","outbound":{…}};
// the reply is an array of ProbeResult in the same order. Xray outbounds share
// one instance and sing-box outbounds another, so a batch of five does not
// start five cores. Failures are reported per item, never as a whole.
func ProbeBatch(itemsJSON string, url string, timeoutMs int) (string, error) {
	var items []probeItem
	if err := json.Unmarshal([]byte(itemsJSON), &items); err != nil {
		return "", err
	}
	if len(items) == 0 {
		return "[]", nil
	}
	if timeoutMs <= 0 {
		timeoutMs = 8000
	}
	if url == "" {
		url = DefaultProbeURL
	}
	timeout := time.Duration(timeoutMs) * time.Millisecond
	results := make([]ProbeResult, len(items))
	dialers := make([]func(context.Context, string, string) (net.Conn, error), len(items))

	var xrayIdx, sbIdx []int
	for i, item := range items {
		switch item.Core {
		case "singbox":
			sbIdx = append(sbIdx, i)
		default:
			xrayIdx = append(xrayIdx, i)
		}
	}

	if len(xrayIdx) > 0 {
		instance, fns, err := startXrayProbe(items, xrayIdx)
		if err != nil {
			for _, i := range xrayIdx {
				results[i] = ProbeResult{Delay: -1, Error: err.Error()}
			}
		} else {
			defer instance.Close()
			for _, i := range xrayIdx {
				dialers[i] = fns[i]
			}
		}
	}
	if len(sbIdx) > 0 {
		instance, cancel, fns, err := startSingboxProbe(items, sbIdx, timeout)
		if err != nil {
			for _, i := range sbIdx {
				results[i] = ProbeResult{Delay: -1, Error: err.Error()}
			}
		} else {
			defer cancel()
			defer instance.Close()
			for _, i := range sbIdx {
				dialers[i] = fns[i]
			}
		}
	}

	jobs := make(chan int)
	var wg sync.WaitGroup
	for range probeWorkers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				results[i] = probeThrough(dialers[i], url, timeout)
			}
		}()
	}
	for i := range items {
		if dialers[i] != nil {
			jobs <- i
		}
	}
	close(jobs)
	wg.Wait()

	out, err := json.Marshal(results)
	return string(out), err
}

// startXrayProbe runs every Xray outbound of the batch in one instance, each
// under its own tag, and hands back a dialer per item that forces that tag.
func startXrayProbe(items []probeItem, idx []int) (*core.Instance, map[int]func(context.Context, string, string) (net.Conn, error), error) {
	outbounds := make([]conf.OutboundDetourConfig, 0, len(idx))
	tags := map[int]string{}
	for _, i := range idx {
		var ob conf.OutboundDetourConfig
		if err := json.Unmarshal(items[i].Outbound, &ob); err != nil {
			return nil, nil, fmt.Errorf("outbound %d: %w", i, err)
		}
		ob.Tag = fmt.Sprintf("probe-%d", i)
		tags[i] = ob.Tag
		outbounds = append(outbounds, ob)
	}
	config, err := (&conf.Config{OutboundConfigs: outbounds}).Build()
	if err != nil {
		return nil, nil, err
	}
	instance, err := core.New(config)
	if err != nil {
		return nil, nil, err
	}
	if err := instance.Start(); err != nil {
		_ = instance.Close()
		return nil, nil, err
	}
	fns := map[int]func(context.Context, string, string) (net.Conn, error){}
	for i, tag := range tags {
		tag := tag
		fns[i] = func(ctx context.Context, network, address string) (net.Conn, error) {
			destination, err := xrayNet.ParseDestination("tcp:" + address)
			if err != nil {
				return nil, err
			}
			return core.Dial(session.SetForcedOutboundTagToContext(ctx, tag), instance, destination)
		}
	}
	return instance, fns, nil
}

// startSingboxProbe is the sing-box twin of startXrayProbe.
func startSingboxProbe(items []probeItem, idx []int, timeout time.Duration) (*box.Box, context.CancelFunc, map[int]func(context.Context, string, string) (net.Conn, error), error) {
	outbounds := make([]json.RawMessage, 0, len(idx))
	tags := map[int]string{}
	for _, i := range idx {
		var raw map[string]json.RawMessage
		if err := json.Unmarshal(items[i].Outbound, &raw); err != nil {
			return nil, nil, nil, fmt.Errorf("outbound %d: %w", i, err)
		}
		tag := fmt.Sprintf("probe-%d", i)
		raw["tag"] = json.RawMessage(fmt.Sprintf("%q", tag))
		tags[i] = tag
		ob, _ := json.Marshal(raw)
		outbounds = append(outbounds, ob)
	}
	list, _ := json.Marshal(outbounds)
	configJSON := fmt.Sprintf(`{"log":{"level":"error"},"outbounds":%s}`, string(list))

	// The batch runs for at most one timeout per worker round, so give the
	// instance a little more than that before the context reaps it.
	ctx, cancel := context.WithTimeout(newContext(), timeout*time.Duration(len(idx)/probeWorkers+2))
	options, err := parseOptions(ctx, configJSON)
	if err != nil {
		cancel()
		return nil, nil, nil, err
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		cancel()
		return nil, nil, nil, err
	}
	if err := instance.Start(); err != nil {
		_ = instance.Close()
		cancel()
		return nil, nil, nil, err
	}
	manager := service.FromContext[adapter.OutboundManager](ctx)
	if manager == nil {
		_ = instance.Close()
		cancel()
		return nil, nil, nil, errors.New("outbound manager unavailable")
	}
	fns := map[int]func(context.Context, string, string) (net.Conn, error){}
	for i, tag := range tags {
		out, found := manager.Outbound(tag)
		if !found {
			continue
		}
		dialer, ok := out.(N.Dialer)
		if !ok {
			continue
		}
		fns[i] = func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialer.DialContext(ctx, network, M.ParseSocksaddr(addr))
		}
	}
	return instance, cancel, fns, nil
}

// probeThrough makes the request over one dialer and reads the trace lines.
func probeThrough(dial func(context.Context, string, string) (net.Conn, error), url string, timeout time.Duration) ProbeResult {
	client := &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			DialContext:       dial,
			DisableKeepAlives: true,
		},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	defer client.CloseIdleConnections()
	start := time.Now()
	resp, err := client.Get(url)
	if err != nil {
		return ProbeResult{Delay: -1, Error: err.Error()}
	}
	delay := time.Since(start).Milliseconds()
	defer resp.Body.Close()
	if resp.StatusCode >= 500 {
		return ProbeResult{Delay: -1, Error: fmt.Sprintf("HTTP %d", resp.StatusCode)}
	}
	result := ProbeResult{Delay: delay}
	// A non-trace target (the old generate_204 URLs still work here) simply
	// yields no exit information.
	scanner := bufio.NewScanner(io.LimitReader(resp.Body, 4096))
	for scanner.Scan() {
		key, value, ok := strings.Cut(scanner.Text(), "=")
		if !ok {
			continue
		}
		switch key {
		case "ip":
			result.IP = value
		case "loc":
			result.Country = value
		}
	}
	return result
}
