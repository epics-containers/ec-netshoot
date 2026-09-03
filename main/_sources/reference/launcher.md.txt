# Launcher Reference

`netshoot` is a bash script whose only dependency is `kubectl` and a working
kubeconfig. It builds a pod spec and hands it to `kubectl run`.

```bash
curl -O https://raw.githubusercontent.com/epics-containers/ec-netshoot/main/netshoot
chmod +x netshoot
```

## Options

| Option | Default | Notes |
|---|---|---|
| `-n`, `--namespace NS` | current context | Resolved and echoed before the pod is created |
| `--node NAME` | none | Verbatim. Sets `nodeName`, bypassing the scheduler and therefore taints |
| `-h`, `--host-network` | false | Also sets `dnsPolicy: ClusterFirstWithHostNet`; disables the ping sysctl. **Note `-h` is not help** — use `--help` or `-?` |
| `-k`, `--keep` | false | Pod survives your session; re-running attaches to it |
| `--delete` | — | Delete the pod and exit |
| `--name NAME` | `netshoot-$USER` | Sanitised to a valid RFC1123 label. Lets you run two at once |
| `--service-account N` | `default` | For namespaces where the default SA lacks RBAC |
| `--annotation K=V` | none | Repeatable. e.g. `--annotation usb-compat=enabled` |
| `-i`, `--image IMAGE` | `ghcr.io/epics-containers/ec-netshoot` | |
| `-v`, `--version VER` | `latest` | `latest` tracks the most recent release tag |
| `-c`, `--command 'CMD'` | interactive | One-shot; useful in scripts |
| `--print` | — | Print the manifest and exit. Contacts no cluster |
| `--no-sysctl` | false | For admission policies that reject `securityContext.sysctls` |

## Environment

| Variable | Effect |
|---|---|
| `NETSHOOT_REQUESTS` | e.g. `100m/128Mi`. Adds CPU/memory requests, for namespaces with a `LimitRange` that requires them |

## What it puts in the pod spec

```json
{
  "apiVersion": "v1",
  "spec": {
    "automountServiceAccountToken": true,
    "securityContext": {"sysctls": [
      {"name": "net.ipv4.ping_group_range", "value": "0 2147483647"}
    ]}
  }
}
```

plus `nodeName`, `hostNetwork` + `dnsPolicy`, `serviceAccountName`,
annotations and resource requests when the corresponding options are given.
`--print` shows the whole thing.

Each of those is doing something specific and non-obvious; see
[the design notes](../explanations/design.md).

## Exit behaviour

Without `--keep` the pod is created with `--rm` and removed when you exit. Any
pod of the same name left behind by a dropped terminal is deleted first, so a
lost connection never blocks the next run.

With `--keep` the pod runs `sleep infinity` and stays until `--delete`.
