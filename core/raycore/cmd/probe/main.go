package main

// Mac-side smoke test for the raycore sing-box wrapper against a local TUIC
// test server (see HANDOVER.md §7). Replace the placeholder credentials first.

import (
	"fmt"
	"github.com/ehsan/rayclient/raycore"
)

func main() {
	tuic := `{"type":"tuic","server":"127.0.0.1","server_port":8443,"uuid":"00000000-0000-0000-0000-000000000000","password":"CHANGE-ME","congestion_control":"bbr","udp_relay_mode":"native","tls":{"enabled":true,"server_name":"rayclient-test","alpn":["h3"],"insecure":true}}`
	for _, u := range []string{"http://cp.cloudflare.com/generate_204", "https://www.google.com/generate_204", "http://www.gstatic.com/generate_204"} {
		ms, err := raycore.SingboxPing(tuic, u, 15000)
		fmt.Printf("tuic %s: %d ms err=%v\n", u, ms, err)
	}
	// Full config validation as the extension would build it
	err := raycore.SingboxTest(`{"log":{"level":"warn"},"dns":{"servers":[{"tag":"dns-remote","type":"https","server":"1.1.1.1","detour":"proxy"}],"final":"dns-remote","strategy":"prefer_ipv4"},"inbounds":[{"type":"socks","tag":"socks-in","listen":"127.0.0.1","listen_port":10808}],"outbounds":[` + tuic[:len(tuic)-1] + `,"tag":"proxy"},{"type":"direct","tag":"direct"},{"type":"block","tag":"block"}],"route":{"rules":[{"action":"sniff"},{"protocol":"dns","action":"hijack-dns"},{"ip_is_private":true,"outbound":"direct"}],"final":"proxy","auto_detect_interface":false}}`)
	fmt.Println("full config test:", err)
}
