# Design Notes

Why this exists in the shape it does. Most of this is here because the
reasoning is not obvious from the code, and without it the next person will
reasonably "simplify" something load-bearing back out.

## Why not just use netshoot?

[`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) is the standard
answer for network debugging in Kubernetes, and most of this image is the same
idea. Two differences justify a separate thing:

- **EPICS.** `caget`, `cainfo`, `pvxget` and `pvxinfo` are the only tools that
  exercise CA and PVA the way an IOC does. "The TCP port is open but `caget`
  times out" is a real and common state, and no generic tool will tell you
  about it.
- **A launcher that knows about the awkward bits.** The pod spec needed to make
  `ping` work unprivileged, to keep DNS working under `hostNetwork`, and to get
  a ServiceAccount token mounted, is not something anyone wants to retype
  during an incident.

## Why not `kubectl debug`?

`kubectl debug --target` attaches an ephemeral container to an existing pod,
sharing its network namespace. That is genuinely better when the question is
"what does *this specific pod* see". It is no help when the question is "can
anything in this namespace reach that device", because there may be no pod to
attach to — or the pod you would attach to is the one that is crash-looping.

The two are complementary. Reach for `kubectl debug` when you have a live pod
whose exact view you need; reach for `netshoot` when you need a vantage point.

## Making ping work without privilege

There are only two ways a process gets ICMP echo on Linux:

1. **`SOCK_RAW`**, which needs `CAP_NET_RAW`. Ubuntu ships `/usr/bin/ping`
   with the `cap_net_raw+ep` *file* capability rather than setuid. That works
   in a default pod, but see the trap below.
2. **`SOCK_DGRAM` with `IPPROTO_ICMP`**, which needs **no capability at all**.
   It is gated only on the netns sysctl `net.ipv4.ping_group_range` covering
   the process's GID. Modern `iputils-ping` tries this first and only falls
   back to raw. The default is `1 0` — an empty range — so it fails in a pod.

The lever is that **`net.ipv4.ping_group_range` is on Kubernetes' *safe*
sysctl list**. Safe sysctls are namespaced per-pod, need no kubelet flag, and
are permitted under both the baseline and restricted Pod Security Standards.
So the launcher sets:

```json
"securityContext": {"sysctls": [
  {"name": "net.ipv4.ping_group_range", "value": "0 2147483647"}
]}
```

and `ping` works with no capability, non-root, under `drop: ALL`.

### The trap: `+ep` breaks exec, not just the socket

The file capability is not merely useless when capabilities are unavailable —
it is actively harmful. The **effective** bit in `cap_net_raw+ep` means that if
the kernel cannot grant the process the capability, `execve` fails outright with
`EPERM`. You get

```
bash: /usr/bin/ping: Operation not permitted
```

before ping has run at all, so the sysctl never gets a chance to help. This
happens whenever the pod drops capabilities or sets
`allowPrivilegeEscalation: false` (which sets `NoNewPrivs`).

Note the difference from a socket failure, which reads
`ping: socket: Operation not permitted`. One is the shell failing to launch the
program; the other is the program failing to work. They need different fixes.

The image therefore **strips file capabilities from every binary under `/usr`**
and asserts at build time that none remain. Nothing is lost by this: a process
that holds `CAP_NET_RAW` in its effective set — which root does whenever the
runtime grants it — opens a raw socket regardless of file capabilities. The
file capability only ever mattered for unprivileged users, and for those the
sysctl is the better mechanism anyway.

The sysctl lives in the **launcher**, not the Dockerfile — it is a property of
the pod, not of the image.

### Why it is dropped under `--host-network`

The kubelet **rejects** any pod that sets a namespaced `net.*` sysctl together
with `hostNetwork: true`. The two are mutually exclusive at the API level, so
the launcher silently drops the sysctl in that mode and warns. In host-network
mode you inherit the node's `ping_group_range`, which is usually `1 0`, so ping
there falls back to needing `CAP_NET_RAW` from the node's default set.

## Why `tracepath` leads

`tracepath` sends UDP with an incrementing TTL and reads the errors back via
`IP_RECVERR`. **No raw socket, no capability, no sysctl.** Linux `traceroute`
uses the same trick for its default UDP method, so it works too; only its `-I`
and `-T` modes need a raw socket.

That makes both usable under the restricted PSS and in clusters that drop
`CAP_NET_RAW`, and it is why `tracepath` — which also reports path MTU, catching
overlay MTU black holes — is the one the documentation leads with.

## Why `nc -zv` and not `ping` as the headline

CNIs and NetworkPolicies routinely drop ICMP while passing TCP without
complaint. A failed `ping` is therefore weak evidence, and acting on it sends
people to investigate a network that is fine. A TCP connect to the port you
actually care about tests the thing you actually care about.

`ping` is still installed, and still useful, but the docs treat it as
corroboration rather than proof.

## The busybox PATH problem

The base image runs `busybox --install -s`, which scatters applet symlinks for
`nc`, `ping`, `traceroute`, `nslookup` and `ip` across the PATH.
**busybox's `nc` has no `-z`** — so if it wins the PATH race, the headline
feature of this image is silently gone.

The Dockerfile removes the busybox symlinks for exactly those applets where a
real tool is installed, leaving the rest of busybox intact, and then asserts
`nc -h` mentions `-z` at build time. That assertion is the reason the failure
cannot reach you.

## Identity: kubectl inside the pod is not you

`kubectl run` binds the pod to the namespace's `default` ServiceAccount.
Inside the pod, kubectl picks up in-cluster config and authenticates as
`system:serviceaccount:<ns>:default`. Your own credentials stay on your
workstation.

Whether that is useful depends on the namespace's RBAC. At DLS the beamline
RoleBindings include the `default` ServiceAccount alongside the human users, so
in-pod `kubectl` has the namespace role and the reads in the how-to guides
work. Elsewhere it may have nothing, and `--service-account` selects a
different one.

**Copying your kubeconfig into the pod is an explicit non-goal.** It would
write a live OIDC token onto a shared node, readable by anyone who can exec
into the namespace, and it would expire mid-session. If the ServiceAccount
cannot do what you need, that is RBAC working; use `--service-account`, or run
the query from your workstation.

### `automountServiceAccountToken`

The launcher sets `automountServiceAccountToken: true` on the pod
unconditionally. Some sites disable automount on the `default` ServiceAccount,
which would give the pod the RBAC but no token to authenticate with. The
**pod-level** field overrides the ServiceAccount's, so setting it here works
either way and avoids hard-coding site-specific ServiceAccount names.

## `hostNetwork` implies a DNS policy

`--host-network` also sets `dnsPolicy: ClusterFirstWithHostNet`. Without it the
pod inherits the node's `/etc/resolv.conf`, cluster DNS disappears, and every
`svc.cluster.local` lookup fails — which looks exactly like the bug you are
hunting. It is never correct to set one without the other.

## What `--keep` means

Plain `kubectl run -ti` with a shell as PID 1 does not survive you exiting the
shell, so "keep" would not keep. Instead `--keep` creates the pod detached
running `sleep infinity`, then execs a shell into it. Exiting leaves the pod
alive, several shells can share it, and re-running `netshoot` attaches to the
existing pod rather than replacing it.

Without `--keep` the pod is created with `--rm` and dies with your session —
and any pod left behind by a dropped terminal is deleted first, so a broken
connection never blocks the next run.

## Running as root

The pod runs as root on purpose: being able to `apt install` something
unanticipated halfway through an incident matters more than the principle, and
packet-adjacent tools generally want it. The image is small (see
[ADR 0003](decisions/0003-base-on-epics-base-runtime.md)) but not minimal, precisely so that
escape hatch exists.

Root is the first thing that breaks if these namespaces are ever labelled
`restricted`. Everything else would survive — every tool in the image works
with no capability at all.

## Rejected

- **A slim variant.** Pull latency did bite, so rather than publish two images
  the single image was made small — `epics-base-runtime` instead of the
  developer image, 465 MB down to roughly 70 MB. See
  [ADR 0003](decisions/0003-base-on-epics-base-runtime.md).
- **Hand-copying EPICS binaries into `ubuntu:noble`.** `caget` and `pvxget` are
  dynamically linked against `libca`, `libCom`, `libpvxs` and `libevent_core`,
  so this means chasing shared libraries and re-chasing them on every base
  bump. `epics-base-runtime` is that job already done, upstream.
- **A Helm chart.** This is never deployed; it is `kubectl run`-ed.
- **`nmap`.** See [Reach a Device From a Namespace](../how-to/reach-a-device.md).
- **Tests and a `:edge` tag.** The Dockerfile's build-time assertions cover the
  claims that could break silently. Everything else is better learned by
  using it.
