// Trims geoip.dat / geosite.dat down to the categories SkyRay needs, so the
// packet tunnel extension can load them without blowing its 50 MB memory cap.
package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

func main() {
	if len(os.Args) > 2 && os.Args[2] == "stats" { statsMain(os.Args[1] + "/geosite.dat"); return }
	in := os.Args[1]
	trimIP(in+"/geoip.dat", "geoip.dat", []string{"ir", "private"})
	trimSite(in+"/geosite.dat", "geosite.dat", []string{"category-ir", "category-ads", "private"})
}

func trimIP(src, dst string, keep []string) {
	raw, err := os.ReadFile(src)
	must(err)
	var list geodata.GeoIPList
	must(proto.Unmarshal(raw, &list))
	var out geodata.GeoIPList
	for _, e := range list.Entry {
		for _, k := range keep {
			if strings.EqualFold(e.Code, k) {
				out.Entry = append(out.Entry, e)
				fmt.Printf("geoip keep %s: %d cidrs\n", e.Code, len(e.Cidr))
			}
		}
	}
	b, err := proto.Marshal(&out)
	must(err)
	must(os.WriteFile(dst, b, 0o644))
}

func trimSite(src, dst string, keep []string) {
	raw, err := os.ReadFile(src)
	must(err)
	var list geodata.GeoSiteList
	must(proto.Unmarshal(raw, &list))
	var out geodata.GeoSiteList
	for _, e := range list.Entry {
		for _, k := range keep {
			if strings.EqualFold(e.Code, k) {
				out.Entry = append(out.Entry, e)
				fmt.Printf("geosite keep %s: %d domains\n", e.Code, len(e.Domain))
			}
		}
	}
	b, err := proto.Marshal(&out)
	must(err)
	must(os.WriteFile(dst, b, 0o644))
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
