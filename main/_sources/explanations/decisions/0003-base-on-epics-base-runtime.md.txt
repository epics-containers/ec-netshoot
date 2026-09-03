# 3. Base on epics-base-runtime, not developer

Date: 2026-09-03

## Status

Accepted. Supersedes [2. Base on epics-base-developer](0002-base-on-epics-base-developer.md).

## Context

ADR 0002 chose the developer image and argued the size cost was acceptable
because node layer caching would pay it once. In practice the first pull was
slow enough to be annoying, which is exactly the moment this tool is supposed
to be helping.

Measured compressed sizes:

| Image | Compressed |
|---|---|
| `ec-netshoot:0.1.0` | 465 MB |
| `epics-base-developer:7.0.10ec5` | 425 MB |
| `ubuntu-devcontainer:noble` | 196 MB |
| `epics-base-runtime:7.0.10ec5` | 33 MB |
| `ubuntu:noble` | 28 MB |

So roughly 92% of the image was the developer base, and almost none of what
made it large — `build-essential`, the EPICS source tree, `npm`, `uv`,
oh-my-zsh, `gdb` — has anything to do with network diagnostics.

`epics-base-runtime` is `ubuntu:noble` plus the output of the upstream
`move_runtime.sh`: the stripped `epics-base/bin`, `epics-base/lib`,
`pvxs/bin` and `pvxs/lib`. That is precisely the CA and PVXS **client tools**
and their shared libraries, with `PATH` and `LD_LIBRARY_PATH` already set.

## Decision

Base on `ghcr.io/epics-containers/epics-base-runtime`, still pinned by
`BASE_VERSION`.

Do not hand-copy binaries out of the developer image.

## Consequences

The image drops from 465 MB to roughly 70 MB compressed, of which `kubectl` is
now the single largest component.

Copying binaries by hand was considered and rejected: `caget` and `pvxget` are
dynamically linked against `libca`, `libCom`, `libpvxs` and `libevent_core`,
so a binaries-only copy would mean chasing shared-library dependencies and
re-chasing them on every base bump. The runtime image has already solved that,
is built by the same upstream CI, and stays in step with the developer image
version for version.

`apt` still works and the pod still has egress, which was a requirement — the
image is small, not minimal.

What is lost relative to the developer base: `git`, `gh`, `glab`, `ssh`,
`gdb`, `npm`, `uv`, zsh and oh-my-zsh. None were being used for diagnosis; the
shell is now plain bash. `curl`, `less` and `procps` are installed explicitly
since the runtime base does not carry them.

The runtime base still runs `busybox --install -s`, so the applet symlinks
still shadow `nc` and friends and the removal step in the Dockerfile is still
required.
