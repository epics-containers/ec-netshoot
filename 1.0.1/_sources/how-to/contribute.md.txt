# Contribute

Issues and pull requests are welcome at
<https://github.com/epics-containers/ec-netshoot>.

The repo is deliberately small: a `Dockerfile`, the `netshoot` launcher, and
`docs/`. There is no python package, no `pyproject.toml` and no test suite —
the Dockerfile carries build-time assertions for the two things that could
break silently, and everything else is verified by using it.

## Building the image

```bash
podman build -t ec-netshoot .
podman run --rm -it ec-netshoot bash
```

The build fails if `nc` has no `-z` (which would mean busybox won the PATH
race) or if any expected tool is missing. That is intentional — see
[the design notes](../explanations/design.md).

To build against a different base or pin kubectl:

```bash
podman build --build-arg BASE_VERSION=7.0.10ec5 --build-arg KUBECTL_VERSION=v1.31.0 -t ec-netshoot .
```

## The launcher

`netshoot` is bash, and its only dependency is `kubectl`. Run `shellcheck` over
it before opening a PR:

```bash
pre-commit install
pre-commit run --all-files
```

`netshoot --print` renders the pod manifest without contacting a cluster, which
is the quickest way to check a change to the spec.

## Building the docs

```bash
python -m venv .venv-docs
.venv-docs/bin/pip install -r docs/requirements.txt
.venv-docs/bin/sphinx-build -EW --keep-going -T docs build/html
```

For a live-reloading preview, `sphinx-autobuild docs build/html`.

## Releasing

CI publishes the image and the docs **on a tag only**, so `latest` always
equals the most recent release. Tag with semver:

```bash
git tag 1.0.0 && git push origin 1.0.0
```
