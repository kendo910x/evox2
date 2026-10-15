# Halogen Flash-Next 常駐化・OS起動時自動起動 指示書

作成日: 2026-10-15

## 1. 目的と指示情報

| 項目 | 指定 |
|---|---|
| repository / 正本 | `kendo910x/evox2` / `origin/main` |
| 指示書作成基準commit | `65d897355b66b3d3f08331199df74f5148eae19f` |
| Codex開始基準commit | **本指示書を含むChatGPT commit**（受渡しチャットでSHAを通知） |
| instruction publisher | ChatGPT |
| primary executor / controller | Windows開発PC上のCodex |
| 対象実機 | SSH alias `evox2` で接続するEVO-X2 Ubuntu Server |
| 必ず読む資料 | `AGENTS.md`、本指示書、`docs/investigation/2026-10/2026-10-15_halogen_flash_initial_deployment.md`、`deploy/halogen-flash/run.sh` |
| tracked write scope | `deploy/halogen-flash/halogen-active.container`（新規）、`docs/investigation/2026-10/2026-10-15_halogen_systemd_boot_service.md`（新規）の2ファイルのみ |
| 実機の変更範囲 | 対象rootlessユーザーのlinger、Quadlet構成、必要な場合の対象UIDだけのsystemd memlock上限、指定コンテナの起動・正常停止、条件付き1回のUbuntu再起動 |
| 今回のモデル | 既存Flash-Next標準v2 HGN、Halogen `0.18.4`のみ |
| 対象外 | 27B Dense導入、2モデル同時ロード、JIT/切替API、LAN API公開、画像/長文品質検証、性能チューニング |

**主目標:** Linuxを起動すればHalogen Flash-Nextが自動起動し、**最後のSSHセッションが切断されても稼働を維持**する。異常時の無条件・無限再起動は行わない。

**将来の運用設計:** 次回起動するモデルはOS再起動前に手動で選択し、**起動される推論コンテナは常に1つ**とする。今回はその基盤として、単一の `halogen-active.container` → `halogen-active.service` をFlash版として設置する。Denseの実装・モデル切替コマンドは別task。複数のsystemdサービスをenableして起動競合させる構造にはしない。

**承認済み設計:** rootless Podman **Quadlet** を採用する。Ubuntu 26.04.1、Podman 5.7.0。Quadletの生成serviceは通常の`systemctl --user enable`対象ではない。起動時の選択はQuadlet定義にある`[Install] WantedBy=default.target`と、後日「どのモデルのQuadlet定義をactiveに置くか」で管理する。

## 2. 完了条件

1. 既存のモデル・GPU設定・API仕様・ポート（host `127.0.0.1:8731`）が変わらない。
2. rootless Quadletで `halogen-active.service` を起動でき、`/health`、`/v1/models`、Thinking ONの日本語短問で正常応答する。
3. SSH接続を閉じてもサービスが稼働し、別のSSHからAPIとsystemdの状態を確認できる。Linger=yes。
4. Ubuntuの次回起動時に、SSHログイン前からFlashが起動していることを実証する。起動先UEFIに不確実性がある場合は**勝手にrebootせず、ユーザーに手動Ubuntu起動を依頼する保留状態**でよい。
5. systemdがコンテナ終了を正しく検知する。正常停止でGPUメモリが解放され、restart loopが生じない。
6. Git管理のQuadlet定義と実機の定義が一致し、実施レポートが`origin/main`へcommit/pushされている。

**性能:** 過去の短文Thinking ON 61～70 tok/sは既知の参考値。今回は新しい性能目標を置かず、サービス方式の変更でThinking、MTP、checkpoint、context等を無断変更しない。検証は最小限にする。

## 3. 受領・開始時の必須確認

- **Windows開発PC:** `AGENTS.md`、指示書、前回レポートと`run.sh`を読む。対象checkout、branch、HEAD、remote、`git status`を確認。`git fetch origin main`後、指示書commitが`origin/main`に含まれることを確認する。実際に競合するtracked変更があれば停止。別task変更の破棄・stash・resetを行わない。
- **EVO-X2 Ubuntu:** `ssh evox2`と`sudo -n true`、実際のOS、一般ユーザー、rootless Podmanとモデルファイルの存在、`/srv/llm`のmount、render/KFD権限、Quadlet generatorの有無、user manager/linger、memlock、port 8731と既存の`podman ps -a`を必要最小限のread-only操作で確認。
- BIOSのUMA固定値2GiB、Linux RAM約121GiB、rootless Podmanのgraphroot、モデルSHA-256照合済みという既存の成功証拠を再利用する。理由のない110GiB再hash・ダウンロード・全面調査は不要。
- Host起動設定をread-onlyで確認。`efibootmgr`が既に利用可能ならBootCurrent/BootOrderを確認する。未導入なら今回のために新規導入しない。**Ubuntuが再起動後も選択されると確認できない場合、Codexは再起動しない。**
- 後述のUbuntu再起動は、現行のSSH疎通に一時的な影響を与えると認識したうえで行う。Windows開発PC・別マシンへの操作はしない。

参照する公式仕様:
- Podman Quadlet: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
- Podman stop: https://docs.podman.io/en/latest/markdown/podman-stop.1.html
- Halogen host運用: https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/host-setup.md
- Halogen troubles: https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md
- systemd user manager: https://manpages.ubuntu.com/manpages/resolute/man5/systemd-user-runtime-dir.5.html

## 4. Phase A: Quadlet定義とメモリ制限

### A1. 固定された構成

Windowsのrepoに `deploy/halogen-flash/halogen-active.container` を作成する。起動先実機では対象SSHユーザーの `~/.config/containers/systemd/halogen-active.container` へコピーする。別の永続rootful unitを作らない。今ある`run.sh`は変更せず、**systemd管理中に手動起動して二重起動しない**。既存のデータは削除しない。

Quadlet定義はPodman 5.7.0でサポートされる項目に限定して、既存の動作を再現する。最低要件:

```text
[Unit] / [Container] / [Service] / [Install]
Name: halogen-active.container -> halogen-active.service
image: ghcr.io/peonist-ai/halogen-flash-server:0.18.4
pull: never
container name: halogen-flash (既存の手動版との誤二重起動を防ぐ)
model: /srv/llm/models/halogen-flash → /models:ro
HALOGEN_CHECKPOINT=/models/qwen38-flash-next-v2.hgn
HALOGEN_DOWNLOAD: unset
GPU: /dev/kfd, /dev/dri (keep-groups)
IPC: host
memlock: unlimited in container
host publish: 127.0.0.1:8731:8731 のみ
boot: [Install] WantedBy=default.target
service restart: no
```

`/srv/llm`が未mount、モデル欠損、権限不正、image欠損の場合は**既定rootディレクトリ等に書き込んで誤起動しない**。systemdの`ConditionPathIsMountPoint`やQuadletの既存機能等を利用して、読み取り専用の起動前確認を加える。単純な検証でよく、新たな管理daemon/frameworkは作らない。

Quadletに`--ipc=host`相当の専用キーがない場合だけ、generatorがサポートする最小限の`PodmanArgs`を利用してよい。実機での`systemctl --user daemon-reload`と生成unitの検査で、正しい起動引数を確認する。設定項目が未対応なら推測のキーを追加せず原因と選択肢を報告する。

**GPUメモリ保全:** `Restart=no`。Halogenの自動restartループは絶対に作らない。停止時はSIGTERM等で正常終了しGTTを解放することを優先する。Podman/Quadletの`StopTimeout`、systemdの`TimeoutStopSec`、`KillMode`の実効値を確認する。**既定の短いタイムアウトによってSIGKILLへ移行する設定を無検証で採用しない。** `--time=-1`相当がQuadlet側で表現できるか、小さな非破壊の起動/停止検証またはgenerator出力で確認し、未対応の場合は安全な代替設計を提示して停止する。無限待機設定がOS shutdownを妨げる可能性もレポートに明記する。

### A2. memlockとlinger

- 現在のSSHログインではmemlock soft/hardがunlimitedだが、systemd --userマネージャーは異なるresource limitを継承することがある。**まずread-onlyで**`user@<UID>.service`のlimit、ユーザーマネージャーのプロセスlimit、生成された`halogen-active.service`のLimitMEMLOCKを調べる。
- systemdユーザーマネージャー側のhard limitが十分でなければ、**当該UID専用**のsystem unit instance drop-in `/etc/systemd/system/user@<UID>.service.d/90-halogen-memlock.conf` に`[Service] LimitMEMLOCK=infinity` を設定することを許可する。必要なら対象Quadletの`[Service] LimitMEMLOCK=infinity`も設定する。他ユーザー全体の`user@.service`変更、sudoers、PAM、/etc/security/limits.d既存規則の変更は禁止。
- 設定反映のために実行中の`user@<UID>.service`をSSH越しに強制restartしない。次回の**承認されたUbuntu再起動**後に新しいユーザーマネージャーで有効なlimitを検証する。再起動前に無理なlive workaroundを増やさない。
- 対象ユーザーの `sudo loginctl enable-linger <user>` のみ許可。既に有効なら再設定不要。`loginctl show-user`等でLinger=yesを確認する。変更によるユーザーマネージャーの永続化・自動起動という副作用を記録する。

### A3. 生成unitの検証

- rootless Podmanのcgroup v2、group、mount、port、image、memlock制限を検証する。
- Quadlet generatorが `halogen-active.service` を正しく生成することを`systemctl --user daemon-reload`、`systemctl --user cat`、generator dry-runなどで確認する。
- **Quadlet generated unitには通常`systemctl --user enable`を使わない。** `[Install] WantedBy=default.target`がgeneratorにより反映され、次のuser-manager起動時にpullされることを確認する。
- 設定ファイルはGit上の内容とハッシュ一致させる。データはすべて既存配置を再利用、追加ダウンロードはしない。

## 5. Phase B: 起動・切断・再起動の確認

**開始条件:** Phase AのQuadlet、memlock、停止方法、lingerを確認でき、GPUに他の大きな推論プロセスがいない。port 8731は未使用。既存のFlashコンテナがある場合は状態・所有者を確認し、無断停止しない。

### B1. systemd起動と短いAPI確認

- `systemctl --user start halogen-active.service`で起動する。起動確認は`active`だけでなく、`GET /health`がready、`GET /v1/models`とThinking ONの日本語短問で正常回答が出ることを確認。
- systemdがコンテナ/engineの実際の存続を把握していることを確認。モデル、MTP、Thinking、KV/Context設定、image ID/モデル識別が以前の正常動作から変わっていない。
- APIは引き続き`127.0.0.1:8731`のみ。Windowsから利用する場合は**SSHローカルポート転送**で検証。認証なしでLANの`0.0.0.0`へ公開しない。

### B2. SSH切断耐性と正常停止

- Codexの操作SSHセッションを終え、新規接続して、Halogenが稼働・API応答を継続していることを確認。Linger=noの失敗が再発していないか、user-manager状態を調べる。
- 次に、実行中のAPIリクエストがなく、Halogen自身がidleと確認した状態で、`systemctl --user stop halogen-active.service`を1回実行。正常終了と、コンテナ消滅、port消失、GTT usedが開始時付近に戻ることを確認する。**停止が固まったらforce kill/rebootをせず停止して報告**する。
- 正常停止を検証した後、`systemctl --user start halogen-active.service`で再起動してreadyを確認する。この時点でも異常時自動restartは無効のまま。

### B3. OS再起動による自動復帰

- **今回はUbuntuホストに対する計画的なOS再起動を最大1回許可する。** ただしBootOrder・BootNext・既定OSがUbuntuへ戻る確証がない場合、Codexは再起動せず`WAITING_FOR_USER_REBOOT`としてレポートを提出する（ユーザーが物理画面のF7等でUbuntu起動）。UEFI設定を変更しない。
- systemd経由の正常停止が検証済みで、コンテナに実行中リクエストがないこと、user-managerのmemlock設定とlingerが永続化済みであることを確認してから再起動する。Windows開発PCやほかのホストを再起動しない。
- 再起動後、**SSHでserviceを手動起動する前に**`systemctl --user status halogen-active.service`、`podman ps`、`/health`を取得し、自動起動が成立したことを確認。memlock、model readiness、KFD/render、GTT used、systemd journalに明らかなOOM/GPU faultがないか短く確認する。
- OS起動後にサービスが失敗していたら、原因を記録し、無制限再試行、GPU driver変更、もう一度の再起動はしない。必要に応じて**本taskで新規作成したQuadletの起動設定だけ**を元へ戻して報告する。既存モデルやPodman graphrootは削除しない。

**最終状態:** 成功した場合は `halogen-active.service` を有効な自動起動状態で稼働させ、SSHを閉じても維持する。これは承認済みの実験サーバ常用化であり、重い負荷試験や性能最適化の許可ではない。

## 6. 今回の禁止事項・停止条件

禁止: Windows SSD/EFI/UEFI/BootOrder変更、BIOS UMA、カーネル/ROCm/firmware変更、全面apt upgrade、サービス無制限restart、watchdogの独自実装、kernel/tuning変更、model/quantization変更、無認証LAN/WAN API公開、他repoやv3への操作、追加モデルダウンロード、systemd system全体や全ユーザーへmemlock緩和。

停止条件: 実行ホスト・Git write scope不明、既存サービスの競合、memlock継承不能、Quadletが正しい起動/停止を生成できない、modelの読み込み失敗、GPUメモリ未解放、SSH障害、boot対象が確定しない、rootlessやポート制限を守れない、実際のGit競合、未承認の高影響操作が必要。

本taskは**起動時の自動起動と切断耐性の導入**であり、切り替え方式の完成ではない。後続Dense版は別指示書で導入し、Flash版が稼働中にDenseを同時起動しない。将来はactive Quadlet定義のみをFlash/Dense間で変更して再起動する予定。

## 7. 実施レポート・commit/push

レポート: `docs/investigation/2026-10/2026-10-15_halogen_systemd_boot_service.md`

必須記録:
- 指示書SHA、作業実施主体、Windows側開始HEAD/branch、他task変更、対象ホスト確認の方法（公開repoなのでローカルIP、ユーザー名、UUID、認証情報は書かない）。
- 採用したQuadletと実際の生成systemd unitの内容の重要点、image/checkpoint/port、rootless、memlock継承・linger。
- `[Install]`による起動時登録がどのように生成されたか、`Restart`と停止タイムアウトの実効値。
- `systemctl --user start/stop`・SSH切断・OS再起動後の自動起動・API/Thinking ONのPASS/FAIL/未実施。
- 正常停止前後のGTT、関連サービスの状態、systemd journalの重要な警告、メモリ残量の観測範囲。
- 新規作成/変更した実機ファイル、drop-in/linger等の副作用、削除・切戻し方法（実行していない削除は未実施と記す）。
- `WAITING_FOR_USER_REBOOT`になった場合は、その理由とユーザーが行う操作、再開時に実施済み手順を繰り返さないこと。
- tracked変更ファイル2件だけの差分確認、commit SHA、origin/main push・包含確認（自己commit SHAの記載は最終チャット報告でよい）。

コード・設定・実施レポートだけをGit管理し、model binary、コンテナイメージ、cache、生ログ、秘密情報は絶対にcommitしない。対象pathを明示的にstageし、`git diff --check`を実行。差分と指示書の整合を確認してから`origin/main`へpush。完了後はChatGPTへ、レポートURL、commit SHA、最終の起動状態、残課題を報告する。
