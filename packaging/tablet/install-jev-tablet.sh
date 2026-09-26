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

The OpenAI control-plane API key is requested with hidden input for profile
creation and is not written to disk. The TypeSafe API key is not needed until
jev-start is launched.
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

if [[ -z ${CONTROL_PLANE_API_KEY:-} ]]; then
  [[ -t 0 ]] || {
    printf 'CONTROL_PLANE_API_KEY is required; run from an interactive Termux terminal.\n' >&2
    exit 2
  }
  printf 'OpenAI tunnel control-plane API key: ' >&2
  IFS= read -r -s CONTROL_PLANE_API_KEY
  printf '\n' >&2
fi
if [[ -z "$CONTROL_PLANE_API_KEY" ]]; then
  printf 'No control-plane key was entered. Nothing was changed.\n' >&2
  exit 2
fi

runtime_dir=$(mktemp -d "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/jev-install.XXXXXX")
chmod 700 "$runtime_dir"
cleanup() {
  unset CONTROL_PLANE_API_KEY
  rm -rf "$runtime_dir"
}
trap cleanup EXIT INT TERM HUP

cat >"$runtime_dir/install-inside-debian.sh" <<'DEBIAN'
#!/usr/bin/env bash
set -Eeuo pipefail

tunnel_bind_target=$1
profile=$2
tunnel_id=$3
runtime_root=/opt/jev-runtime
node_root="$runtime_root/node"
package_root="$runtime_root/package"

IFS= read -r CONTROL_PLANE_API_KEY
export CONTROL_PLANE_API_KEY
exec 0</dev/null

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

"$tunnel_bind_target/tunnel-client" doctor --profile "$profile" --explain

printf '\nJev tablet runtime installed.\n'
printf 'Profile: %s\n' "$profile"
printf 'MCP command: %s\n' "$mcp_command"
printf 'Next: run jev-start from Termux and enter the TypeSafe key privately when prompted.\n'
DEBIAN
chmod 700 "$runtime_dir/install-inside-debian.sh"

printf 'Installing Jev runtime inside Debian and creating tunnel profile "%s"...\n' "$profile"
proot-distro login "$debian_name" \
  --bind "$tunnel_dir:$tunnel_bind_target" \
  --bind "$runtime_dir:/opt/jev-installer" \
  -- /bin/bash /opt/jev-installer/install-inside-debian.sh \
     "$tunnel_bind_target" "$profile" "$tunnel_id" \
  < <(printf '%s\n' "$CONTROL_PLANE_API_KEY")


script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [[ -f "$script_dir/jev-start" ]]; then
  mkdir -p "$HOME/.local/bin"
  cp "$script_dir/jev-start" "$HOME/.local/bin/jev-start"
  chmod 700 "$HOME/.local/bin/jev-start"
  printf 'Installed launcher: %s/.local/bin/jev-start\n' "$HOME"
fi
