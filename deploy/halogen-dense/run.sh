#!/usr/bin/env bash
# Run on EVO-X2 Ubuntu after the approved Dense bootstrap and Flash shutdown.
set -euo pipefail

fail() { printf 'halogen-dense: %s\n' "$*" >&2; exit 1; }

[[ -r /etc/os-release ]] || fail 'Ubuntu is required.'
. /etc/os-release
[[ ${ID:-} == ubuntu ]] || fail 'Ubuntu is required.'
[[ $(id -u) != 0 ]] || fail 'Run as the configured rootless Podman user.'
for command in podman ss mountpoint systemctl; do
    command -v "$command" >/dev/null || fail "Missing command: $command"
done

image=ghcr.io/peonist-ai/halogen:0.1.4
models=/srv/llm/models/halogen-dense
mountpoint -q /srv/llm || fail '/srv/llm must be mounted.'
[[ $(systemctl --user show halogen-active.service -p LoadState --value) == loaded ]] || \
    fail 'The existing Flash service must be available for inspection.'
[[ $(systemctl --user show halogen-active.service -p ActiveState --value) == inactive ]] || \
    fail 'Flash must already be normally stopped; this script does not stop it.'
[[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]] || \
    fail 'Rootless Podman is required.'
existing=$(podman ps -a --filter 'name=^(halogen-flash|halogen-dense|halogen-dense-bootstrap)$' --format '{{.Names}}')
[[ -z "$existing" ]] || fail 'A Flash or Dense container already exists; leave it unchanged.'
listeners=$(ss -H -ltn 'sport = :8732')
[[ -z "$listeners" ]] || fail 'TCP port 8732 is already in use; leave it unchanged.'
podman image exists "$image" || fail 'The approved Dense image must already be pulled.'
for file in qwen3.8-27b-p1w4d-d2.hgn tokenizer/tokenizer.json \
            tokenizer/tokenizer_config.json tokenizer/chat_template.jinja; do
    [[ -r "$models/$file" && -s "$models/$file" ]] || fail "Missing Dense model file: $file"
done
[[ -r /dev/kfd && -w /dev/kfd ]] || fail 'KFD read/write access is required.'
render_nodes=(/dev/dri/renderD*)
[[ -e ${render_nodes[0]} ]] || fail 'No DRM render node is available.'
for node in "${render_nodes[@]}"; do
    [[ -r "$node" && -w "$node" ]] || fail "No read/write access: $node"
done
[[ $(ulimit -S -l) == unlimited && $(ulimit -H -l) == unlimited ]] || \
    fail 'Start from an SSH login with unlimited memlock.'

exec podman run -d --rm --pull=never --name halogen-dense \
    -p 0.0.0.0:8732:8731 \
    --device /dev/kfd --device /dev/dri --group-add keep-groups \
    --security-opt seccomp=unconfined --ipc=host --ulimit memlock=-1:-1 \
    -e HALOGEN_CHECKPOINT=/models/qwen3.8-27b-p1w4d-d2.hgn \
    -e HALOGEN_TOKENIZER=/tokenizer \
    -v "$models:/models:ro" -v "$models/tokenizer:/tokenizer:ro" \
    "$image"
