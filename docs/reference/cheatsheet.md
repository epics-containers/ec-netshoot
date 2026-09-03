# Cheat Sheet

The page to paste from at 2am.

## Get in

```bash
netshoot -n i07-beamline                        # shell in the namespace
netshoot -c 'nc -zv my-ioc 5064'                # one-shot, then exit
netshoot -n i07-beamline --node bl07i-node1     # pinned to a node
netshoot --host-network                         # the node's network stack
netshoot -k                                     # leave it running
netshoot --delete                               # tear down a kept pod
netshoot --print                                # show the manifest, change nothing
```

## The ladder

```bash
cat /etc/resolv.conf                                       # search path, ndots
dig +search my-ioc                                         # does the name resolve
kubectl get endpointslices -l kubernetes.io/service-name=my-ioc   # any endpoints?
nc -zv my-ioc 5064                                         # via the Service
nc -zv 10.42.1.37 5064                                     # direct to a pod
ss -tulpn                                                  # what is listening here
kubectl get networkpolicy                                  # anything dropping it
tracepath my-ioc                                           # where does it stop, and MTU
tcpdump -nni any host X and port Y -w /tmp/c.pcap          # last resort
```

## Reading a failure

| Symptom | Means |
|---|---|
| Connection refused | Path is fine, nothing listening on that port |
| Timeout | Dropped somewhere — policy, routing, or masquerade |
| Name resolves, no endpoints | Service selector does not match pod labels |
| Works on pod IP, not Service | kube-proxy or the endpoint list |
| Works with `--host-network`, not without | Cluster is in the way — suspect masquerade |
| Large writes hang, small ones fine | Path MTU black hole (`tracepath` reports it) |
| `bash: /usr/bin/X: Operation not permitted` | The *shell* cannot launch it — a file-capability/NoNewPrivs clash, not a network fault |
| `X: socket: Operation not permitted` | The program ran but was denied a raw socket — the pod lacks `CAP_NET_RAW` |

## Ports

| Protocol | Search | Data |
|---|---|---|
| Channel Access | UDP 5064 | TCP 5064 |
| PV Access | UDP 5076 | TCP 5075 |
| Kubernetes API | — | TCP 443 (`kubernetes.default.svc`) |
| Cluster DNS | UDP/TCP 53 | (`kube-dns.kube-system.svc`) |

## EPICS without broadcast

```bash
EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_ADDR_LIST=my-ioc.i07-beamline.svc caget MY:PV
EPICS_PVA_NAME_SERVERS=my-ioc.i07-beamline.svc:5075 pvxget MY:PV
cainfo MY:PV                       # which server actually answered
PVXS_LOG='*=DEBUG' pvxget MY:PV
```

## Odds and ends

```bash
nc -zv moxa1 4000-4010                          # port range
socat -v TCP-LISTEN:9999,fork STDOUT            # a listener to probe towards
openssl s_client -connect svc:443 -servername svc   # TLS and certificates
capsh --print                                   # what am I actually allowed to do
kubectl cp i07-beamline/netshoot-$USER:/tmp/c.pcap ./c.pcap   # from your workstation
```

Bandwidth needs a netshoot at each end:

```bash
netshoot -k --name iperf-server -c 'iperf3 -s -D'   # one end
netshoot -c 'iperf3 -c iperf-server-pod-ip'         # the other
```
