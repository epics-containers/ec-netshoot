[![CI](https://github.com/epics-containers/ec-netshoot/actions/workflows/ci.yml/badge.svg)](https://github.com/epics-containers/ec-netshoot/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

# ec-netshoot

Network diagnostics for EPICS services in Kubernetes.

A container image and a launcher script for answering "can this thing reach
that thing" from inside a Kubernetes namespace — with the good versions of
`nc`, `dig`, `ss` and `tracepath`, a `ping` that works without privilege
elevation, `kubectl`, and the EPICS tools (`caget`, `pvxget`) that let you
check a service the way an IOC would.

Source          | <https://github.com/epics-containers/ec-netshoot>
:---:           | :---:
Docker          | `docker run ghcr.io/epics-containers/ec-netshoot:latest`
Documentation   | <https://epics-containers.github.io/ec-netshoot>
Releases        | <https://github.com/epics-containers/ec-netshoot/releases>

## Quick Start

```bash
cd $HOME/bin
curl -O https://raw.githubusercontent.com/epics-containers/ec-netshoot/main/netshoot
chmod +x netshoot

netshoot -n i07-beamline
```

Then:

```bash
nc -zv my-ioc 5064
```

<!-- README only content. Anything below this line won't be included in index.md -->

See <https://epics-containers.github.io/ec-netshoot> for the full
documentation, including the ladder to work down when something in a namespace
cannot reach something else, and how to tell a broken device from a cluster
that is in the way.
