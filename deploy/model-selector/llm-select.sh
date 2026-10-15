#!/usr/bin/env bash
# EVO-X2: one active Quadlet, with its matching stop drop-in. No pending state.
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C.UTF-8
umask 077

base=/srv/llm/engines/model-selector
unit=halogen-active.service
quadlet="$HOME/.config/containers/systemd/halogen-active.container"
dropin="$HOME/.config/systemd/user/$unit.d/90-safe-stop.conf"
generator=/usr/lib/systemd/system-generators/podman-system-generator
gtt_baseline=18661376
gtt_tolerance=16777216 # Allow at most 16 MiB above the measured stopped baseline.
changed=0
safe_stop=0
reboot_accepted=0
backup_q= backup_d= next_q= next_d=

say() { printf 'llm-select: %s\n' "$*"; }
fail() { say "$*" >&2; exit 1; }
value() { systemctl --user show "$unit" --property="$1" --value; }
hash() { sha256sum -- "$1" | cut -d ' ' -f 1; }
qtemplate() { printf '%s/templates/%s/halogen-active.container' "$base" "$1"; }
dtemplate() { printf '%s/templates/%s/halogen-active.service.d/90-safe-stop.conf' "$base" "$1"; }
qhash() {
    case "$1" in
        flash) echo cb6c6357066d68a0a7a8a035c8b61de8950ffa8847665b4bae23689c8ec03446 ;;
        dense) echo 52a90d1a9ed70c95c84f42fd8edefa3cd293ef874ef7d048ed7d9166b67b9466 ;;
        *) return 1 ;;
    esac
}
dhash() {
    case "$1" in
        flash) echo 790f8cc28a2c035c32a9436745bd946f00dc2ea9c088d5c5851cbface958605e ;;
        dense) echo 6586664d17de8b7a888002fcd382012974219c1eb2a1d4517436e22fbfaf35f2 ;;
        *) return 1 ;;
    esac
}
image_id() {
    case "$1" in
        flash) echo 556c3c8179d8a566cc0ec0a7f7f54f9f3cb8b77e7bc4a4175e7c23ae359ad80a ;;
        dense) echo 7f87d073e63491e65fcdce6fb52c2faf2ded22229638f4ed2438096b11cb66c6 ;;
        *) return 1 ;;
    esac
}
image_name() {
    case "$1" in
        flash) echo ghcr.io/peonist-ai/halogen-flash-server:0.18.4 ;;
        dense) echo ghcr.io/peonist-ai/halogen:0.1.4 ;;
        *) return 1 ;;
    esac
}
port() { case "$1" in flash) echo 8731 ;; dense) echo 8732 ;; *) return 1 ;; esac; }
checked_file() {
    [[ -f "$1" && ! -L "$1" ]] &&
        [[ $(stat -c '%u:%a' -- "$1") == "$(id -u):644" ]] &&
        [[ $(hash "$1") == "$2" ]]
}
templates_ok() {
    local model
    for model in flash dense; do
        checked_file "$(qtemplate "$model")" "$(qhash "$model")" || return 1
        checked_file "$(dtemplate "$model")" "$(dhash "$model")" || return 1
    done
}
identify() {
    local model
    for model in flash dense; do
        if checked_file "$quadlet" "$(qhash "$model")" &&
           checked_file "$dropin" "$(dhash "$model")"; then
            echo "$model"
            return 0
        fi
    done
    return 1
}

# Compare every argument; Quadlet's Go maps can reorder independent options.
unit_ok() {
    local model=$1 expected actual stop post wants
    [[ $(value LoadState) == loaded && $(value UnitFileState) == generated ]] || return 1
    [[ $(value SourcePath) == "$quadlet" && $(value DropInPaths) == "$dropin" ]] || return 1
    [[ $(value FragmentPath) == "$XDG_RUNTIME_DIR/systemd/generator/$unit" ]] || return 1
    [[ $(value Restart) == no && $(value NRestarts) == 0 ]] || return 1
    [[ $(value TimeoutStopUSec) == infinity && $(value SendSIGKILL) == no ]] || return 1
    [[ $(value KillMode) == mixed && $(value LimitMEMLOCK) == infinity ]] || return 1
    [[ $(value Type) == notify ]] || return 1
    case "$model" in
        flash) [[ -z $(value SuccessExitStatus) ]] || return 1 ;;
        dense) [[ $(value SuccessExitStatus) == 143 ]] || return 1 ;;
        *) return 1 ;;
    esac
    expected=$(QUADLET_UNIT_DIRS="$base/templates/$model" "$generator" --user --dryrun 2>/dev/null) || return 1
    expected=$(printf '%s\n' "$expected" | sed -n 's/^ExecStart=//p')
    [[ -n "$expected" && "$expected" != *$'\n'* ]] || return 1
    actual=$(value ExecStart) || return 1
    [[ "$actual" == '{ path=/usr/bin/podman ; argv[]='*' ; ignore_errors=no ; '* && "$actual" != *'} {'* ]] || return 1
    actual=${actual#*argv\[\]=}
    actual=${actual%% ; ignore_errors=*}
    python3 -c '
import shlex,sys
def arguments(text):
    a=shlex.split(text)
    assert a[:2] == ["/usr/bin/podman","run"]
    image=a.pop(); a=a[2:]; options=[]
    while a:
        key=a.pop(0)
        if key in ("--replace","--rm","-d") or "=" in key:
            options.append((key,))
        else:
            options.append((key,a.pop(0)))
    return image,sorted(options)
assert arguments(sys.argv[1]) == arguments(sys.argv[2])
' "$expected" "$actual" || return 1
    stop=$(value ExecStop) || return 1
    post=$(value ExecStopPost) || return 1
    [[ "$stop" == "{ path=/usr/bin/podman ; argv[]=/usr/bin/podman stop --ignore --time=-1 halogen-$model ; ignore_errors=no ; "* ]] || return 1
    [[ "$post" == "{ path=/usr/bin/podman ; argv[]=/usr/bin/podman rm --ignore --filter label=io.evox2.halogen.service=halogen-active --filter name=^halogen-$model"'$$ ; ignore_errors=yes ; '* ]] || return 1
    [[ "$stop$post" != *'} {'* ]] || return 1
    wants=$(systemctl --user show default.target --property=Wants --value) || return 1
    [[ " $wants " == *" $unit "* ]] || return 1
    [[ $(readlink "$XDG_RUNTIME_DIR/systemd/generator/default.target.wants/$unit") == "../$unit" ]] || return 1
    systemd-analyze --user --generators=true verify "$unit" || return 1
}

stop_commands_ok() {
    local property record
    # ExecStopPost ignores errors at unit level; check its actual exit separately.
    for property in ExecStop ExecStopPost; do
        record=$(value "$property") || return 1
        [[ "$record" == *' ; code=exited ; status=0 }' &&
           "$record" != *'} {'* && "$record" != *'pid=0 ;'* ]] || return 1
    done
}

gtt() { cat "$gtt_file"; }
gpu_released() {
    local used busy
    used=$(gtt) || return 1
    busy=$(cat "$busy_file") || return 1
    say "GPU確認: GTT=$used bytes / busy=$busy%" >&2
    [[ "$used" =~ ^[0-9]+$ ]] || return 1
    (( used <= gtt_baseline + gtt_tolerance )) || return 1
    [[ "$busy" == 0 ]]
}
empty_runtime() {
    local containers listeners
    containers=$(podman ps -a --format '{{.Names}}') || return 1
    listeners=$(ss -H -ltn '( sport = :8731 or sport = :8732 )') || return 1
    [[ -z "$containers" ]] || { say '停止後もcontainerが存在します。' >&2; return 1; }
    [[ -z "$listeners" ]] || { say '停止後も8731/8732がlistenしています。' >&2; return 1; }
    gpu_released
}
health_idle() {
    # Ubuntu's existing Python stdlib is used only to parse JSON strictly.
    curl --noproxy '*' -fsS --max-time 10 "http://127.0.0.1:$(port "$1")/health" |
        python3 -c '
import json, sys
h=json.load(sys.stdin); m=sys.argv[1]
assert h["status"] == "ok" and h["context"] == 262144
assert h["model"] == ("halogen-qwen3.8-flash-next" if m == "flash" else "halogen-qwen3.8-27b")
assert h["busy"] is False and h["in_flight"] == 0 and h["queued"] == 0
v="0.18.4" if m == "flash" else "0.1.4"
assert h["version"]["api"] == v and h["version"]["engine"] == v and h["version"]["match"] is True
assert h["slots"] == (4 if m == "flash" else 1)
assert h["drafter_default"] == ("mtp" if m == "flash" else "dflash2")
if m == "flash":
    assert h["engine"]["responds"] is True
    assert h["kv_pool_positions"] == 524288 and h["prompt_cache"]["mode"] == 2
' "$1"
}
running_idle() {
    local model=$1 names used expected_gtt
    [[ $(value ActiveState) == active && $(value SubState) == running && $(value Result) == success ]] || return 1
    names=$(podman ps -a --format '{{.Names}}') || return 1
    [[ "$names" == "halogen-$model" ]] || return 1
    podman inspect "halogen-$model" | python3 -c '
import json,sys
c=json.load(sys.stdin)[0]; m,im,p,pid=sys.argv[1:]
s=c["State"]
assert s["Running"] and not any(s[k] for k in ("Paused","Restarting","OOMKilled","Dead"))
assert str(s["ConmonPid"]) == pid and c["Image"] == im
assert c["Config"]["Labels"]["io.evox2.halogen.service"] == "halogen-active"
assert c["HostConfig"]["PortBindings"] == {"8731/tcp":[{"HostIp":"0.0.0.0","HostPort":p}]}
assert c["HostConfig"]["RestartPolicy"]["Name"] == "no"
mounts={v["Destination"]:v for v in c["Mounts"]}
assert mounts["/models"]["Source"] == "/srv/llm/models/halogen-"+m and not mounts["/models"]["RW"]
if m == "dense":
    assert mounts["/tokenizer"]["Source"] == "/srv/llm/models/halogen-dense/tokenizer" and not mounts["/tokenizer"]["RW"]
assert not any(e.startswith("HALOGEN_DOWNLOAD=") for e in c["Config"]["Env"])
' "$model" "$(image_id "$model")" "$(port "$model")" "$(value MainPID)" || return 1
    [[ -n $(ss -H -ltn "sport = :$(port "$model")") ]] || return 1
    local other=flash
    [[ "$model" == flash ]] && other=dense
    [[ -z $(ss -H -ltn "sport = :$(port "$other")") ]] || return 1
    used=$(gtt) || return 1
    expected_gtt=29085544448
    [[ "$model" == dense ]] && expected_gtt=21176967168
    [[ "$used" =~ ^[0-9]+$ ]] || return 1
    (( used >= expected_gtt - 536870912 && used <= expected_gtt + 536870912 )) || return 1
    [[ $(cat "$busy_file") == 0 ]] || return 1
    health_idle "$model"
}

preflight() {
    local model f boot current order first
    templates_ok && [[ $(identify) == "$original" ]] || return 1
    mountpoint -q /srv/llm || return 1
    [[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]] || return 1
    [[ $(loginctl show-user "$(id -u)" --property=Linger --value) == yes ]] || return 1
    [[ $(ulimit -Sl) == unlimited && $(ulimit -Hl) == unlimited ]] || return 1
    for f in /dev/kfd /dev/dri/renderD*; do [[ -r "$f" && -w "$f" ]] || return 1; done
    for model in flash dense; do
        [[ $(podman image inspect "$(image_name "$model")" --format '{{.Id}}') == "$(image_id "$model")" ]] || return 1
        for f in tokenizer/tokenizer.json tokenizer/tokenizer_config.json tokenizer/chat_template.jinja; do
            [[ -r /srv/llm/models/halogen-$model/$f && -s /srv/llm/models/halogen-$model/$f ]] || return 1
        done
    done
    for f in /srv/llm/models/halogen-flash/qwen38-flash-next-{v2,ngram}.hgn \
             /srv/llm/models/halogen-dense/qwen3.8-27b-p1w4d-d2.hgn; do
        [[ -r "$f" && -s "$f" ]] || return 1
    done
    sudo -n true || return 1
    boot=$(sudo -n efibootmgr) || return 1
    [[ "$boot" != *BootNext:* ]] || return 1
    current=$(printf '%s\n' "$boot" | sed -n 's/^BootCurrent: //p')
    order=$(printf '%s\n' "$boot" | sed -n 's/^BootOrder: //p')
    [[ -n "$current" && ${order%%,*} == "$current" ]] || return 1
    printf '%s\n' "$boot" | grep -qi "^Boot$current.*ubuntu" || return 1
    grep -qx 'GRUB_DEFAULT=0' /etc/default/grub || return 1
    [[ -z $(sudo -n grub-editenv list) ]] || return 1
    first=$(sudo -n awk '/^menuentry / {print; exit}' /boot/grub/grub.cfg) || return 1
    [[ "$first" == "menuentry 'Ubuntu' "* ]] || return 1
    unit_ok "$original" && running_idle "$original"
}

cleanup() {
    local rc=$? restored=1 f
    trap - EXIT HUP INT TERM
    set +e
    if (( changed && ! reboot_accepted )); then
        if [[ $(value ActiveState) != inactive ]] || ! empty_runtime; then
            say "復元保留: runtime状態が変化しました。設定を重ねず退避を保持: $backup_q $backup_d" >&2
            exit 1
        fi
        say '切替中断: 旧Quadletと停止設定を対で復元します。' >&2
        # Backups stay in the destination directories, on the same filesystems.
        mv -fT -- "$backup_q" "$quadlet" || restored=0
        mv -fT -- "$backup_d" "$dropin" || restored=0
        if (( restored )) && [[ $(identify) == "$original" ]]; then
            systemctl --user daemon-reload || restored=0
            unit_ok "$original" || restored=0
        else
            restored=0
        fi
        if (( ! restored )); then
            say "復元失敗。再起動/別モデル起動は禁止。退避: $backup_q $backup_d" >&2
            exit 1
        fi
    fi
    if (( rc != 0 && safe_stop && ! reboot_accepted )); then
        if [[ $(value ActiveState) == inactive && $(identify) == "$original" ]] &&
           empty_runtime && unit_ok "$original"; then
            say 'GPU解放と旧設定を確認。旧モデルの起動を1回試みます。' >&2
            systemctl --user start "$unit" || say '旧モデル起動失敗。再試行せず確認してください。' >&2
        else
            say '旧モデルの起動条件が不成立。停止状態を保って確認してください。' >&2
        fi
    fi
    for f in "$backup_q" "$backup_d" "$next_q" "$next_d"; do
        [[ -z "$f" ]] || rm -f -- "$f"
    done
    exit "$rc"
}
trap cleanup EXIT
trap 'fail "端末切断または割込み。切替を中断します。"' HUP INT TERM

[[ $# == 0 || ( $# == 1 && $1 == --show ) ]] || fail 'Usage: llm-select [--show]'
[[ $(id -u) != 0 ]] || fail '既存のrootless Podmanユーザーで実行してください。'
. /etc/os-release
[[ $ID == ubuntu ]] || fail 'Ubuntu専用です。'
[[ "$HOME" == "$(getent passwd "$(id -u)" | cut -d : -f 6)" ]] || fail 'HOMEが実ユーザーと不一致です。'
[[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]] || fail 'ユーザーruntimeがありません。'
[[ ${XDG_CONFIG_HOME:-$HOME/.config} == "$HOME/.config" ]] || fail '標準外XDG_CONFIG_HOMEは未対応です。'
for command in whiptail flock podman systemctl systemd-analyze curl python3 sha256sum ss sudo; do
    command -v "$command" >/dev/null || fail "Missing command: $command"
done
[[ -d "$base" && -O "$base" && ! -L "$base" ]] || fail 'selector配置先・所有者が不一致です。'
# Lock the existing directory inode: no lock/state file, even on Cancel/No.
exec {lockfd}<"$base"
flock -n "$lockfd" || fail '別のllm-selectが実行中です。'
templates_ok || fail 'テンプレートのSHA-256・所有者・modeが正本と不一致です。'
original=$(identify) || fail 'active Quadletと停止設定の対が正本と不一致です。'
if [[ ${1:-} == --show ]]; then
    say "現在選択中: $original / $unit / API $(port "$original")"
    systemctl --user show "$unit" -p ActiveState -p SubState -p MainPID -p Result
    exit 0
fi
[[ -t 0 && -t 1 && -t 2 && -n ${TERM:-} && $TERM != dumb ]] || fail '対話TTYが必要です: ssh -t evox2 llm-select'
flash_on=OFF dense_on=OFF
case "$original" in flash) flash_on=ON ;; dense) dense_on=ON ;; esac
if ! selected=$(whiptail --title 'Halogen model selector' --default-item "$original" --radiolist \
    "現在選択中: $original\nService: $unit\nFlash API 8731 / Dense API 8732 (自宅LAN)\n矢印: 移動 / Space: 選択 / Tab: OK・Cancel\n進行中のクライアント処理は切断され得ます。\nNo/Cancel/Escは変更を適用しません。" \
    19 78 2 flash 'Flash-Next / API 8731' "$flash_on" dense '27B Dense / API 8732' "$dense_on" \
    3>&1 1>&2 2>&3); then
    say '取消: 変更なし。'
    exit 0
fi
[[ "$selected" == flash || "$selected" == dense ]] || fail '不正な選択です。'
if [[ "$selected" == "$original" ]]; then
    say "現在選択中: $original。変更・再起動なし。"
    exit 0
fi
if ! whiptail --title 'Reboot?' --defaultno --yesno \
    "選択: $selected / $unit / API $(port "$selected")\nリクエストを終了し、モデルを変更してOSを再起動しますか？\n作業中のクライアントを終了してください。\nYes: idle確認→正常停止→GPU解放→設定対の切替→Reboot\nNo/Esc: 何も変更しません。" 16 78; then
    say 'No/取消: 変更なし。'
    exit 0
fi

# Every write and every service operation is below the explicit Yes gate.
gtt_files=(/sys/class/drm/card*/device/mem_info_gtt_used)
[[ ${#gtt_files[@]} == 1 && -r ${gtt_files[0]} ]] || fail 'GTT監視対象が一意でありません。'
gtt_file=${gtt_files[0]}
busy_file=${gtt_file%/*}/gpu_busy_percent
preflight || fail '前提/idle/boot先/実効unitが不一致です。停止せず終了します。'
say 'idle検査と新規HTTP到着の競合は完全には防げません。クライアント停止が前提です。'
# Recheck immediately before stop; do not wait/stop an externally replaced model.
if ! running_idle "$original"; then
    say '直前idle確認失敗。モデルは停止しません。' >&2
    exit 1
fi
container_id=$(podman inspect "halogen-$original" --format '{{.Id}}')
stop_since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
say "正常停止: $original / GTT before=$(gtt) bytes"
systemctl --user stop "$unit" || fail 'systemd停止失敗。設定変更・再起動を行いません。'
# --rm removes inspect state. Read the persisted event for this exact ID;
# do not leave a background waiter holding the selector lock after an error.
container_exit=$(podman events --stream=false --since "$stop_since" \
    --filter "container=$container_id" --filter event=died --format '{{.ContainerExitCode}}') || \
    fail 'container終了イベントを取得できません。設定変更・再起動を行いません。'
systemctl --user show "$unit" -p ActiveState -p SubState -p Result -p ExecMainCode -p ExecMainStatus -p ExecStop -p ExecStopPost
say "container exit=$container_exit / GTT after=$(gtt) bytes"
[[ $(value ActiveState) == inactive && $(value Result) == success ]] || fail 'systemdが正常停止を報告していません。終了コードだけで成功扱いせず保留します。'
stop_commands_ok || fail 'ExecStop/ExecStopPostの正常終了を確認できません。設定変更・再起動を行いません。'
[[ "$container_exit" == 0 || ( "$original" == dense && "$container_exit" == 143 ) ]] || fail '想定外のcontainer終了コードです。'
[[ $(value ExecMainCode) == 1 && $(value ExecMainStatus) == "$container_exit" ]] || fail 'systemdとcontainerの終了状態が一致しません。'
empty_runtime || fail 'container/port/GTTが解放されていません。設定変更・再起動を行いません。'
safe_stop=1
templates_ok && [[ $(identify) == "$original" ]] || fail '停止中に設定が変更されました。'

# Backups and staged files are adjacent to each destination, then renamed.
backup_q=$(mktemp "${quadlet%/*}/.llm-select-backup.XXXXXX")
backup_d=$(mktemp "${dropin%/*}/.llm-select-backup.XXXXXX")
cp -p -- "$quadlet" "$backup_q"
cp -p -- "$dropin" "$backup_d"
next_q=$(mktemp "${quadlet%/*}/.llm-select-next.XXXXXX")
next_d=$(mktemp "${dropin%/*}/.llm-select-next.XXXXXX")
install -m 0644 -- "$(qtemplate "$selected")" "$next_q"
install -m 0644 -- "$(dtemplate "$selected")" "$next_d"
checked_file "$next_q" "$(qhash "$selected")" && checked_file "$next_d" "$(dhash "$selected")" || fail '設置前hash不一致です。'
checked_file "$backup_q" "$(qhash "$original")" && checked_file "$backup_d" "$(dhash "$original")" || fail '退避hash不一致です。'
changed=1
mv -fT -- "$next_q" "$quadlet"
mv -fT -- "$next_d" "$dropin"
[[ $(identify) == "$selected" ]] || fail '切替後の設定対が不一致です。'
systemctl --user daemon-reload
unit_ok "$selected" || fail '生成unit/停止設定/default.targetの整合性検査に失敗しました。'
[[ $(value ActiveState) == inactive ]] && empty_runtime || fail '再起動直前にruntime状態が変化しました。'
systemctl --user show "$unit" -p ExecStart -p ExecStop -p ExecStopPost -p Restart
say "選択確認: $selected / API $(port "$selected")。正常停止とGPU解放済み。OSを再起動します。"
sync -f "$quadlet"
sync -f "$dropin"
# A successful reboot disconnects SSH. Do not roll back in response to that HUP.
trap '' HUP INT TERM
if sudo -n reboot; then
    reboot_accepted=1
    exit 0
fi
fail 'reboot要求が失敗しました。旧設定へ復元します。'
