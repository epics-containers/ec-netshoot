# ec-netshoot - network diagnostics for EPICS services in Kubernetes.
#
# Based on epics-base-developer so that caget/caput/pvxget are available
# alongside the network tools: the point of this image is to answer
# "can this pod reach that thing", including when "that thing" speaks EPICS.

ARG BASE_IMAGE=ghcr.io/epics-containers/epics-base-developer
# Pinned deliberately. A diagnostics tool that changes under you between
# incidents is a bad diagnostics tool. Bump it on purpose, not by drift.
ARG BASE_VERSION=7.0.10ec5

FROM ${BASE_IMAGE}:${BASE_VERSION}

# ARGs declared before FROM are only visible to FROM; re-declare to use below.
ARG BASE_VERSION

# Empty means "resolve the current stable release at build time". Set it to
# pin, e.g. when the cluster falls outside kubectl's +/-1 minor version skew.
ARG KUBECTL_VERSION=""
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="ec-netshoot" \
      org.opencontainers.image.description="Network diagnostics container for EPICS services in Kubernetes" \
      org.opencontainers.image.source="https://github.com/epics-containers/ec-netshoot" \
      org.opencontainers.image.licenses="Apache-2.0" \
      io.epics-containers.base-version="${BASE_VERSION}"

# Every tool here works with no capabilities at all, so the image is useful
# under any Pod Security Standard and in clusters that drop CAP_NET_RAW.
#   netcat-openbsd     nc -zv, and port ranges: nc -zv moxa1 4000-4010
#   socat              relays, UDP probes, unix sockets
#   bind9-dnsutils     nslookup and dig - cluster DNS and upstream resolution
#   bind9-host         host(1); ships separately and is only a Recommends of
#                      bind9-dnsutils, so name it explicitly
#   iproute2           ss -tulpn and the real ip(8)
#   iputils-tracepath  path trace and path MTU, via UDP + IP_RECVERR
#   traceroute         its default UDP method uses IP_RECVERR too; only -I/-T
#                      need a raw socket
#   iputils-ping       unprivileged SOCK_DGRAM ICMP, given the launcher's sysctl
#   openssl            s_client, for TLS and certificate problems
#   jq                 for kubectl -o json
#   libcap2-bin        getcap/capsh - check in-pod what you are allowed to do
#   iperf3             throughput, with an ec-netshoot at each end
#
# tcpdump, arping and mtr are deliberately absent. They need a raw socket, and
# clusters commonly drop CAP_NET_RAW from the capability bounding set - where
# nothing inside the pod can recover it and the tools only waste your time.
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        bind9-dnsutils \
        bind9-host \
        iperf3 \
        iproute2 \
        iputils-ping \
        iputils-tracepath \
        jq \
        libcap2-bin \
        netcat-openbsd \
        openssl \
        socat \
        traceroute && \
    rm -rf /var/lib/apt/lists/*

# The base image runs `busybox --install -s`, which scatters applet symlinks
# for nc, ping, traceroute, nslookup and ip across the PATH. busybox's
# nc in particular has no -z, so if it wins the PATH race the headline feature
# of this image silently disappears. Remove the shadows where we now ship the
# real tool, and leave the rest of busybox alone.
RUN for applet in nc ping ping6 traceroute traceroute6 nslookup ip; do \
        for dir in /bin /usr/bin /sbin /usr/sbin; do \
            link="${dir}/${applet}"; \
            if [ -L "${link}" ]; then \
                case "$(readlink -f "${link}")" in \
                    */busybox) rm -f "${link}" ;; \
                esac; \
            fi; \
        done; \
    done

# kubectl, so you can ask the API server what it thinks the topology is from
# inside the namespace. Runs as the pod's ServiceAccount, not as you.
RUN arch="$(dpkg --print-architecture)" && \
    version="${KUBECTL_VERSION}" && \
    if [ -z "${version}" ]; then \
        version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"; \
    fi && \
    curl -fsSLo /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl" && \
    chmod +x /usr/local/bin/kubectl && \
    echo "kubectl ${version}" > /etc/ec-netshoot-versions

# `k` as a shortcut. A symlink rather than a shell alias, so it also works
# non-interactively - netshoot -c 'k get pods' and anything scripted.
RUN ln -s /usr/local/bin/kubectl /usr/local/bin/k

# Strip file capabilities from every binary under /usr.
#
# Ubuntu ships /usr/bin/ping with cap_net_raw+ep. The *effective* bit in that
# "+ep" means execve fails outright with EPERM whenever the kernel cannot grant
# the process the capability - which is the case any time the pod drops
# capabilities or sets allowPrivilegeEscalation: false (NoNewPrivs). The
# symptom is
#
#     bash: /usr/bin/ping: Operation not permitted
#
# before the program has run at all, so no amount of sysctl helps.
#
# With no file capability ping execs everywhere and picks its socket at
# runtime: a raw socket if the process holds CAP_NET_RAW, otherwise the
# unprivileged SOCK_DGRAM ICMP socket that the launcher's
# net.ipv4.ping_group_range sysctl enables.
#
# Sweeping rather than naming binaries, so a future package that ships fcaps
# cannot quietly reintroduce the failure. -n1 because setcap reads alternating
# caps/file pairs, so a batched call parses the second path as a capability.
# See docs/explanations/design.md.
RUN getcap -r /usr 2>/dev/null | cut -d' ' -f1 | xargs -r -n1 setcap -r

# Build-time assertions, not a test suite. They cost nothing and they guard the
# things that would otherwise break silently and only show up mid-incident.
RUN nc -h 2>&1 | grep -q -- '-z' || { echo "FATAL: nc has no -z; busybox won the PATH race" >&2; exit 1; } && \
    [ -z "$(getcap -r /usr 2>/dev/null)" ] || { echo "FATAL: file capabilities remain: $(getcap -r /usr 2>/dev/null)" >&2; exit 1; } && \
    for tool in nslookup host dig ss socat tracepath traceroute iperf3 openssl jq kubectl k caget pvxget; do \
        command -v "${tool}" >/dev/null || { echo "FATAL: ${tool} missing" >&2; exit 1; }; \
    done
