#!/usr/bin/env bash
# Install the latest published NetLoom compute agent on Ubuntu amd64.
set +x
set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: sudo bash install.sh [--config /path/to/dashboard-issued.env] [--qemu-bundle /path/to/verified.zip]\n'; }

input=
qemu_bundle=
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --config) [[ $# -ge 2 && -n "$2" ]] || { usage; exit 2; }; input=$2; shift 2 ;;
        --qemu-bundle) [[ $# -ge 2 && -n "$2" ]] || { usage; exit 2; }; qemu_bundle=$2; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
(( EUID == 0 )) || die 'Run this installer with sudo.'
[[ $(dpkg --print-architecture) == amd64 ]] || die 'The customer package requires Ubuntu amd64.'
# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID:-}" == ubuntu && ( "${VERSION_ID:-}" == 24.04 || "${VERSION_ID:-}" == 26.04 ) ]] || die 'This installer supports Ubuntu 24.04 and 26.04 amd64.'
for tool in curl python3 flock; do
    command -v "$tool" >/dev/null || die "Install $tool before running the bootstrap."
done
for path in /usr/local/bin/netloom-node /etc/netloom/node.env /etc/systemd/system/netloom-node.service /run/systemd/system/netloom-node.service; do
    [[ ! -e $path && ! -L $path ]] || die "Manual installation detected at $path. Use its existing update method."
done

umask 077
exec 9>/run/netloom-node-bootstrap.lock
flock -n 9 || die 'Another NetLoom installer is running. Try again when it finishes.'
work=$(mktemp -d)
# APT's unprivileged download user can access the deb. Keep credentials in the private subdirectory.
chmod 0755 "$work"
mkdir -m 0700 "$work/private"
terminal_state=
env_tmp=
cleanup() {
    if [[ -n $terminal_state ]]; then stty "$terminal_state" </dev/tty || true; fi
    if [[ -n $env_tmp ]]; then rm -f -- "$env_tmp"; fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

config=/etc/blocpow/netloom.env
example=/usr/share/doc/netloom-node/node.env.example
staged=$work/private/netloom.env
validate_config() {
    python3 - "$staged" <<'PY'
import json, re, sys, uuid
from pathlib import Path
from urllib.parse import urlsplit

def reject(message):
    raise SystemExit("Node configuration: " + message)

allowed = {"NODE_ID", "NODE_NAME", "CENTRAL_URL", "TRANSPORT", "HEARTBEAT_TOKEN",
           "CONTROL_TOKEN", "MAX_MEMORY_MB", "MAX_VCPUS", "OPERATION_WORKERS", "CONFIGURATION_WORKERS"}
values = {}
try:
    data = Path(sys.argv[1]).read_text(encoding="utf-8")
except (OSError, UnicodeError):
    reject("cannot read the supplied dashboard configuration.")
if len(data) > 65536:
    reject("the supplied configuration is too large.")
for line in data.splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    key, eq, value = line.partition("=")
    name = key.removeprefix("NETLOOM_")
    if not eq or not key.startswith("NETLOOM_") or name not in allowed or name in values:
        reject("paste the dashboard-issued settings, one assignment per line.")
    if value.startswith('"'):
        try:
            value = json.loads(value)
        except ValueError:
            reject("invalid quoted setting.")
    elif any(c in value for c in ['"', "'", "\\"]):
        reject("use the quoting supplied by the dashboard.")
    if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
        reject("invalid setting value.")
    values[name] = value
try:
    identity = values["NODE_ID"]
    if str(uuid.UUID(identity)) != identity.lower():
        raise ValueError
    origin = urlsplit(values["CENTRAL_URL"])
    if (origin.scheme != "https" or not origin.hostname or origin.username is not None
            or origin.password is not None or origin.path not in ("", "/")
            or re.search(r"[?#\s\\]", values["CENTRAL_URL"])):
        raise ValueError
    _ = origin.port
except (KeyError, ValueError):
    reject("expected the assigned node UUID and an HTTPS dashboard origin.")
if values.get("TRANSPORT") != "outbound":
    reject("an outbound registration is required.")
for name in ("HEARTBEAT_TOKEN", "CONTROL_TOKEN"):
    token = values.get(name, "")
    if not re.fullmatch(r"[A-Za-z0-9._~-]{32,1024}", token) or token.startswith("replace-with-"):
        reject("missing or invalid dashboard credentials.")
for name, low, high in [("MAX_MEMORY_MB",64,2**63-1), ("MAX_VCPUS",1,2**63-1),
                         ("OPERATION_WORKERS",1,8), ("CONFIGURATION_WORKERS",1,8)]:
    if name in values and (not re.fullmatch(r"[0-9]{1,19}", values[name]) or not low <= int(values[name]) <= high):
        reject("invalid " + name + ".")
PY
}
if [[ -n $input ]]; then
    [[ -f $input && ! -L $input ]] || die '--config needs a regular file.'
    install -m 0600 -- "$input" "$staged"
    validate_config
fi

[[ ! -L $config && ( ! -e $config || -f $config ) ]] || die "Expected a regular file at $config."
if [[ -f $config && -f $example ]] && cmp -s "$config" "$example"; then
    cp -- "$config" "$work/private/old-template"
fi
if [[ -n $input && -f $config && ! -f $work/private/old-template ]] && ! cmp -s "$config" "$staged"; then
    die "The node already has a different configuration. Manage it explicitly in $config."
fi

repo=HelixEvo/netloom-node-releases
asset=netloom-node_amd64.deb
download() { curl --disable --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 180 --proto '=https' --proto-redir '=https' "$@"; }
download -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$repo/releases/latest" -o "$work/release.json"
verified=$(python3 - "$work/release.json" "$repo" "$asset" <<'PY'
import json, re, sys
from pathlib import Path
try:
    release = json.loads(Path(sys.argv[1]).read_bytes())
    repo, name = sys.argv[2:]
    tag = release["tag_name"]
    if release["draft"] is not False or release["prerelease"] is not False or not re.fullmatch(r"v(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}-[1-9][0-9]*", tag):
        raise ValueError
    [asset] = [a for a in release["assets"] if a["name"] == name]
    if (asset["state"] != "uploaded" or type(asset["size"]) is not int or asset["size"] <= 0
        or not re.fullmatch(r"sha256:[0-9a-f]{64}", asset["digest"])
        or asset["browser_download_url"] != f"https://github.com/{repo}/releases/download/{tag}/{name}"):
        raise ValueError
except (KeyError, TypeError, ValueError):
    raise SystemExit("GitHub has no matching stable NetLoom amd64 package with a SHA-256 digest.")
print(tag, asset["digest"][7:], asset["size"])
PY
)
read -r tag digest size <<< "$verified"
version=${tag#v}
dpkg --compare-versions "$version" ge 0.9.19-1 || die 'Publish NetLoom Node 0.9.19-1 or later before using this installer.'
deb=$work/$asset
download "https://github.com/$repo/releases/download/$tag/$asset" -o "$deb"
chmod 0644 "$deb"
[[ $(stat -c %s "$deb") == "$size" ]] || die 'The package size does not match the release.'
printf '%s  %s\n' "$digest" "$deb" | sha256sum --check --status || die 'The package SHA-256 does not match the release.'
[[ $(dpkg-deb -f "$deb" Package) == netloom-node && $(dpkg-deb -f "$deb" Architecture) == amd64 &&
   $(dpkg-deb -f "$deb" Version) == "$version" ]] || die 'The package metadata does not match the release.'

installed=$(dpkg-query -W -f='${db:Status-Status} ${Version}' netloom-node 2>/dev/null || true)
read -r status old_version <<< "$installed"
if [[ -n $old_version && $status != config-files ]] && dpkg --compare-versions "$old_version" gt "$version"; then
    die "Installed version $old_version is newer than $version; refusing to downgrade."
fi
if [[ $status != installed || $old_version != "$version" ]]; then
    (umask 022; apt-get update && apt-get install --yes --no-remove "$deb")
else
    printf 'NetLoom Node %s is already installed.\n' "$version"
fi

# Package postinst does not start the node. Verify/install the host runtime before
# configuring a fresh node or offering the command to start an existing one.
runtime_helper=/usr/lib/netloom-node/install-qemu-runtime.sh
[[ -f "$runtime_helper" && ! -L "$runtime_helper" ]] || die 'The selected node package does not contain the reviewed QEMU runtime installer. Publish the updated node release first.'
runtime_args=(--install)
if [[ -n "$qemu_bundle" ]]; then runtime_args+=(--bundle "$qemu_bundle"); fi
bash "$runtime_helper" "${runtime_args[@]}"

# Never overwrite live credentials or operator settings, including on a rerun.
[[ -f $config && ! -L $config ]] || die "Package installation did not create a regular $config."
if ! cmp -s "$config" "$example" && ! cmp -s "$config" "$work/private/old-template"; then
    if [[ -n $input ]]; then
        cmp -s "$config" "$staged" || die "Existing configuration at $config was preserved."
    fi
    printf 'Existing configuration and service state preserved. After an upgrade, restart netloom-node during your maintenance window.\n'
    printf 'To enable a previously configured, stopped node, run:\n  sudo systemctl enable --now docker.service openvswitch-switch.service netloom-node.service\n'
    exit 0
fi
if [[ -z $input && -t 0 ]]; then
    terminal_state=$(stty -g </dev/tty)
    stty -echo </dev/tty
    printf 'Paste the complete dashboard-issued node configuration (input hidden). End with a blank line; press Enter alone to defer.\n' >/dev/tty
    : > "$staged"
    while IFS= read -r line </dev/tty && [[ -n $line ]]; do
        printf '%s\n' "$line" >> "$staged"
    done
    unset line
    stty "$terminal_state" </dev/tty
    terminal_state=
fi
if [[ ! -s $staged ]]; then
    printf 'Installed NetLoom Node %s. Edit %s, then run:\n  sudo systemctl enable --now docker.service openvswitch-switch.service netloom-node.service\n' "$version" "$config"
    exit 0
fi
validate_config
env_tmp=$(mktemp /etc/blocpow/.netloom-env.XXXXXXXX)
install -o root -g root -m 0600 -- "$staged" "$env_tmp"
if ! cmp -s "$config" "$example" && ! cmp -s "$config" "$work/private/old-template"; then
    die "The configuration changed during setup. Existing settings were preserved."
fi
mv -T -- "$env_tmp" "$config"
env_tmp=
systemctl enable --now docker.service openvswitch-switch.service netloom-node.service
printf 'NetLoom Node %s started. Check Online status and image inventory in the dashboard.\n' "$version"

