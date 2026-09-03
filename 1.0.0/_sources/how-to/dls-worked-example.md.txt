# A Worked Session (Diamond Light Source)

A real session on beamline I07, annotated. Other facilities should be able to
follow the same shape with their own service names — the only DLS-specific
parts are the `module load` and the gateway service.

## Install the launcher (once)

```bash
mkdir -p $HOME/bin
cd $HOME/bin
curl -O https://raw.githubusercontent.com/epics-containers/ec-netshoot/main/netshoot
chmod +x netshoot
```

`$HOME/bin` is on your PATH in any new shell, though not the one you are in.
The launcher needs nothing but `kubectl`, and it is a single bash script — the
`curl` above is the whole installation.

## Set the context (each session)

```bash
module load ec/i07
```

```
Loading ec/i07
  Loading requirement: argocd/v2.14.10 edge-containers-cli/5.2.1 vscode/1.133.0 plandev/0.2.0 k8s-i07/local
(k8s-i07:i07-beamline)
```

That sets the kubectl context and namespace, so `netshoot` needs no arguments —
it picks up `i07-beamline` from the current context and says so before creating
anything.

```bash
netshoot
```

## Pinging a device works

```bash
ping bl07i-mo-step-09
```

```
PING bl07i-mo-step-09.diamond.ac.uk (172.23.107.174) 56(84) bytes of data.
64 bytes from bl07i-mo-step-09.diamond.ac.uk (172.23.107.174): icmp_seq=1 ttl=127 time=0.115 ms
64 bytes from bl07i-mo-step-09.diamond.ac.uk (172.23.107.174): icmp_seq=2 ttl=127 time=0.076 ms
^C
--- bl07i-mo-step-09.diamond.ac.uk ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1035ms
rtt min/avg/max/mdev = 0.076/0.095/0.115/0.019 ms
```

Two things worth noting. This is the **pod** network, not `--host-network`:
beamline device networks are routed from pods as well as from nodes, so device
reachability needs no special flags.

## Services do not answer ping

```bash
kubectl get svc
```

```
NAME                       TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                                                                                     AGE
excalibur-01-meta-writer   ClusterIP      10.101.159.122   <none>          5659/TCP                                                                                    4h12m
excalibur-01-odin-data-0   ClusterIP      10.109.73.6      <none>          10004/TCP,10008/TCP                                                                         4h12m
excalibur-01-odin-data-1   ClusterIP      10.105.186.0     <none>          10004/TCP,10008/TCP                                                                         4h12m
excalibur-01-odin-server   LoadBalancer   10.99.132.213    172.23.107.44   8888:31030/TCP                                                                              4h12m
i07-epics-gateways         LoadBalancer   10.104.11.12     172.23.107.46   9064:30854/TCP,9064:30854/UDP,9065:31264/TCP,9065:31264/UDP,9075:32595/TCP,9076:31844/UDP   9d
i07-epics-opis             LoadBalancer   10.110.39.33     172.23.107.45   80:31849/TCP,443:32171/TCP                                                                  9d
```

```bash
ping excalibur-01-odin-data-0
```

```
PING excalibur-01-odin-data-0.i07-beamline.svc.cluster.local (10.109.73.6) 56(84) bytes of data.
From bl09i-nt-netsw-04-04r.diamond.ac.uk (172.23.66.109) icmp_seq=1 Destination Host Unreachable
From bl09i-nt-netsw-04-04r.diamond.ac.uk (172.23.66.109) icmp_seq=2 Destination Host Unreachable
^C
--- excalibur-01-odin-data-0.i07-beamline.svc.cluster.local ping statistics ---
4 packets transmitted, 0 received, +4 errors, 100% packet loss, time 3099ms
```

**This is the single most useful thing on this page.** The service is perfectly
healthy. A ClusterIP is a *virtual* address: kube-proxy rewrites traffic to the
service's declared **ports** and nothing else. ICMP has no port, so nothing
rewrites it, and the packet leaves with a destination address that nothing in
the cluster claims.

**A failed ping to a Service means nothing. Use `nc -zv`.**

## Check the port instead

```bash
nc -zv excalibur-01-odin-data-0 10004
```

```
Connection to excalibur-01-odin-data-0 (10.109.73.6) 10004 port [tcp/*] succeeded!
```

That is the real answer: DNS resolved, the ClusterIP routed, kube-proxy picked
an endpoint, and something accepted a TCP connection. Ranges work too, so both
of that service's ports take one command:

```bash
nc -zv excalibur-01-odin-data-0 10004-10008
```

## EPICS through the gateway

The pod network has no broadcast, so default CA name search finds nothing. At
DLS the answer is the gateway service rather than `--host-network`:

```bash
export EPICS_CA_ADDR_LIST=i07-epics-gateways:9064
caget BL07I-VA-IONP-06:STA
```

```
BL07I-VA-IONP-06:STA           Running
```

CA falls back to unicast search against the addresses in `EPICS_CA_ADDR_LIST`,
and the gateway answers. Read the ports off the `kubectl get svc` output above:
`i07-epics-gateways` exposes 9064 and 9065 on both TCP and UDP, and 9075/9076
for PV Access. So the PVA equivalent is:

```bash
export EPICS_PVA_NAME_SERVERS=i07-epics-gateways:9075
pvxget BL07I-VA-IONP-06:STA
```

Two follow-ups worth knowing:

```bash
cainfo BL07I-VA-IONP-06:STA      # which server actually answered — the gateway
caget -w5 SOME:MISSING:PV        # bound timeout, rather than hanging
```

If you need broadcast search exactly as an IOC does it, `netshoot -h` gives you
the node's network stack — but then you are testing what a workstation tests,
and the gateway route above is what services in the cluster actually use.

## Other things worth a try

Commands only; run them and see what your namespace says.

```bash
# What did that name really resolve to, and via which search suffix?
nslookup excalibur-01-odin-data-0
cat /etc/resolv.conf

# Does the Service have any backing pods? An empty list here explains most
# "the network is broken" reports.
kubectl get endpointslices -l kubernetes.io/service-name=excalibur-01-odin-data-0

# Reach a LoadBalancer by its external address, from inside the cluster
nc -zv 172.23.107.44 8888
curl -sI http://i07-epics-opis

# Where does the path to a device go, and what is the MTU?
tracepath bl07i-mo-step-09

# Throughput between two pods - start the server end first
netshoot -k --name iperf-server -c 'iperf3 -s -D'
netshoot -c 'iperf3 -c <server-pod-ip>'

# A device wired to one specific node
netshoot --node bl07i-node1
netshoot --node bl07i-node1 --annotation usb-compat=enabled   # mounts /dev/bus/usb
netshoot --node bl07i-node1 --annotation usb-compat=enabled -c lsusb
```
