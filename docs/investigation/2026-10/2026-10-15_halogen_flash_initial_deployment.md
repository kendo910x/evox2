# Halogen Flash-Next 初回導入 実施レポート

> **最新状態（2026-10-15 12:33 JST）: 初回導入・Thinking ONの日本語API疎通は成功。検証後に正常停止済み。** モデル・image・通常起動スクリプトは配置済み。自動起動・常時稼働は設定していない。第1〜7節は11:27 JSTまでのPhase A中間報告であり、その時点の未実施・待機状態を記録している。UMA変更後の結果は第8節以降。

## 1. 状態・実施条件

**状態: `WAITING_FOR_USER_UMA`。Phase Aのストレージ・GPU権限・rootless Podmanの準備を実施した。Phase Bのイメージ/モデル取得、Halogen起動、API疎通は未実施であり、初回導入全体は未完了。**

- 作業日: 2026-10-15。実機の調査・準備・確認は11:21〜11:27 JST。
- 指示書: `docs/instructions/2026-10/2026-10-15_halogen_flash_initial_deployment_instruction.md`
- 実行した指示書commit: `fe1d900e4630923d8563154cf0d6859d2089f056`。
- 実行主体: Windows開発PC上のCodex。実機操作はSSH別名 `evox2` 経由のUbuntuで実行した。
- Git: `kendo910x/evox2`、branch `main`。開始時HEADは `3dacbf5f4e1626e64b7f981165109cdd9857e0bd`、作業ツリーはclean。fetch後に指定commitの `origin/main` 包含を確認し、fast-forwardで同期した。対象ファイルの既存変更・競合はなかった。
- 必須読込: `AGENTS.md`、修正版指示書、`docs/investigation/2026-10/2026-10-15_initial_environment_survey.md`。
- 対象確認: SSH先のhostname、一般ユーザーのID/group、Ubuntu 26.04.1 LTS、カーネル `7.0.0-38-generic`、初回調査と一致するSSD/GPUを確認。`sudo -n true` 成功。実hostname、ユーザー名、LAN情報、UUID等は公開しない。

## 2. 検証結果

| 項目 | 結果 | 観測・制限 |
|---|---|---|
| 指示書受領・包含確認 | PASS | `git merge-base --is-ancestor fe1d900e4630923d8563154cf0d6859d2089f056 origin/main` が終了コード0 |
| SSH・sudo無人実行 | PASS | 作業前後の別SSH接続で成功。SSH設定・sudoersは変更していない |
| Linux用PV/VGの照合 | PASS | `ubuntu-vg` のPVはKIOXIA SSD上の `/dev/nvme1n1p3` だけ。開始時LVは100 GiBのrootだけ |
| 新規データ領域 | PASS | `llm_data` を新規作成・ext4化し、`/srv/llm` にmount。root/boot/ESPは元の構成を維持 |
| GPUデバイス権限 | PASS（ホスト上） | 当該ユーザーをrender groupに追加。新規SSHセッションで `/dev/kfd` と `/dev/dri/renderD128` のread/write可否検査が成功。GPU計算自体は未実施 |
| GPU ISA・KFD前提 | PASS（公開された判定式の範囲） | GPU nodeの `gfx_target_version=110501`、SVM capability bit、CWSR計算式の一致を確認。Halogen実行の保証ではない |
| rootless Podman基本動作 | PASS | `podman info` のrootless=true、overlay/crun、専用graphrootを確認。`podman unshare true` 成功 |
| memlock上限引上げ診断 | FAIL（制限確認） | soft/hardとも8 MiB。rootless user namespace内の上限引上げは拒否された。Halogen起動失敗を実測したわけではない |
| Phase BのUMA開始条件 | 未達 | Linux `MemTotal` 約30.5 GiB、VRAM表示96 GiBのまま。約100 GiB以上のLinux RAMという開始目安を満たさない |
| イメージ/モデル取得・起動・API/Thinking ON | 未実施 | UMA待ちのためPhase Bに進めていない。image digest、モデルの実サイズ、性能値も未確認 |
| Git commit/push・最終包含確認 | 最終チャットで報告 | 本文確定時点では未実施。実際のSHAと結果を最終チャットに記載する |

## 3. Phase Aの観測と実施内容

### 3.1 ストレージ

開始時は次の条件をすべて満たした。

- `ubuntu-vg`: PV数1、LV数1。PVは `/dev/nvme1n1p3`、親SSDはKIOXIA-EXCERIA PLUS G3 SSD。別のCT2000E100SSD8はVGに含まれず、mountpointもなかった。
- VG容量 `996923146240` bytes、空き `889548963840` bytes（828.45703125 GiB）。extent sizeは4194304 bytes、free extentsは212085。400 GiB以上の条件を満たす。
- 既存root LVは `ubuntu-lv`、`107374182400` bytes（100 GiB）。`/srv/llm` はディレクトリもmountもfstabエントリも存在しなかった。
- `lvcreate --test` 後にもLV一覧を確認し、試行段階ではroot以外が作られていないことを確認した。

**[EVO-X2 Ubuntu/SSH]** 実デバイス・VG・空きextent数・rootサイズ・新規パス不在を再検査してから実行した主な変更:

```bash
sudo -n lvcreate -l 100%FREE -n llm_data ubuntu-vg
sudo -n mkfs.ext4 -q -L llm_data /dev/ubuntu-vg/llm_data
sudo -n mkdir /srv/llm
# /etc/fstab に新LVの実UUIDを用いた1行のみ追記（UUIDは公開しない）
# UUID=<新LVのUUID> /srv/llm ext4 defaults,nofail 0 2
sudo -n systemctl daemon-reload
sudo -n mount /srv/llm
```

`mkfs` の前に、新LVの容量・配置と既存filesystem signatureがないことを確認した。初回の読み取り専用 `wipefs` 確認では `-o TYPE` がoffset指定として解釈され失敗したため、`--no-act --noheadings --output TYPE` に訂正して確認した。誤った書込・消去は発生していない。

| 項目 | 作業後 |
|---|---|
| 新LV | `/dev/ubuntu-vg/llm_data`、889548963840 bytes、約828.5 GiB |
| mount | `/dev/mapper/ubuntu--vg-llm_data` → `/srv/llm`、ext4、rw |
| `df -h /srv/llm` | filesystem容量815G、空き773G。LV容量との差にはext4の管理領域・予約領域等がある |
| VG free | 0 bytes / 0 extents。指示書どおり未割当領域を全量使用 |
| root | 100 GiB LVのまま。`df -h /` は容量98G、使用12G、空き82G |
| boot / ESP | 同じLinux SSD上の `nvme1n1p2` / `nvme1n1p1` のまま。変更なし |
| fstab | UUIDが新LVと一致する `/srv/llm` エントリが1つだけあることを確認。`nofail` はデータ領域のmount失敗でOS起動を妨げないため。再開時はmountを必ず確認する |

rootとEFI、Windows側SSD、既存partition/LVの初期化・拡張・縮小・移動は行っていない。VG freeはゼロのため、将来のroot拡張・snapshot用の余地は残っていない。

### 3.2 GPU・メモリ

- Linux `MemTotal=31960852 kB`（約30.480 GiB）。作業後 `MemAvailable=29155396 kB`（採取時点の値）。swapは約8 GiB、作業開始時使用量0。
- VRAM totalは `103079215104` bytes（96 GiB）、GTT totalは `16363954176` bytes（約15.240 GiB）。BIOS画面の設定値は未確認。
- GPUの使用率は事前確認時0%。GTT usedは18661376 bytes、VRAM usedは154939392 bytes。既知の推論サービス名に該当するrunning system unitはなかった。`fuser` は未導入のため、全GPU利用プロセスの特定までは行っていない。
- KFD topologyのGPU node: `gfx_target_version=110501`、`capability=671326848`。SVM bit `0x08000000` が立っている。`simd_count=80`、`ctl_stack_size=16384`、`cwsr_size=19185664` で、公式の `ctl_stack_size + (simd_count / 2) * 479232` と一致した。既存kernel configも `CONFIG_HSA_AMD_SVM=y`。
- `/dev/kfd` とrender nodeが `root:render 0660`、当該ユーザーがrender非会員という指定条件を確認し、`usermod -aG render` を当該ユーザーにだけ実施。新たなSSHセッションでgroup反映と両デバイスのread/write可を確認した。

### 3.3 Podman・パッケージ

Ubuntu公式repository由来であることを確認し、apt indexを更新した。通常の `install podman` のdry-runは35パッケージだったが、今回不要なbuildah/CRIU等を含むため、rootless実行・UID mapping・network・storageに必要な通常依存に絞った。実施コマンドは次のとおり。

```bash
# [EVO-X2 Ubuntu/SSH]
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
  apt-get -y --no-upgrade --no-install-recommends install \
  podman uidmap passt crun fuse-overlayfs
```

結果は **12パッケージ新規導入、upgrade 0、削除0**。31.8 MB取得、aptの追加使用量表示は107 MB。needrestartは再起動が必要なサービスなしと報告した。aptが提案した古いカーネルのautoremoveは実行していない。

| 新規パッケージ | version |
|---|---|
| podman | 5.7.0+ds2-3build1 |
| conmon | 2.1.13+ds1-2 |
| crun | 1.21-1ubuntu3 |
| fuse-overlayfs | 1.14-1build2 |
| golang-github-containers-common | 0.66.0+ds2-3 |
| golang-github-containers-image | 5.38.0+ds2-2 |
| libgpgme45 | 2.0.1-2build1 |
| libsubid5 | 1:4.17.4-2ubuntu3 |
| libyajl2 | 2.1.0-5.1 |
| netavark | 1.16.1-3.1 |
| passt | 0.0~git20260120.386b5f5-1 |
| uidmap | 1:4.17.4-2ubuntu3 |

当該ユーザーの既存subuid/subgid rangeはそれぞれ65536 IDs分あり、その設定は変更していない。Docker、ROCmホスト一式、GUI、グローバルpipパッケージは導入していない。

既存Podmanストレージ・ユーザー設定がなく、関連するXDG/containers storage overrideもないことを確認し、`~/.config/containers/storage.conf` を新規作成した（mode 0600、実ユーザーのHOMEパスは非掲載）。内容:

```toml
[storage]
driver = "overlay"
graphroot = "/srv/llm/containers/podman"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
```

`podman info` はrootless=true、graphrootが指定パス、driver=overlay、runtime=crunと報告。`podman unshare true` も成功。`podman ps -a` と `podman images` はともに空。既定のHOME側graphrootは作られていない。

イメージ取得の一時保存先は無指定だと `/var/tmp` だったため、`/srv/llm/containers/tmp` を用意した。**再開時のpullには `TMPDIR=/srv/llm/containers/tmp` を付ける。** この環境変数を付けた `podman info` で `imageCopyTmpDir` の一致を確認済み。グローバルな環境設定は追加していない。

memlockはSSHセッションのhard limitが8192 KiB、`podman unshare` 内でもsoft/hardとも8388608 bytesだった。診断用の一時Pythonプロセスで `resource.setrlimit(RLIMIT_MEMLOCK, (RLIM_INFINITY, RLIM_INFINITY))` を試すと `not allowed to raise maximum limit` となった。ホストのPAM/limits設定は変更していない。Podman公式資料では `--ulimit` の `-1` は現在のプロセスの最大値を使うため、指定だけで無制限になるとは扱わない。**Halogenのロードやコンテナ内の実際の制限は未検証であり、この診断だけをHalogen起動失敗とはしない。** 実際に追加設定が必要なら、対象ユーザーのmemlock制限だけを扱う案について承認を得る。rootful/privilegedへ切り替えない。

### 3.4 残った状態・サービスへの副作用

| 項目 | 作成・変更と現在の状態 |
|---|---|
| `/srv/llm` | root所有、0755。独立ext4 LVのmountpoint |
| `models` / `engines` / `containers` 親ディレクトリ | `/srv/llm` 配下、root所有、0755 |
| `/srv/llm/models/halogen-flash` | 実行ユーザー所有、0755、空 |
| `/srv/llm/engines/halogen-flash` | 実行ユーザー所有、0755、空。run.shはまだ転送していない |
| `/srv/llm/containers/podman` | 実行ユーザー所有、0700。Podman管理metadata約160K、イメージ/コンテナなし |
| `/srv/llm/containers/tmp` | 実行ユーザー所有、0700、約4.0K |
| ユーザー専用設定 | `~/.config/containers/storage.conf` のみ新規作成。Podman runrootは当該ユーザーの `/run/user/<UID>/containers` |
| システム側 | 新LV、fstab 1行、render group会員資格、apt/dpkg管理の12パッケージ。LVMの `/etc/lvm/backup`・`/etc/lvm/archive`、apt/dpkgの通常ログ等も管理対象として残る |
| netavarkのapt副作用 | パッケージが `netavark-dhcp-proxy.service`（enabled/inactive）、`netavark-dhcp-proxy.socket`（enabled/active/listening）、`netavark-firewalld-reload.service`（enabled/active/running）を登録した。手作業でenable/startしたものではない |
| netavark socket | unit定義はローカルUnix socket `%t/podman/nv-proxy.sock`。TCP API公開ではない。`firewalld.service` 本体はnot-found |
| Podman system units | `podman.service`、`podman.socket`、`podman-auto-update.timer`、`podman-restart.service` はいずれもdisabled/inactive |
| SSH・API port | `ssh.service` active、`ssh.socket` active/enabledを維持。8731/TCPのlistenなし。Halogenサービス・自動起動設定なし |

既存サービスを明示的に停止・再起動していない。fstab反映のためsystemd daemon-reloadを実施した。上記apt依存によるunit登録・起動は実際の副作用として記録する。BIOS/UMA、カーネル/firmware、SSH/sudoers、firewall設定、電力設定、Windows SSDは変更していない。実機のreboot/shutdownも行っていない。

## 4. 人手待ちと再開条件

指示書のPhase A終了条件に従い、**`WAITING_FOR_USER_UMA`** として停止する。ユーザーが行う操作:

1. BIOS画面で現在のUMA frame buffer / dedicated graphics memoryの値を控える。
2. **Autoではなく、画面で選べる最小の明示値**にする。Halogen公式にはEVO-X2で2GBの報告があるが、本機の選択肢はユーザーが確認する。
3. ユーザー操作でUbuntuへ起動し直し、設定した値と起動完了を伝える。この変更はWindows起動時のGPUメモリ配分にも影響し得る。

同じ指示書から再開できる。Codexは既存のLV作成・format・fstab追記・group追加・初期storage設定を繰り返さない。再開時はLinux `MemTotal` 約100 GiB以上、GPU権限、実SSDとmount、160 GiB以上のデータ空き、Podman保存先・一時保存先、8731の空き、GPU利用状況、memlockを再確認する。BIOS変更後の実機状態で判断し、Codex自身はBIOS変更や再起動をしない。

Phase Bでは指定の `ghcr.io/peonist-ai/halogen-flash-server:0.18.4` と公式 `peonist-ai/halogen-qwen3.8-flash-next` のv2を使う。今回はpull・モデル取得とも0回。digest、ライセンス詳細、モデル版/実サイズ、ロード、`/health`、`/v1/models`、Thinking ONの日本語応答、再リクエスト、timingsは未確認。`deploy/halogen-flash/run.sh` はPhase B2で作成・実機照合するため、この中間報告時点では作成していない。

## 5. 削除・切戻し手順（未実行）

以下は後日の切戻し計画であり、今回削除操作は実行していない。実行前に対象が本タスク専用のままか、後から追加されたデータや利用者がないかを再確認する。

1. 現在Halogenコンテナ・イメージ・モデルはない。再開後に存在する場合は当該コンテナだけを正常停止し、固まる場合はforce kill/rebootへ進まず報告する。モデル等を保存する必要があれば、削除前に退避する。
2. 当該ユーザー専用の `storage.conf` が今回の内容のままで他用途に使われていなければ削除する。Podmanの管理データ・runtimeは当該ユーザーと専用graphrootに限定して整理する。他用途ができた状態で `podman system reset` や全体pruneを実行しない。
3. パッケージを戻す場合は上記12個のうち引き続き本用途だけのものを選び、まずaptのsimulateで依存・削除範囲を確認してからremove/purgeする。netavarkのpackage-managed unitも対象になる。古いカーネル等を巻き込む一括autoremoveはしない。
4. render会員資格が他用途にも必要でなければ、対象ユーザーだけをrenderから外し、新しいログインで確認する。既存のsubuid/subgidは変更していないため戻さない。
5. 新LVを削除する場合はデータ退避・利用停止を確認し、`/srv/llm` をunmount、fstabの今回の1行だけを除去してdaemon-reloadする。その後 **`/dev/ubuntu-vg/llm_data` だけ**を削除する。root LV、VG/PV全体、partition、EFI、別SSDは対象外。この操作でVG freeを戻せるが、後から蓄積したデータは失われるため、実行前に削除の承認と対象確認を行う。
6. 空になった今回専用のmountpoint・設定ディレクトリだけを必要に応じて整理する。apt/LVMの履歴やOSログを隠す目的で削除しない。BIOSは今回Codexが変更していないので切戻し対象外。後日ユーザーが変えた場合は控えた値を使ってユーザーが戻す。

## 6. 参照した公式資料

2026-10-15に確認。外部資料の一般的な推奨より、本リポジトリの承認済み指示書の操作境界を優先した。

- Halogen: [README](https://github.com/peonist-ai/halogen-flash-server/blob/main/README.md)、[AGENTS](https://github.com/peonist-ai/halogen-flash-server/blob/main/AGENTS.md)、[getting-started](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/getting-started.md)、[troubleshooting](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md)。UMA最小化、固定タグ、デバイス/IPC指定、KFD topology判定を照合した。
- Halogen API設定: [FLAGS](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/FLAGS.md)、[api](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/api.md)、[sampling](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/sampling.md)。Phase Bの実行は保留。
- Podman: [rootless・TMPDIR](https://docs.podman.io/en/latest/markdown/podman.1.html)、[storage.conf](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)、[ulimit](https://docs.podman.io/en/latest/markdown/podman-run.1.html#ulimit-option)。ユーザー専用graphroot、overlay設定、一時保存先と制限を照合した。

## 7. Git成果物

- 今回のtracked変更は `docs/investigation/2026-10/2026-10-15_halogen_flash_initial_deployment.md` 新規1ファイルのみ。Phase Aでの人手待ちなので、未検証の起動スクリプトは成果物に含めない。
- commit前に本文、機密情報、`git diff --check`、対象差分とstage範囲を確認する。
- 実際のcommit SHA、push結果、push後の `origin/main` 包含確認は**最終チャットで報告**する。
- 次工程: ユーザーによるUMA変更後、同じ指示書からPhase Bを再開し、本レポートに追補する。初回導入成功、性能達成、恒久稼働への移行はいずれもまだ宣言しない。

## 8. UMA変更後の再開・A4

- 再開日: 2026-10-15。実行主体は引き続きWindows開発PC上のCodex、実機操作は `ssh evox2` 経由。
- 更新指示書: `docs/instructions/2026-10/2026-10-15_halogen_flash_initial_deployment_instruction.md`、commit `38d2612c6518d89c2f241a535852ba816a6fefda`。
- 再開時のbranchは `main`、HEADは前回報告commit `10ebac6ce3a2d19279710410768305d726c005a2`、作業ツリーclean。`AGENTS.md` を先に読み、fetch・指示書commitの包含確認後にfast-forwardした。対象ファイルに他タスクの変更はなかった。
- 前回完了したLV作成、format、fstab追記、apt導入、render group追加、storage.conf作成は再実行していない。

### 8.1 Phase B開始条件の再確認

| 確認項目 | 結果 |
|---|---|
| 対象・権限 | 同じUbuntu 26.04.1 LTS、kernel `7.0.0-38-generic`、対象一般ユーザーを確認。新規SSHと `sudo -n true` が成功 |
| UMA/RAM | `MemTotal=127098452 kB`（約121.21 GiB）、採取時 `MemAvailable=125382784 kB`。GPU固定VRAMは2147483648 bytes（2 GiB）。ユーザーのUMA変更を観測値で再確認し、`WAITING_FOR_USER_UMA` は解消 |
| GPU/GTT | gfx1151、SVM/CWSR前提は前回同様。GTT total=65074405376 bytes、開始時used=18661376 bytes、GPU busy=0%。再起動後のGPU sysfsはcard1であり、card0固定参照を訂正して実デバイスを確認 |
| GPU権限 | `/dev/kfd` と `/dev/dri/renderD128` のread/write可。render資格を維持 |
| データ領域 | Linux側KIOXIA SSDの同じPV/VG/LV、`/srv/llm` mountを確認。開始時空き773 GiB、root空き82 GiB。Windows側SSDは操作していない |
| Podman | rootless、crun、graphroot `/srv/llm/containers/podman` を確認。開始時image/containerなし、8731のlistenなし |
| memlock | 以下のA4適用後、新SSH・rootless namespaceとも無制限を確認してからPhase Bへ進んだ |

### 8.2 memlockの変更と検証

既存の競合するmemlock規則がなく、専用ファイルが未存在であることを確認した。`/etc/pam.d/sshd` に既存の `session required pam_limits.so` があったため、PAM設定変更は不要だった。

**[EVO-X2 Ubuntu/SSH]** `/etc/security/limits.d/90-evox2-halogen-memlock.conf` を排他的な新規作成で追加し、mode 0644とした。実機の `id -un` で得た1名だけに次の2行を設定した。公開用の表記はプレースホルダーとする。

```text
<login-user> soft memlock unlimited
<login-user> hard memlock unlimited
```

既存セッションは8192 KiBのまま、新しいSSH接続ではsoft/hardとも `unlimited`。`podman unshare` 内の `resource.getrlimit(resource.RLIMIT_MEMLOCK)` は `(-1, -1)`、対象規則は重複なく2行だった。コンテナinspectでもmemlockのSoft/Hard=-1を確認した。全ユーザー・他のlimit・既存PAM/SSH/sudoersは変更せず、サービス再起動もしていない。無制限という上限設定と、モデルの実際のpin/lock成功は別に評価する。

## 9. Phase B取得・起動の記録

### 9.1 配布物

**[EVO-X2 Ubuntu/SSH]** `TMPDIR=/srv/llm/containers/tmp podman pull --quiet ghcr.io/peonist-ai/halogen-flash-server:0.18.4` が終了コード0。pull所要約61秒。

| 項目 | 確認値 |
|---|---|
| image tag | `ghcr.io/peonist-ai/halogen-flash-server:0.18.4` |
| image digest | `sha256:1a458cd6decdd3a2c27f96196cc3a0bc853cbb3905320c3461d29137072faa78` |
| image ID | `556c3c8179d8a566cc0ec0a7f7f54f9f3cb8b77e7bc4a4175e7c23ae359ad80a` |
| image metadata | version 0.18.4、revision `968a683de2ad`、size 3598114683 bytes、entrypoint `/usr/local/bin/entrypoint.sh` |
| model repository | `peonist-ai/halogen-qwen3.8-flash-next`、確認時revision `cf41ff9fc97b6dd9887d82e21269522de6208055` |
| model選択 | 標準v2。旧w4b/GGUF/別量子化への変更なし |
| 取得予定量 | 公式entrypoint表示110.6 GiB。v2・ngram・visionとtokenizer。130 GiB上限内 |
| ライセンス表記 | imageは `LicenseRef-Peonist-EULA`、モデルカードはApache-2.0。エンジンEULAとモデルの条件は別。配布・改変時は各原文を再確認する |

モデルは匿名で取得可能なpublic/ungated repositoryであり、認証情報を設定・取得していない。Hugging Faceのモデルcacheもモデルディレクトリ内。root/HOMEへモデルを二重取得していない。

### 9.2 初回取得の中断と再開

11:58:40 JSTに、指示書のrootless bootstrapコマンド（`--pull=never` を追加）を起動した。loopback `127.0.0.1:8731` のみ、指定デバイス・keep-groups・host IPC・memlock無制限、モデルRW mount。

**最初の試行は失敗:** SSHコマンド終了後の11:58:51にコンテナが終了コード1で停止・自動削除され、`download FAILED. Nothing was started.` と記録された。取得途中の約192 MiBのcacheだけが残り、完成したモデル本体・GPUロードはなかった。

限定診断で、同じimageのhf CLI 1.28.0、匿名のmetadata取得・モデルHEADがHTTP 200、`hf download --dry-run` の対象3ファイル/118.8 GB（十進）を確認した。追加のモデルダウンロードは行っていない診断である。journalでは同時刻にユーザー用systemdのshutdownと当該libpod scopeの停止があり、`Linger=no` だった。最後のSSH接続終了でユーザーマネージャーが終了し、取得中コンテナが停止したと判断した。

12:03:30 JSTに **中断した同じ初回取得を再開**。`podman run` 後に同じSSH接続で `podman wait halogen-flash-bootstrap` を実行し、ログインセッションを保持した。断片の再利用は公式downloaderの再開機構に委ねたが、実際の再利用byte数は未測定。bootstrap起動は中断分を含め2回であり、1回で成功したとは記録しない。盲目的なループ再試行、別モデル取得、linger設定変更、systemd永続service追加はしていない。

12:28:15 JSTにdownload complete。再開から約24分46秒、終盤の取得ログは平均約80 MB/s（十進、**推論速度ではない**）。モデル本体3個とtokenizerの実サイズ合計は118808753412 bytes（約110.65 GiB）。初回中断由来とみられる201196516 bytesおよび0 bytes×2の `.incomplete` がcacheに残り、削除は行っていない。この残骸を含めても130 GiB以内である。entrypointの `download complete (63G)` はv2本体の表示であり、取得一式のサイズとは区別した。

### 9.3 通常起動スクリプト

`deploy/halogen-flash/run.sh` を新規作成。Ubuntu・一般ユーザー・rootless Podman・mount・必要モデルファイル・GPU権限・memlock・imageの存在と、同名container/8731の未使用を確認してから通常起動する。imageは指定tag固定かつ `--pull=never`、モデルはRO、`HALOGEN_DOWNLOAD` なし。既存containerを停止・置換しない。

**[Windows開発PC → EVO-X2 Ubuntu]** `scp` で `/srv/llm/engines/halogen-flash/run.sh` へ1ファイルのみ転送。転送先の未存在を確認後に配置しmode 0755とした。LF形式、`bash -n` 成功、双方のSHA-256は `5cb53066f338a15cb9c621d0b330998e1ed8da9dcd830d67e07971a9df15d0a9` で一致した。

取得途中にスクリプトを実行し、v2本体の未存在を検出して終了コード1、bootstrap以外のcontainerを作成しないことを確認した。これは意図したガードのPASSであり、モデルロード成功の検証ではない。

### 9.4 モデル照合と通常起動

bootstrapの `/health`・`/v1/models` がHTTP 200、モデルreadyを確認した後、12:29:16 JSTに `podman stop --time -1 halogen-flash-bootstrap` で正常停止した。終了コード0、GTT usedは起動前の18661376 bytesに戻った。`--time -1` は強制killへのtimeoutを無効にする指定である（[Podman公式](https://docs.podman.io/en/latest/markdown/podman-stop.1.html)）。

**[EVO-X2 Ubuntu/SSH]** 停止後にPythonで実ファイルのsizeと全体SHA-256を算出し、Hugging FaceのLFS metadataと照合した。3ファイルすべてPASS、hash計算所要63.73秒。取得metadataが示すrevisionもすべて `cf41ff9fc97b6dd9887d82e21269522de6208055` で一致した。

| ファイル | 実bytes | SHA-256（実測・配布metadata一致） |
|---|---:|---|
| `qwen38-flash-next-v2.hgn` | 66687678432 | `71246c6ab3fc1de2cf06326f18e275fe9c2a18366d646ed3357d194c884fc687` |
| `qwen38-flash-next-ngram.hgn` | 51200246144 | `3450acada94e19aabad88bd49b45eb70304820949c2240fc178067b20ae5dffe` |
| `qwen38-flash-next-vision.hgn` | 897916416 | `d62e0ae553fe88afd3833733d4a4c669f34d20fd8dfce4b9610525bed2134b10` |

tokenizerは `chat_template.jinja` 8952、`generation_config.json` 202、`merges.txt` 3353259、`tokenizer.json` 12809320、`tokenizer_config.json` 17928、`vocab.json` 6722759 bytes。実測したchat template SHA-256は `c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041`、tokenizer.jsonは `0997f410c57a1f4e53b09e4be8f4a172d90edd9564368fb0847030937229b9f3`。

12:30:21 JSTに配置済みrun.shで通常container `halogen-flash` を起動し、同じSSHで `podman wait halogen-flash` によりセッションを保持した。inspectで `/models` のRW=false、memlock Soft/Hard=-1、HostIp=127.0.0.1/HostPort=8731、`HALOGEN_DOWNLOAD` の不在を確認した。APIプロセスはcontainer内で0.0.0.0:8731にlistenするが、ホストへの公開は127.0.0.1だけである。

- 通常起動ログ: weights pinned 62.11 GiB、所要5.8秒、model readyまで7.7秒、engine listeningまで10秒。API/engine双方0.18.4。取得・hash直後のpage cacheが温まった条件であり、cold bootのロード時間ではない。
- bootstrap側はweights pin 7.0秒、model ready 9.2秒、engine listening 12秒だった。
- GPU/バックエンド: 公式imageの `HALOGEN_ARCH=gfx1151`、ホストamdgpu/KFD、指定GPUデバイスを使用。ホストに別ROCm一式は導入していない。コンテナ内ROCmライブラリの詳細版は採取していない。
- 標準v2 HGNはcheckpoint内にprecision選択を持つと起動ログが報告。quality sidecar適用なし。量子化の変更や内部bit幅の再設定はしていない。
- context=262144、4 slots、共通KV pool=524288 positions、MAX_TOK/PREFILL_CHUNK=32768。ログ上のメモリ内訳はweights 62.1 GiB + KV pool 14.4 GiB + working 12.5 GiB = 89.0 GiB。47.7 GiBのngram表は必要時にfile cacheから読む。
- memlock上限無制限とGPUへのpin成功を確認した。`HALOGEN_WEIGHTS_LOCK` は設定しておらず、Linuxの明示的なmlockを別途有効化したとは扱わない。起動ログ自身が、MemAvailableはGPU登録済みweightsをreclaimableとして約62 GiB過大に数える場合があると注意しており、実際に他用途へ使える空きは単純な `free` の値とは異なる。
- prompt cache=2、MTP depth-2（up to 3）既定有効。healthはprompt cacheのwarm/coldがbitwise-identicalではないと報告した。出力同等性やMTP有無の比較は実施していない。
- visionファイルは取得したがtowerはロードしておらず、healthでvision=false。画像推論は未実施。
- imageに含まれる既定のengine watchdogは起動ログに存在する。独自watchdog・daemon・serviceは追加していない。FastAPIの `on_event` DeprecationWarningが出たが、起動とAPI検証は成功した。

### 9.5 Thinking ONのAPI検証と実測

**[EVO-X2 Ubuntu/SSH]** Python標準ライブラリのHTTP clientから `http://127.0.0.1:8731/v1/chat/completions` へ逐次送信。いずれもmodel=`halogen-qwen3.8-flash-next`、`enable_thinking=true`、`max_completion_tokens=4096`、stream=false。最初の2回はreasoning_effort=low/temperature=0でseed未指定、top_p/top_kも未指定（greedy）。最後の1回だけxhigh/temperature=1.0/top_p=0.95/top_k=20/seed=42。クライアントtimeoutは各180秒で、すべて数秒で正常完了した。

| 検証 | HTTP / finish_reason / 最終回答 | input / completion（うちreasoning）tokens | pp tok/s | tg tok/s | prompt / generation ms | wall秒 |
|---|---|---:|---:|---:|---:|---:|
| 初回low、12人の握手の組合せ | 200 / stop / 66回、12×11÷2の説明。PASS | 78 / 121（88） | 175.557 | 69.429 | 444.3 / 1742.8 | 2.224 |
| 再リクエストlow、りんご17個を5人に配る | 200 / stop / 一人3個、余り2個。PASS | 70 / 104（74） | 313.199 | 70.157 | 223.5 / 1482.4 | 1.720 |
| 追加xhigh、赤2青1から非復元で2個取る同色確率 | 200 / stop / 1/3、組合せの説明。PASS | 101 / 315（273） | 420.133 | 61.456 | 240.4 / 5125.6 | 5.373 |

全応答に非空の `reasoning_content` と日本語の最終回答、usage、timingsがあった。reasoning_contentは312/278/421文字だったが、生の思考内容はレポートへ保存しない。3問の最終回答の計算内容も確認した。length終了、空回答、Thinkingのみの応答はなかった。tgはThinkingを含むcompletion全体に対するserverの `predicted_per_second` であり、最終回答だけの速度ではない。wallはHTTP要求開始から全応答受信までのclient実測。非streamのためTTFTは未測定であり、prompt_msをTTFTと呼ばない。

MTPのdraft/acceptedは初回104/78、再リクエスト91/69、xhigh233/171。timingsのcache_nは全件0、2回目/3回目のprefix_nは33/9。短い日本語の計算問題3件・逐次実行・ロード後のwarm条件の参考値であり、長文創作・分析/ツール利用の品質や持続速度、Windows実測との厳密な倍率を結論にしない。

通常containerの `/health` と `/v1/models` はHTTP 200、status=ok、engine.responds=true、API/engine版一致、chat template thinking_control=true/probe passed、model id一致。検証後もbusy=false/in_flight=0/queued=0だった。

**[Windows開発PC]** 30秒で自然終了するSSHに `-L 127.0.0.1:18731:127.0.0.1:8731` を付け、Windowsの `Invoke-RestMethod` でhealth/modelsの同じ正常応答を確認した。転送終了後にWindows側18731のlistenなしを確認。最初に試したStart-Process/Stop-Processを組み合わせる一時トンネル用コマンドは実行前に自動承認レビューで拒否されたため実行されておらず、上記の自然終了する方式で検証を完了した。

### 9.6 終了状態・PASS/FAIL/未実施

通常起動スクリプトを稼働中に再度実行すると、既存同名containerを検出して終了コード1、container ID不変だった（既存保護ガードPASS）。検証後の12:32:58〜12:32:59 JSTに `podman stop --time -1 halogen-flash` で正常停止し、waitは終了コード0だった。

| 項目 | 結果・最終状態 |
|---|---|
| A4 / Phase B開始gate | PASS。UMA変更を再確認し、対象1名のmemlockを設定・継承確認 |
| 最初のbootstrap | FAIL。SSH終了に伴うユーザーマネージャー終了で中断。原因確認後、SSHを保持して同じ初回取得を再開 |
| 取得・実ファイル照合 | PASS。指定v2一式、公開ハッシュと一致、130 GiB以内 |
| 通常起動・health/models・Thinking ON日本語3件 | PASS。モデルRO/download無効、低い品質条件への変更なし |
| WindowsからのSSH転送 | PASS。一時転送だけ、終了済み |
| 正常停止・GPU返却 | PASS。bootstrap/通常双方終了コード0。最終GTT used=18661376 bytesで開始時と一致、container一覧空、8731 listenなし |
| ホスト状態 | 終了時MemAvailable約119 GiB、swap使用276 KiB。12:28以降のkernelログをGPU error/fault/reset/OOMのパターンで限定確認し該当なし。全イベントの不存在を保証する検査ではない |
| ディスク | `/srv/llm` 使用115 GiB/空き659 GiB、root空き82 GiB。モデルディレクトリ約111 GiB、Podman graphroot約3.4 GiB、pull tmp約4 KiB |
| 恒久稼働・自動復旧 | 未実施。`Linger=no` のまま。推論engineは**配置済み・検証成功・正常停止中** |
| 追加評価 | 長文/長context、tool calls、並列負荷、耐久試験、MTP有無の品質比較、画像入力、27B Dense/NPUは未実施 |

通常ユーザーの `du` はrootless image内部のUID所有ディレクトリ2箇所でpermission deniedとなった。停止操作自体はその前に成功済みであり、サイズ確認だけを `podman unshare du` で読み取り直して成功した。所有権・権限は変更していない。

## 10. 一時利用と追加状態の切戻し

以下は通常利用・後日の切戻し手順である。削除・設定切戻しは今回実行していない。

### 10.1 SSHを保持した一時利用

今回 `Linger=no` を変更していないため、`-d` のrootless containerだけでSSH切断後も稼働し続けるとは保証しない。次のように**同じSSH接続を開いたまま**利用する。8731をWindows側ですでに使っている場合は左側のローカルportを別の空き番号にする。

```powershell
# [Windows開発PC] 対話SSHとローカル転送。利用中はこの接続を保持する。
ssh -L 127.0.0.1:8731:127.0.0.1:8731 evox2
```

```bash
# [EVO-X2 Ubuntu / 上の対話SSH内]
/srv/llm/engines/halogen-flash/run.sh
# 別のWindows端末/クライアントから http://127.0.0.1:8731/v1 を利用する。
# リクエスト完了後に正常停止する。-1は強制killへのタイムアウトを無効にする。
podman stop --time -1 halogen-flash
# 停止が固まる場合は別SSHで読み取り診断し、強制killやrebootをせず報告する。
```

API公開はホストloopbackのみ。認証を追加しておらず、LAN/WANの無認証公開やSSH/firewall変更はしていない。ログアウト後の継続稼働、OS再起動時の自動起動、systemd永続service化は本タスクの成果に含めない。Windows checkoutから後日再転送する場合も、shell scriptの改行をLFで保持し、Ubuntuで `bash -n` とハッシュを確認する。

### 10.2 追加した永続状態と削除範囲

前回の第3.4節・第5節に加え、今回の追加状態は以下。

- `/etc/security/limits.d/90-evox2-halogen-memlock.conf`。不要になった場合は、内容が本タスクの対象1名・memlock2行のままであることを確認して、この専用ファイルだけを削除し、新たなSSHログインで旧上限を確認する。現在のプロセスの上限は削除だけでは変わらない。既存PAM等は触らない。
- `/srv/llm/models/halogen-flash` 内の指定モデル・tokenizer・Hugging Faceの取得metadata/cache。削除時は当該container停止と他用途がないことを確認し、このディレクトリの今回の取得物だけを対象にする。モデル本体はGit管理外。
- `/srv/llm/engines/halogen-flash/run.sh`。転送した1ファイルだけが対象。
- 専用graphroot内の指定image（上記digest/ID）とPodman管理状態。一時診断containerは `--rm` で終了した。imageを削除する場合は依存containerや別用途がないことを確認し、当該imageだけを `podman image rm` の対象にする。全体reset/pruneはしない。
- system journalには取得・起動・検証の通常ログが残る。ログ削除、HF認証情報の保存、追加パッケージ導入はしていない。

memlock無制限により大容量メモリのロックが可能になる。並行する大きなGPU負荷やメモリ圧迫時のOOMを本検証で評価したものではない。

## 11. 再開分の成果物・残課題

- tracked変更は `deploy/halogen-flash/run.sh` の新規作成（実行可能）と本レポートへの追補の2ファイルだけ。承認済み指示書・AGENTS.mdは変更しない。
- 本文確定後に対象差分、機密情報、`git diff --check`、stage範囲を確認し、commit/pushする。実際のSHAと `origin/main` 包含確認結果は最終チャットで報告する（自己commit SHAの本文への自己参照は行わない）。
- 初回導入の成功条件は達成した。今回の最終状態は停止中であり、ユーザーが第10.1節のSSHを保持する手順で一時利用できる。ログアウト後の継続稼働やsystemdへの昇格は、別途設計・承認が必要。
- 短いAPI疎通の結果だけで本格的な品質・性能の優位を判断しない。Flash-Nextの分析・ツール利用・長文context、長時間安定性、Windowsベースラインとの条件を揃えた比較は次工程の判断対象。TTFT、cold bootロード時間、コンテナ内ROCmの詳細版、モデル内部precisionのbit幅内訳は未確認。
- 小さい取得中断cache（約192 MiB）が残る。モデル本体は完全に照合済みであり、この残骸は未完成モデルを使用しているという意味ではない。不要ファイルの削除は今回実施していない。
- 新たに参照した公式資料: [Halogen host setup](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/host-setup.md)、[API](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/api.md)、[troubleshooting](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md)、[engine license](https://github.com/peonist-ai/halogen-flash-server/blob/main/LICENSE.md)、[model card](https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next)、[model revision](https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next/tree/cf41ff9fc97b6dd9887d82e21269522de6208055)。実際に稼働した版・設定は上記image/実ファイルhash/実機ログを根拠とし、mainの将来の変化と区別する。
