#!/usr/bin/env bash
# Run on EVO-X2 Ubuntu after completing the approved bootstrap download.
set -euo pipefail

fail() { printf 'halogen-flash: %s\n' "$*" >&2; exit 1; }

[[ -r /etc/os-release ]] || fail 'Ubuntu is required.'
. /etc/os-release
[[ ${ID:-} == ubuntu ]] || fail 'Ubuntu is required.'
[[ $(id -u) != 0 ]] || fail 'Run as the configured rootless Podman user.'
for command in podman ss mountpoint; do
    command -v "$command" >/dev/null || fail "Missing command: $command"
done

image=ghcr.io/peonist-ai/halogen-flash-server:0.20.1
image_id=b0973fd66e5aa886b54cfaf2e4ad976b8d56ad2a2640221beec8dc920ade6e37
models=/srv/llm/models/halogen-flash
mountpoint -q /srv/llm || fail '/srv/llm must be mounted.'
for file in qwen38-flash-next-v2.hgn qwen38-flash-next-ngram.hgn \
            tokenizer/tokenizer.json tokenizer/tokenizer_config.json \
            tokenizer/chat_template.jinja; do
    [[ -r "$models/$file" && -s "$models/$file" ]] || fail "Missing model file: $file"
done
[[ -r /dev/kfd && -w /dev/kfd ]] || fail 'KFD read/write access is required.'
render_nodes=(/dev/dri/renderD*)
[[ -e ${render_nodes[0]} ]] || fail 'No DRM render node is available.'
for node in "${render_nodes[@]}"; do
    [[ -r "$node" && -w "$node" ]] || fail "No read/write access: $node"
done
[[ $(ulimit -S -l) == unlimited && $(ulimit -H -l) == unlimited ]] || \
    fail 'Start from a new SSH login with unlimited memlock.'
[[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]] || \
    fail 'Rootless Podman is required.'
[[ $(podman image inspect "$image" --format '{{.Id}}') == "$image_id" ]] || \
    fail 'The local image must match the approved Flash server image ID.'

existing=$(podman ps -a --filter 'name=^(halogen-flash|halogen-flash-uncensored|halogen-dense|halogen-dense-bootstrap)$' --format '{{.Names}}')
[[ -z "$existing" ]] || fail 'A Halogen model container already exists.'
listeners=$(ss -H -ltn '( sport = :8731 or sport = :8732 or sport = :8733 )')
[[ -z "$listeners" ]] || fail 'A Halogen model port is already in use.'

exec podman run -d --rm --pull=never --name halogen-flash \
    -p 127.0.0.1:8731:8731 \
    --device /dev/kfd --device /dev/dri --group-add keep-groups \
    --ipc=host --ulimit memlock=-1:-1 \
    -e HALOGEN_CHECKPOINT=/models/qwen38-flash-next-v2.hgn \
    -v "$models:/models:ro" \
    "$image"
