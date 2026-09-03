# Quick Start

## Get the launcher

```bash
cd $HOME/bin
curl -O https://raw.githubusercontent.com/epics-containers/ec-netshoot/main/netshoot
chmod +x netshoot
```

Its only dependency is `kubectl` and a working kubeconfig.

:::{note}
If you do not have a `$HOME/bin`, `mkdir $HOME/bin` — it is added to your PATH
in new shells, though not in the one you are in.
:::

## Open a shell in a namespace

```bash
netshoot -n i07-beamline
```

The pod is created, you land in a shell inside it, and when you exit the pod is
deleted. The first run on a node pulls the image, which takes a while; after
that it is cached.

It tells you where it put the pod before creating it — worth reading, since
landing in the wrong namespace is the easiest mistake to make here:

```
netshoot: namespace i07-beamline, pod netshoot-abc12345, image ghcr.io/epics-containers/ec-netshoot:latest
```

## The first useful command

```bash
nc -zv my-ioc 5064
```

`-z` connects and immediately disconnects, `-v` says what happened. This is the
single most useful probe in the image and the one the guides keep coming back
to. **Connection refused** means the path is fine and nothing is listening;
**timeout** means something dropped it.

Try a couple more:

```bash
nslookup my-ioc                     # does the name resolve, and to what
ss -tulpn                           # what is listening in here
tracepath my-ioc                    # where the path goes, and the MTU
kubectl get pods                    # as the pod's ServiceAccount, not as you
```

## One-shot

You do not need an interactive shell for a single check:

```bash
netshoot -n i07-beamline -c 'nc -zv my-ioc 5064'
```

## Where next

- `../how-to/debug-namespace-networking` — the ladder to work down when
  something in the namespace cannot reach something else
- `../how-to/reach-a-device` — when an IOC cannot see its hardware
- `../reference/cheatsheet` — the page to paste from
