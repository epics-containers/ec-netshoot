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

# Empty means "resolve the current stable release at build time". Set it to
# pin, e.g. when the cluster falls outside kubectl's +/-1 minor version skew.
ARG KUBECTL_VERSION=""
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="ec-netshoot" \
      org.opencontainers.image.description="Network diagnostics container for EPICS services in Kubernetes" \
      org.opencontainers.image.source="https://github.com/epics-containers/ec-netshoot" \
      org.opencontainers.image.licenses="Apache-2.0" \
      io.epics-containers.base-version="${BASE_VERSION}"

# Tier 1 - work with no capabilities at all, so they survive even under the
# restricted Pod Security Standard. These are the tools the docs lead with.
#   netcat-openbsd     nc -zv, and port ranges: nc -zv moxa1 4000-4010
#   socat              relays, UDP probes, unix sockets
#   bind9-dnsutils     dig / host - cluster DNS and upstream resolution
#   iproute2           ss -tulpn and the real ip(8)
#   iputils-tracepath  the only path trace needing no raw socket (UDP + IP_RECVERR)
#   openssl            s_client, for TLS and certificate problems
#   jq                 for kubectl -o json
#   libcap2-bin        getcap/setcap - lets you check in-pod what you are allowed to do
#
# Tier 2 - best effort. These need CAP_NET_RAW, which is in the container
# runtime's default set today but is dropped by the restricted PSS.
#   iputils-ping iputils-arping traceroute mtr-tiny tcpdump
#
# Tier 3 - throughput, for detector data-rate questions. Needs ec-netshoot
# at both ends: run one with --keep as the server.
#   iperf3
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        bind9-dnsutils \
        iperf3 \
        iproute2 \
        iputils-arping \
        iputils-ping \
        iputils-tracepath \
        jq \
        libcap2-bin \
        mtr-tiny \
        netcat-openbsd \
        openssl \
        socat \
        tcpdump \
        traceroute && \
    rm -rf /var/lib/apt/lists/*

# The base image runs `busybox --install -s`, which scatters applet symlinks
# for nc, ping, traceroute, nslookup, ip and arping across the PATH. busybox's
# nc in particular has no -z, so if it wins the PATH race the headline feature
# of this image silently disappears. Remove the shadows where we now ship the
# real tool, and leave the rest of busybox alone.
RUN for applet in nc ping ping6 traceroute traceroute6 nslookup ip arping; do \
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

# Ubuntu ships /usr/bin/ping with the cap_net_raw file capability rather than
# setuid. BuildKit preserves the security.capability xattr, but assert it
# rather than discover at 2am that a base image change dropped it.
#
# This block plus the next are build-time assertions, not a test suite. They
# cost nothing and they guard the two things that would otherwise break
# silently. Delete them if you disagree.
RUN getcap /usr/bin/ping | grep -q cap_net_raw || setcap cap_net_raw+ep /usr/bin/ping

RUN nc -h 2>&1 | grep -q -- '-z' || { echo "FATAL: nc has no -z; busybox won the PATH race" >&2; exit 1; } && \
    for tool in dig ss socat tracepath iperf3 tcpdump openssl jq kubectl caget pvxget; do \
        command -v "${tool}" >/dev/null || { echo "FATAL: ${tool} missing" >&2; exit 1; }; \
    done
