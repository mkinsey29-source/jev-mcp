#!/usr/bin/env bash
# Install a Jev runtime inside the existing Debian proot and create a dedicated
# OpenAI Secure MCP Tunnel profile. Run this from Termux on the tablet.
set -Eeuo pipefail

tunnel_id=${1:-}
profile=${JEV_TUNNEL_PROFILE:-jev-tablet}
debian_name=${JEV_DEBIAN_NAME:-debian}
tunnel_dir=${JEV_TUNNEL_DIR:-"$HOME/replicator-tunnel"}
tunnel_bind_target=${JEV_TUNNEL_BIND_TARGET:-/opt/jev-tunnel}

usage() {
  cat <<'EOF'
Usage: install-jev-tablet.sh TUNNEL_ID

Run in Termux after creating a dedicated Jev tunnel in OpenAI Platform.
The script reuses the tunnel-client already installed for Replicator, installs
Node 22 + @jkudish/jev-mcp inside the existing Debian proot, and creates the
separate "jev-tablet" tunnel profile.

It does not ask for or store either the OpenAI control-plane key or the TypeSafe
API key. Those are entered only when jev-start is launched.
EOF
}

if [[ -z "$tunnel_id" ]]; then
  usage >&2
  exit 2
fi

command -v proot-distro >/dev/null 2>&1 || {
  printf 'proot-distro is not installed in Termux.\n' >&2
  exit 2
}
[[ -x "$tunnel_dir/tunnel-client" ]] || {
  printf 'Tunnel client not found at %s/tunnel-client\n' "$tunnel_dir" >&2
  printf 'This setup expects the tunnel client already used by Replicator Tablet.\n' >&2
  exit 2
}

printf 'Installing Jev runtime inside Debian...\n'
proot-distro login "$debian_name" \
  --bind "$tunnel_dir:$tunnel_bind_target" \
  -- /bin/bash -s -- "$tunnel_bind_target" "$profile" "$tunnel_id" <<'DEBIAN'
set -Eeuo pipefail

tunnel_bind_target=$1
profile=$2
tunnel_id=$3
runtime_root=/opt/jev-runtime
node_root="$runtime_root/node"
package_root="$runtime_root/package"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl xz-utils

case "$(uname -m)" in
  aarch64|arm64) node_arch=arm64 ;;
  x86_64|amd64) node_arch=x64 ;;
  *)
    printf 'Unsupported Debian architecture for the prepared Node runtime: %s\n' "$(uname -m)" >&2
    exit 2
    ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sums="$tmp/SHASUMS256.txt"
curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt -o "$sums"
archive=$(awk -v a="linux-$node_arch.tar.xz" '$2 ~ a"$" {print $2; exit}' "$sums")
if [[ -z "$archive" ]]; then
  printf 'Could not resolve the latest Node 22 archive for %s.\n' "$node_arch" >&2
  exit 2
fi
curl -fsSL "https://nodejs.org/dist/latest-v22.x/$archive" -o "$tmp/$archive"
(
  cd "$tmp"
  grep "  $archive$" SHASUMS256.txt | sha256sum -c -
)

mkdir -p "$runtime_root"
rm -rf "$node_root" "$runtime_root/node-new"
mkdir -p "$runtime_root/node-new"
tar -xJf "$tmp/$archive" -C "$runtime_root/node-new" --strip-components=1
mv "$runtime_root/node-new" "$node_root"

export PATH="$node_root/bin:$PATH"
node --version
npm --version
rm -rf "$package_root"
mkdir -p "$package_root"
npm install --prefix "$package_root" @jkudish/jev-mcp@latest

jev_entry="$package_root/node_modules/@jkudish/jev-mcp/dist/index.js"
[[ -f "$jev_entry" ]] || {
  printf 'Jev MCP entrypoint was not installed where expected: %s\n' "$jev_entry" >&2
  exit 2
}

mcp_command="$node_root/bin/node $jev_entry"
"$tunnel_bind_target/tunnel-client" init \
  --sample sample_mcp_stdio_local \
  --profile "$profile" \
  --tunnel-id "$tunnel_id" \
  --mcp-command "$mcp_command"

printf '\nJev tablet runtime installed.\n'
printf 'Profile: %s\n' "$profile"
printf 'MCP command: %s\n' "$mcp_command"
printf 'Next: run jev-start from Termux and enter the two keys privately when prompted.\n'
DEBIAN
