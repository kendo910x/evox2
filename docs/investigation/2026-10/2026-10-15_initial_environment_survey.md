# EVO-X2 初回環境調査 実施レポート

## 1. 目的・実施条件

- 目的: 指示書受領、Windows開発PCからのSSH経由の読み取り専用調査、レポートのGit受渡しを確認する。環境構築・性能評価は対象外。
- 実施日: 2026-10-15、実機情報採取は10:56〜10:57 JST。
- 指示書: `docs/instructions/2026-10/2026-10-15_initial_environment_survey_instruction.md`
- 指示書commit: `020641fd6e603a63f81276988ee7a58033f0c5dd`
- 実行主体: Windows開発PC上のCodex。対象はSSH別名 `evox2` で接続したUbuntuホスト。OS、hostname、アカウント、CPUを確認した。SSHセッションは一般ユーザーで、権限昇格はしていない。
- Git: `kendo910x/evox2`、branch `main`。開始時HEADは `ede6b5563c4a85b07c4fa951b534cb0feb613dcc`、作業ツリーはclean。開始時のローカル `origin/main` とHEADは一致していた。
- `git fetch origin main` 後、指定commitの `origin/main` 包含を確認し、`git merge --ff-only origin/main` で `020641fd6e603a63f81276988ee7a58033f0c5dd` に更新。最新指示書を読んで実機調査を開始した。既存変更・対象レポートの競合はなかった。
- 公開用のため、実際のhostname、ログイン名、Windows側パス、LAN情報、端末固有ID、生ログは掲載しない。

## 2. ワークフロー疎通結果

| 確認項目 | 結果 | 根拠・範囲 |
|---|---|---|
| `AGENTS.md` 読込 | PASS | 指示書より先に読込 |
| 指示書commitの包含 | PASS | fetch後の `git merge-base --is-ancestor 020641fd6e603a63f81276988ee7a58033f0c5dd origin/main` が終了コード0 |
| SSH疎通・対象確認 | PASS | `ssh-ok`、`Linux` を取得し、Ubuntuと対象CPU、一般ユーザー権限を確認 |
| 読み取り専用調査 | PASS（一部未確認） | 下表の情報を取得。権限不足・ツール不在は未確認として扱い、追加導入・権限変更はしていない |
| レポート作成 | PASS | 指定された本ファイルのみを新規作成 |
| Git commit / push / push後の包含確認 | 最終チャットで報告 | 本文確定時点では未実施。成功を先取りせず、実際のSHAと各結果を最終チャットに記載する |
| ChatGPTによるGitHub上の内容レビュー | 未実施 | 本タスクの受渡し後に行う工程 |

## 3. 環境サマリー

| 項目 | 観測結果 |
|---|---|
| OS | `/etc/os-release`: Ubuntu 26.04.1 LTS (Resolute Raccoon) |
| カーネル・アーキテクチャ | `7.0.0-38-generic` / `x86_64` |
| CPU | `AMD RYZEN AI MAX+ 395 w/ Radeon 8060S`。1 socket、16 cores、32 threads、NUMA node 1 |
| Linux側RAM | `MemTotal=31960852 kB`（約30.480 GiB）。採取時 `MemAvailable=29343440 kB`（約27.984 GiB）。物理搭載容量128GBの独立確認ではない |
| swap | `SwapTotal=8388604 kB`（約8 GiB）、`SwapFree` も同値。採取時使用量0 |
| PCI GPU認識 | `lspci` あり。AMD/ATI Strix Halo、Radeon Graphics / Radeon 8050S Graphics / Radeon 8060S Graphics共通表示、PCI ID `1002:1586`。使用ドライバ `amdgpu`。GPUのISA名 `gfx1151` は未確認 |
| GPUモジュール・カーネルconfig | `lsmod` で `amdgpu` を確認。独立した `amdkfd` 行はなし。既存の `/boot/config-7.0.0-38-generic` は `CONFIG_DRM_AMDGPU=m`、`CONFIG_HSA_AMD=y`、`CONFIG_HSA_AMD_SVM=y` |
| KFD / DRM | `/dev/kfd`、`/dev/dri`、`/dev/dri/renderD128` が存在。両デバイスノードは `root:render`、mode `0660`。現SSHユーザーは `render` グループに属さず、`test -r` / `test -w` は両ノードとも不可 |
| VRAM観測値 | `/sys/class/drm/card0/device/` の `mem_info_vram_total` と `mem_info_vis_vram_total` はともに `103079215104` bytes（96 GiB） |
| GTT・UMA | 同ディレクトリの `mem_info_gtt_total=16363954176` bytes（約15.240 GiB）。`/sys/module/amdgpu/parameters/gttsize` は存在するが現ユーザーには読み取り不可。BIOS UMA値・GTT全体の設定・実際に確保可能な上限は未確認 |
| Linux SSD | `nvme1n1`、931.5G、KIOXIA-EXCERIA PLUS G3 SSD。`p3` はLVM2 memberで、その配下の100GのLVがroot |
| Linux root | `/dev/mapper/ubuntu--vg-ubuntu--lv`、ext4、`/`。`df -h /` は容量98G / 使用11G / 空き82G / 使用率12% |
| Linux boot / ESP | `/boot` は同SSDの `nvme1n1p2`（2G、ext4）。`/boot/efi` は `nvme1n1p1`（1G、vfat）。rootと現在マウント中のESPは同じLinux SSD系列 |
| 別SSDの観測 | `nvme0n1`、1.8T、CT2000E100SSD8。`lsblk` にvfat・NTFS等のpartitionが表示され、mountpointは全て空欄。Windows用と考えられるが、内容の検査・マウントはしていない |
| SSH | 接続成功。`ssh.service` はactive/running、unit fileはdisabled。`ssh.socket` はactiveかつenabledで、サービスの `TriggeredBy=ssh.socket` を確認。socket経由の自動起動設定がある。再起動後の疎通は未検証 |
| GUI関連 | default targetは `graphical.target` で、同targetはactive。ただし `display-manager.service` はnot-found/inactive。`ubuntu-desktop`、`ubuntu-desktop-minimal`、`gdm3`、`sddm`、`lightdm` は `dpkg-query` で該当パッケージなし。GUI全般の完全な不在までは断定しない |
| ツール | 現SSHセッションの `PATH` 上で `docker`、`podman`、`git`、`rocminfo`、`amd-smi`、`rocm-smi`、`llama-server` は見つからず。`python3` は存在し、Python 3.14.4。PATH外を含むインストール状況の完全調査ではない |
| 推論関連systemdサービス | system scopeと現ユーザーのuser scopeで、読み込まれたservice unit名を限定検索し該当なし。検索語は `llama / gufo / halogen / ollama / vllm / llm / lmstudio / lm-studio / text-generation / inferen / mlx`。任意名のサービス、他ユーザー、systemd外のプロセスは未確認 |

取得上の制限:

- `lspci -nnk` は一部PCIデバイスの `label` 読み取りで `Operation not permitted` を出したが、上記GPUの識別と使用ドライバは取得できた。sudo等で追跡していない。
- `gttsize` は読み取り可否を検査し、読み取り不可と確認した。値を推定値で埋めていない。
- GUIパッケージの限定照会は該当パッケージなしにより終了コード1となった。これはSSH接続失敗ではない。照会した5パッケージについての結果に限定する。

## 4. 次工程に関係する未確認事項・技術的リスク

1. **メモリの利用可能範囲**: Linux側RAMは約30.5 GiB、GPU側のVRAM表示は96 GiB。128GB全体をCPU側RAMとして利用できる状態ではない。BIOS UMA値、物理搭載容量、メモリ共有・割当可能量の詳細は未確認で、観測値だけから設定変更の要否は決めない。
2. **GPU実行権限と互換性**: KFD/render nodeはあるが現SSHユーザーには読み書き権限がない。HSA/SVMのconfigが有効でもROCmや推論エンジンの動作を保証しない。次回の実行主体・権限方針、GPU ISA、エンジンとの互換性確認が必要。
3. **モデル保存先と起動経路**: 現rootの空きは82Gで、Linux SSD全容量がrootに割り当てられているわけではない。VGの空きや将来の保存先は未調査。rootとマウント中ESPは同SSDだが、UEFI起動エントリやWindows SSDに依存しない起動の完全確認は未実施。
4. **GUIなし運用の確認範囲**: 表示マネージャは確認できず主要GUIパッケージも照会範囲では存在しない一方、default targetはgraphical。GUIなしという前提は部分確認にとどまり、今回targetやパッケージは変更していない。
5. **推論環境・性能**: コンテナ/ROCm/llama-serverの各コマンドはPATH上に見つからず、モデル・エンジンの全配置は未調査。モデル起動、ダウンロード、性能・品質測定は未実施。Gufo・Halogen・llama.cppの採否は本調査では判断しない。

## 5. 実施操作・副作用

実行場所と主な操作:

| 実行場所 | 実施内容 |
|---|---|
| Windows開発PC | `AGENTS.md`・指示書・READMEの読込、Git状態/remote/HEAD/差分確認、fetch、指示書commitの包含確認、安全なfast-forward、レポート作成。SSHは `BatchMode=yes`、`StrictHostKeyChecking=yes`、接続timeout 10秒で実行 |
| EVO-X2 Ubuntu（SSH経由） | `hostname`、`id`、`/etc/os-release`、`uname`、`lscpu`、`free`、`/proc/meminfo` の参照 |
| EVO-X2 Ubuntu（SSH経由） | `lspci` のGPU関連出力、`ls` によるデバイス属性、`lsmod` のAMD関連行、既存kernel configとGPU sysfs数値の参照、`test` によるパス/権限確認 |
| EVO-X2 Ubuntu（SSH経由） | `lsblk` の指定列、`findmnt` でroot/ESP、`df -h /` を確認。別SSD内のファイルは参照していない |
| EVO-X2 Ubuntu（SSH経由） | `systemctl is-active/is-enabled/get-default/show/list-units` の読み取り、`command -v`、`python3 --version`、限定した `dpkg-query` |

**EVO-X2の設定変更なし。** ソフトウェア導入、モデル取得、サービス操作、権限/グループ変更、マウント、BIOS/EFI/GRUB変更、ネットワーク変更、再起動、ベンチマークは行っていない。実機へのスクリプト・一時ファイル・生ログの保存も行っていない。sudoは使用していない。

SSHアクセスに伴う通常のOSログ等の自動記録は発生し得るが、意図的な実機ファイル作成・設定変更は行っていない。ホストの切戻し操作は不要。Windows側では既存cloneのGit更新と本レポートの作成を行った。コード・指示書・他プロジェクトのファイルは変更していない。

## 6. Git成果物・受渡し

- 変更ファイル: `docs/investigation/2026-10/2026-10-15_initial_environment_survey.md`（新規1ファイルのみ）。
- commit前に本文、`git diff --check`、`git status --short`、stageした対象差分を確認し、本ファイルだけを明示的にstageする。
- 実際のcommit SHA、push結果、push後の `origin/main` 包含確認: **最終チャットで報告**。本文確定時点ではこれらは未実施。
- 残課題: 上記の未確認事項、およびChatGPTによるGitHub上のレポートレビュー。次の承認済み指示書なしに環境構築へ進まない。
