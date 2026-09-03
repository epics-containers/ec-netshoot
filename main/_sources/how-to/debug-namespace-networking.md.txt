# Debug Networking Inside a Namespace

This is the ladder. Each rung distinguishes two hypotheses, so you always know
what the next command buys you. Work down it in order — skipping rungs is how
people end up capturing packets to diagnose a Service selector typo.

Start a pod in the namespace you care about:

```bash
netshoot -n i07-beamline
```

## 0. Where am I?

```bash
hostname -i                 # this pod's IP
cat /etc/resolv.conf        # search path and the ndots setting
ip addr                     # interfaces the pod can see
kubectl config current-context
```

Read `/etc/resolv.conf` before anything else. Two things matter:

- the **search path**, normally `<ns>.svc.cluster.local svc.cluster.local
  cluster.local`, which is why a bare `my-ioc` resolves at all
- **`ndots:5`**, which means any name with fewer than five dots is tried
  against every search-path suffix *first*. `moxa1.diamond.ac.uk` has three
  dots, so it gets four failed lookups before the real one. Usually just slow;
  occasionally the cause of a timeout you are blaming on something else. A
  trailing dot (`moxa1.diamond.ac.uk.`) skips the search path entirely, which
  is a good way to prove that is what is happening.

## 1. Does the name resolve?

```bash
dig +search my-ioc
dig my-ioc.i07-beamline.svc.cluster.local
```

A ClusterIP Service resolves to its virtual IP. A **headless** Service
(`clusterIP: None`) resolves to the pod IPs directly — so several A records,
or none, is normal there and not a fault.

If the name does not resolve at all, the Service does not exist under that
name; check for a typo or the wrong namespace before going further.

## 2. Are there any endpoints?

```bash
kubectl get endpointslices -l kubernetes.io/service-name=my-ioc
```

**An empty endpoint list is the single most common cause of "the network is
broken", and it is not a network fault at all.** It almost always means the
Service's selector does not match the pod's labels. Compare them directly:

```bash
kubectl get svc my-ioc -o jsonpath='{.spec.selector}'
kubectl get pods --show-labels
```

A second cause: the pods exist and are labelled correctly but are not `Ready`,
so they are held out of the endpoint list on purpose. `kubectl get pods` will
show that.

:::{note}
`kubectl` inside the pod authenticates as the pod's **ServiceAccount**, not as
you. If you get `Forbidden`, that is RBAC working correctly — see
`../explanations/design`.
:::

## 3. Is TCP getting through?

```bash
nc -zv my-ioc 5064                       # via the Service
nc -zv 10.42.1.37 5064                   # direct to a pod IP from step 2
```

Comparing those two is the useful part:

| Service | Pod IP | Reading |
|---|---|---|
| fail | works | kube-proxy or the endpoint list — go back to step 2 |
| fail | fail | nothing is listening, or traffic is being dropped |
| works | works | not a connectivity problem; look at the application |

Note the failure *mode*, not just the failure. **Connection refused** means a
packet reached a host that actively said no — the path is fine, the port is
shut. **Timeout** means nothing came back at all, which is a drop somewhere:
policy, routing, or a firewall.

`nc` also takes ranges, which is handy when you are unsure which port a device
or service is on:

```bash
nc -zv moxa1 4000-4010
```

## 4. Is the application actually listening?

```bash
ss -tulpn
```

Run this in the *target* pod (`kubectl exec`), or from a netshoot pod pinned to
the same node with `--node`. The classic finding is a process bound to
`127.0.0.1` rather than `0.0.0.0` — reachable from inside its own container and
from nowhere else. It looks exactly like a network fault from the outside.

## 5. Is something dropping it?

```bash
kubectl get networkpolicy
```

The signature is a **timeout** rather than a refusal, from one pod but not
another. If the namespace has no NetworkPolicy at all, skip this and go to
step 6 — in a cluster with open egress, routing is the more likely suspect.

## 6. Where does the path stop?

```bash
tracepath my-ioc.i07-beamline.svc.cluster.local
```

`tracepath` needs **no capabilities at all** — UDP with an incrementing TTL,
reading the errors back via `IP_RECVERR`. That is why it is the one the
documentation leads with; `traceroute -I` and `-T` would need a raw socket. See
`../explanations/design`.

`tracepath` also reports the path MTU, which matters more than it sounds. An
overlay network with a smaller MTU than the interface advertises produces a
black hole where small writes succeed and large ones hang forever — a
plausible-looking "the detector stream stalls after a few seconds" that is
really a 1500-vs-1450 mismatch.

`ping` and `traceroute` both work here without any capability — ping via an
unprivileged ICMP socket, traceroute via its default `IP_RECVERR` method. Still
treat their results as weak evidence: CNIs and NetworkPolicies routinely drop
ICMP while passing TCP happily, so a failed `ping` proves little. **`nc -zv`
against a port you care about is always the stronger test.**

## 7. Capture — not from here

Packet capture needs `CAP_NET_RAW`, and clusters commonly drop that capability
from the bounding set, where nothing inside a pod can recover it. `tcpdump` is
therefore **not** in this image — see `../reference/tools`.

Check what you actually have before assuming:

```bash
capsh --decode=$(grep CapEff /proc/self/status | cut -f2)
```

When you genuinely need the wire, capture at the other end — on the device, on
the node, or in a pod that does hold the capability. In practice steps 0-6
settle almost everything without it.

## EPICS services

Mostly this behaves the same from a netshoot pod as it does from your
workstation, so this is rarely the reason to reach for this tool. The parts
that are specific:

| Protocol | Search | Data |
|---|---|---|
| Channel Access | UDP 5064 | TCP 5064 |
| PV Access | UDP 5076 | TCP 5075 |

With default EPICS settings, **name search is a UDP broadcast**, and broadcast
does not cross the pod network. IOCs at DLS run with `hostNetwork: true` for
exactly this reason, so to search for PVs the same way an IOC does you need:

```bash
netshoot -n i07-beamline --host-network
caget MY:PV:NAME
```

Without `--host-network` you can still talk to a PV if you skip the broadcast
and address the server directly:

```bash
EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_ADDR_LIST=my-ioc.i07-beamline.svc caget MY:PV
EPICS_PVA_NAME_SERVERS=my-ioc.i07-beamline.svc:5075 pvxget MY:PV
```

That distinction matters when triaging: **a `caget` timeout is far more often
an address-list problem than a network fault.** Prove the transport separately
before blaming the network:

```bash
nc -zv my-ioc 5064          # is the CA TCP port reachable at all?
cainfo MY:PV                # which server actually answered?
PVXS_LOG='*=DEBUG' pvxget MY:PV
```
