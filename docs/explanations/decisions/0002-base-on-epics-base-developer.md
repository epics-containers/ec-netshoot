# 2. Base on epics-base-developer

Date: 2026-09-03

## Status

Superseded by [3. Base on epics-base-runtime, not developer](0003-base-on-epics-base-runtime.md)

## Context

A network diagnostics container for EPICS services in Kubernetes could be
based on several things:

- `nicolaka/netshoot` or an Alpine image built from scratch — small, but musl,
  no EPICS tools, and a parallel toolchain nobody here otherwise maintains
- the `ubuntu-devcontainer` base plus network tools — small-ish, but no
  `caget`/`pvxget`, so it cannot answer "can this pod reach that IOC's PVA port
  *and* does the IOC answer"
- the `epics-base` **runtime** stage plus network tools — has the EPICS tools
  and is much smaller, but loses the shell environment and the ability to
  `apt install` something unanticipated mid-incident
- the `epics-base` **developer** stage — everything, but multiple GB

The size cost is real. A debug pod's job is to appear quickly on an arbitrary
node when something is already broken, and a cold pull of a multi-GB image is
exactly what you do not want at that moment.

## Decision

Base on `ghcr.io/epics-containers/epics-base-developer`, pinned by an
explicit `BASE_VERSION` build argument.

Do not publish a slim variant.

## Consequences

The EPICS tools are the differentiator: without them this is a worse
`netshoot`. `cainfo` telling you which server actually answered, and the
ability to distinguish "the TCP port is open" from "CA is working", is the
reason for the project.

Nodes cache layers, so the pull cost is paid once per node rather than per
invocation, and the set of nodes in play at a facility is small and stable.

Keeping `apt` and a full shell means the pod stays useful when the diagnosis
turns out to need a tool nobody predicted — which for a diagnostics tool is
worth more than a smaller image.

Pinning the base rather than tracking `latest` is deliberate: a diagnostics
tool that changes under you between incidents is a bad diagnostics tool.

A slim variant can be added later if pull latency actually bites. Until then,
one image is one thing to reason about.
