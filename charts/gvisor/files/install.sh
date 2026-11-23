#!/bin/bash
set -euo pipefail

# After a restart of the node, the node has gVisor already.
if grep -qE '^\s*\[plugins\..*\.containerd\.runtimes\.runsc\]' "$CONTAINERD_CONFIG"; then
  exit 0
fi

# The plugin name in the table of runc depends on the containerd version. The table of runsc needs the same name.
if ! runc="$(grep -m 1 -E '^\s*\[plugins\..*\.containerd\.runtimes\.runc\]' "$CONTAINERD_CONFIG")"; then
  echo "$CONTAINERD_CONFIG does not contain a table for the runtime runc" >&2
  exit 1
fi

url="https://storage.googleapis.com/gvisor/releases/release/$GVISOR_VERSION/$(uname -m)"

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cd "$dir"
curl -fsSLO --retry 5 --retry-all-errors "$url/gvisor.tar.zstd"
curl -fsSLO --retry 5 --retry-all-errors "$url/gvisor.tar.zstd.sha512"
sha512sum -c gvisor.tar.zstd.sha512
tar --zstd -xf gvisor.tar.zstd -C /usr/local/bin

printf '\n%s\nruntime_type = "io.containerd.runsc.v1"\n' "$(sed -E 's/^\s*//; s/runtimes\.runc\].*$/runtimes.runsc]/' <<<"$runc")" >>"$CONTAINERD_CONFIG"

systemctl restart containerd
