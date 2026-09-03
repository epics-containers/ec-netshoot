# Tools

What is in the image and what each thing is for. Nothing here needs a Linux
capability, which is deliberate — see `../explanations/design`.

## Everything in the image

Every tool here works with **no capabilities at all**, so the image is useful
under any Pod Security Standard and in clusters that drop `CAP_NET_RAW`.

| Tool | For |
|---|---|
| `nc` (netcat-openbsd) | TCP reachability — `nc -zv host port`, and port ranges |
| `socat` | Relays, UDP probes, unix sockets, ad-hoc listeners |
| `nslookup`, `host` | Cluster DNS — **both honour the search path**, so `nslookup my-ioc` works |
| `dig` | When you need a record type, a specific server, or TTLs. Note `dig` ignores the search path unless given `+search` |
| `ss` | What is listening and what is connected |
| `ip` | Interfaces, addresses, routes |
| `tracepath` | Path tracing **and path MTU**, with no raw socket |
| `ping` | ICMP echo, via an unprivileged `SOCK_DGRAM` socket. Weak evidence — CNIs often drop ICMP but pass TCP |
| `traceroute` | Path tracing. Default UDP method uses `IP_RECVERR`, so no raw socket |
| `openssl` | `s_client` for TLS handshakes and certificates |
| `jq` | Reading `kubectl -o json` |
| `getcap` / `capsh` | Checking what this pod is actually permitted to do |
| `kubectl` (also `k`) | The API server's view, as the pod's ServiceAccount |
| `iperf3` | Throughput, with a netshoot at each end |
| `curl`, `wget`, `ssh` | From the base image |

## EPICS, from the base image

| Tool | For |
|---|---|
| `caget`, `caput`, `camonitor` | Channel Access |
| `cainfo` | **Which server actually answered** — the useful one when triaging |
| `pvxget`, `pvxput`, `pvxmonitor` | PV Access |
| `pvxinfo`, `pvxlist` | PVA introspection and server discovery |

## Deliberately absent

- **`nmap`** — scanning fragile device hardware can wedge it. `nc -zv host
  4000-4010` covers the legitimate case. See `../how-to/reach-a-device`.
- **`tcpdump`, `arping`, `mtr`** — they need a raw socket, and clusters commonly
  drop `CAP_NET_RAW` from the capability bounding set, where nothing inside the
  pod can recover it. Shipping tools that cannot run only wastes time during an
  incident. Capture at the other end instead: on the device, on the node, or in
  a pod that does hold the capability.
- **`net-tools`** — busybox's `netstat` and `ifconfig` remain available; `ss`
  and `ip` are better.

`apt` works and the pod has egress, so anything missing is one command away.
If you find yourself installing the same thing twice, open an issue.
