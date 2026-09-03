# Tools

Grouped by what they need from the container runtime, because that determines
whether they will still work if these namespaces are ever tightened. See
`../explanations/design` for why that split matters.

## Work with no capabilities at all

Available under any Pod Security Standard, including `restricted`.

| Tool | For |
|---|---|
| `nc` (netcat-openbsd) | TCP reachability — `nc -zv host port`, and port ranges |
| `socat` | Relays, UDP probes, unix sockets, ad-hoc listeners |
| `dig`, `host` | Cluster DNS and upstream resolution |
| `ss` | What is listening and what is connected |
| `ip` | Interfaces, addresses, routes |
| `tracepath` | Path tracing **and path MTU**, with no raw socket |
| `openssl` | `s_client` for TLS handshakes and certificates |
| `jq` | Reading `kubectl -o json` |
| `getcap` / `capsh` | Checking what this pod is actually permitted to do |
| `kubectl` | The API server's view, as the pod's ServiceAccount |
| `iperf3` | Throughput, with a netshoot at each end |
| `curl`, `wget`, `ssh` | From the base image |

## Best effort — need `CAP_NET_RAW`

These open raw sockets, so they work only when the pod actually holds
`CAP_NET_RAW` in its effective set. `ping` additionally works with no
capability at all when the launcher's `ping_group_range` sysctl is applied,
which is the default.

:::{note}
The image strips file capabilities from all of its binaries. Ubuntu ships
`ping`, `arping` and `mtr-packet` with `cap_net_raw+ep`, and the effective bit
makes `execve` itself fail with `Operation not permitted` in any pod that drops
capabilities or sets `allowPrivilegeEscalation: false`. Stripping it costs
nothing and turns "cannot run at all" into "runs, with whatever privilege the
pod actually has". See `../explanations/design`.
:::

| Tool | For |
|---|---|
| `ping` | ICMP echo. Weak evidence — CNIs often drop ICMP but pass TCP |
| `arping` | Is a device answering ARP on this L2 segment |
| `traceroute` | Path tracing. Prefer `tracepath` |
| `mtr` | Continuous path statistics |
| `tcpdump` | Packet capture |

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
- **`net-tools`** — busybox's `netstat` and `ifconfig` remain available; `ss`
  and `ip` are better.

`apt` works and the pod has egress, so anything missing is one command away.
If you find yourself installing the same thing twice, open an issue.
