# Halogen Flash-Next 初回導入 実施レポート

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
