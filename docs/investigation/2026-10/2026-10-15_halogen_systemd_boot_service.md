# Halogen Flash-Next 常駐化・OS起動時自動起動 実施レポート

## 1. 結果

**状態: `BLOCKED_SAFE_STOP_DESIGN`。常駐化は未完了。** Podman 5.7.0のQuadlet停止設定について、承認済み指示書が求める `--time=-1` 相当の安全な停止を標準の `StopTimeout` では実現できないことを実機で確認した。指示書A1の「未対応の場合は安全な代替設計を提示して停止する」に従い、代替設定の適用・Halogen起動・Ubuntu再起動には進んでいない。

既存モデル、image、run.sh、GPU設定、memlockの既存設定を維持。コンテナは停止中、8731のlistenなし、Linger=noのままである。OS起動時の自動起動やSSH切断後の継続稼働をPASSとは扱わない。

## 2. 実施条件

- 作業日: 2026-10-15、13:14 JST以降。実行主体はWindows開発PC上のCodex。実機コマンドはSSH alias `evox2` 経由のEVO-X2 Ubuntu上で実行した。
- 指示書: `docs/instructions/2026-10/2026-10-15_halogen_systemd_boot_service_instruction.md`。
- 指示書commit: `5157c0f9e4a72e0de51e47f25cfd6077039d4a95`。
- Windows checkout: `kendo910x/evox2`、branch `main`、開始HEAD `65d897355b66b3d3f08331199df74f5148eae19f`、作業ツリーclean。他タスクのtracked変更なし。
- `AGENTS.md` を先に読み、fetchで指示書commitの `origin/main` 包含を確認し、fast-forwardした。指示書、前回実施レポート、`deploy/halogen-flash/run.sh` を確認した。前回のモデルhash照合・Thinking ON成功証拠を再利用した。
- 実hostname・アカウント・group・OSを実機で照合。公開レポートでは実ユーザー名、UID、LAN情報、UEFI/ディスクUUIDを省略する。

## 3. 読み取り確認

| 項目 | 結果 |
|---|---|
| SSH / sudo | 新規SSH接続と `sudo -n true` が成功 |
| OS / kernel | Ubuntu 26.04.1 LTS / `7.0.0-38-generic`。変更していない |
| RAM / UMA | MemTotal=127098452 kB（約121.21 GiB）、MemAvailable=125015272 kB。GPU固定VRAM=2147483648 bytes（2 GiB） |
| GPU | `/dev/kfd` と `/dev/dri/renderD128` のread/write可、render所属を確認。GTT used=18661376 bytesで前回正常停止後と一致 |
| mount / disk | `/dev/mapper/ubuntu--vg-llm_data` が `/srv/llm` にext4/rwでmount。データ空き659 GiB、root空き82 GiB |
| model | v2=66687678432 bytes、ngram=51200246144 bytes、vision=897916416 bytes。前回hash照合済みの既存ファイルを再利用する前提を確認。大容量の再hash・取得はしていない |
| image | 指定0.18.4が存在。ID `556c3c8179d8a566cc0ec0a7f7f54f9f3cb8b77e7bc4a4175e7c23ae359ad80a`、digest `sha256:1a458cd6decdd3a2c27f96196cc3a0bc853cbb3905320c3461d29137072faa78`。前回と一致 |
| Podman | 5.7.0、rootless=true、cgroups=v2、runtime=crun、graphroot=`/srv/llm/containers/podman` |
| 既存runtime | `podman ps -a` は空、8731未使用。既存Halogen user unitとユーザーのQuadlet定義はなかった |
| generator | `/usr/libexec/podman/quadlet`。system generatorとuser generator（`podman-user-generator`）の登録を確認 |
| linger | Linger=no。今回変更していない |

### 3.1 memlock

SSHのsoft/hardはunlimited。`systemctl show user@<UID>.service` の設定表示はLimitMEMLOCK/Softとも8388608 bytesだったが、**実際のユーザーマネージャープロセス** `/proc/<MainPID>/limits` のMax locked memoryはsoft/hardともunlimited、`systemctl --user show` のDefaultLimitMEMLOCK/Softもinfinityだった。

PAM経路を読み取り確認すると、system unitは `PAMName=systemd-user`、vendorファイル `/usr/lib/pam.d/systemd-user` に `session required pam_limits.so` があった。前回の対象ユーザー専用limits.d規則が実効値へ適用されていると判断する。`/etc/pam.d/systemd-user` は存在せず、vendor側を確認した。設定表示8 MiBだけを根拠に「実効hard limit不足」とは扱わない。

現時点で実効上限は足りているため、UID専用memlock drop-inは追加していない。ユーザーマネージャーをrestartせず、PAM・limits.d・全ユーザー設定も変更していない。Quadletサービス/コンテナへの継承と、boot後の新しいマネージャーの実効値は未検証である。

### 3.2 起動先

既存 `efibootmgr` を読み取り実行し、BootCurrentはUbuntuエントリ、BootOrderの先頭も同じUbuntuエントリ、BootNextの指定なしを確認した。GRUBは `GRUB_DEFAULT=0`、先頭menuentryはUbuntu、grubenvにnext_entry/saved_entryはなかった。BootOrder・BootNext・GRUB・UEFIへ書き込んでいない。

したがって今回の停止理由はUbuntuの起動先不確実性ではない。**正常停止方式のgateが未達なので再起動を実施していない**。ユーザーに先に再起動してもらえば解決する状態ではなく、`WAITING_FOR_USER_REBOOT` とも区別する。

## 4. 停止設定の実機検証

### 4.1 実施方法

**[Windows開発PC]** Podmanの公式v5.7.0ソースでgeneratorの実装を確認した。**[EVO-X2 Ubuntu/SSH]** 当該ユーザーのruntime領域に一時ディレクトリを作り、最小の `halogen-active.container` 候補を置き、`QUADLET_UNIT_DIRS` をその一時ディレクトリだけに限定して次を実行した。

```bash
# [EVO-X2 Ubuntu] 一時候補のみを読むdry-run。通常の探索先へは配置しない。
QUADLET_UNIT_DIRS=<temporary-directory> \
  /usr/libexec/podman/quadlet --user --dryrun
# CLI引数のparseだけを確認。--helpなのでコンテナは起動しない。
podman run --stop-timeout=-1 --help
```

候補には指定image、Pull=never、ContainerName=halogen-flash、StopTimeout=-1、Restart=no、LimitMEMLOCK=infinity、TimeoutStopSec=infinity、KillMode=mixed、WantedBy=default.targetを入れた。モデル/GPUを渡す必要のないgenerator検証であり、実際の起動候補として配置したものではない。一時ファイルとディレクトリはPythonのTemporaryDirectory終了時に削除され、残っていない。

### 4.2 結果

generator自体は終了コード0だったが、次の引数を生成した。

```ini
Restart=no
LimitMEMLOCK=infinity
TimeoutStopSec=infinity
KillMode=mixed
Type=notify
NotifyAccess=all
ExecStop=/usr/bin/podman rm -v -f -i halogen-flash
ExecStopPost=-/usr/bin/podman rm -v -f -i halogen-flash
# ExecStartの主要部分（順序は実出力どおり）
# podman run --name halogen-flash --replace --rm --cgroups=split \
#   --stop-timeout -1 --pull never --sdnotify=conmon -d <指定image>
```

CLI parseは**終了コード125**、`invalid argument "-1" for "--stop-timeout" flag: strconv.ParseUint: parsing "-1": invalid syntax`。`podman run --help` でもstop-timeoutの型はuintである。`StopTimeout=-1` はgeneratorの構文検査だけでは検出できず、実際のPodman起動が失敗する設定だった。

また、生成unitのExecStop/ExecStopPostは `podman rm -f` であり、要求した `podman stop --time=-1` ではない。`podman rm --help` はforce removal、timeの既定値10秒と表示する。`TimeoutStopSec=infinity` をQuadletのServiceに足すだけで、Podman側の強制終了経路までなくなったと判断できない。未検証の巨大な数値へ置き換える、生成結果の強制削除をそのまま使う、といった対応はしていない。

### 4.3 親ユーザーマネージャーの停止制限

加えて実機の `user@<UID>.service` はvendor drop-in `/usr/lib/systemd/system/user@.service.d/timeout.conf` により、次の実効値だった。

```text
TimeoutStopUSec=5s
KillMode=mixed
SendSIGKILL=yes
```

Halogenの子serviceだけを無限待機にしても、OS shutdownで親ユーザーマネージャーが5秒の停止期限に達すると、親cgroup側から強制終了される可能性が残る。GPUメモリ解放を優先する停止設計は親側も含めて決める必要がある。この親設定の変更は、今回許可された「必要な場合の当該UIDだけのmemlock変更」とは別なので実施していない。

## 5. 再開に向けた具体案（未適用・要承認）

Quadlet採用・単一activeサービスという設計は維持し、**生成serviceに対する専用drop-inで停止処理を置き換える方式**を提案する。生成された一時unitを直接編集する方式ではない。

1. `halogen-active.container` は承認済みimage・ROモデル・GPU・IPC・loopback公開・Restart=no・WantedBy=default.targetを定義する。`StopTimeout=-1` は使わない。同名手動コンテナがあれば起動を拒否する確認を加え、generatorの `--replace` による置換を防ぐ。mount・モデル・image・GPU権限・memlockも起動前に確認する。
2. **追加の実機path** `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf` に、以下のような停止overrideを置く。これは代替案の具体化であり、今回生成unitへ適用・検証した設定ではない。

   ```ini
   [Service]
   ExecStop=
   ExecStop=/usr/bin/podman stop --ignore --time=-1 halogen-flash
   ExecStopPost=
   ExecStopPost=-/usr/bin/podman rm --ignore halogen-flash
   TimeoutStopSec=infinity
   KillMode=mixed
   SendSIGKILL=no
   ```

   ExecStopを明示的な正常停止へ変更し、ExecStopPostから `--force` を除く。正常停止後は `--rm` 済み、または停止済みcontainerだけを掃除する。起動失敗時にも実行され得るExecStopPostが、同名の稼働containerを強制削除しない構成にする。実装時には実効unitを再検査し、小さな検証または指定Halogenのidle状態で正常停止を確認する。
3. **追加の実機path** `/etc/systemd/system/user@<UID>.service.d/90-halogen-stop.conf` に対象UID限定で `[Service] TimeoutStopSec=infinity` と `SendSIGKILL=no` を設定する案を検討する。全ユーザーのtemplateは変更しない。system managerのdaemon-reload後に実効値を確認し、実行中のuser managerを強制restartしない。
4. これらのdrop-inのtracked保存先を指示書のwrite scopeへ追加する必要がある。例: `deploy/halogen-flash/halogen-active.service.d/90-safe-stop.conf` と `deploy/halogen-flash/user-manager-stop.conf`。実UIDやユーザー名はGitへ保存しない。
5. 承認後、Quadletとdrop-inを生成・照合、lingerを対象ユーザーだけ有効化し、memlock実効値を再確認する。Phase Bの起動/API、SSH切断耐性、idleからの正常停止/GTT解放、再起動を順に検証する。boot選択は再照合し、条件を満たした場合だけ未使用の計画再起動枠（最大1回）で自動復帰を確認する。

**トレードオフ:** 無限待機と強制kill禁止は、GPU/engineが終了不能になった場合にサービス停止やOS shutdownを長時間・無期限に待たせ得る。復旧は状況確認とユーザー判断が必要であり、無条件のkill/reboot/restartへは進まない。今回の案はその待機を明示的に選ぶものであり、採用には追加の操作範囲・運用上の判断が必要である。

## 6. 検証一覧・最終状態

| 検証 | 判定 | 証拠・理由 |
|---|---|---|
| 指示書包含・Git競合なし | PASS | fetch・ancestor確認・fast-forward成功 |
| 既存モデル/image/保存先/GPU権限 | PASS | 前回の識別と実ファイルsize、image ID/digest、rootless/cgroup v2を確認 |
| SSH/user managerのmemlock | PASS（現時点） | 実プロセスのsoft/hardはunlimited。Quadlet内・boot後は未検証 |
| Ubuntuへ戻る起動設定 | PASS（観測時点） | UEFIの先頭/現在、BootNextなし、GRUB default/先頭entryがUbuntu |
| StopTimeout=-1のgenerator変換 | PASS（変換だけ） | dry-runは0。動作の保証にはならない |
| StopTimeout=-1のPodman互換性 | FAIL | 符号なし整数parserが拒否、終了コード125。GPU起動前に検出 |
| 安全な正常停止方式 | 未成立 | 生成rm -fと親user managerの5秒期限を解消する追加設計が必要 |
| Quadletの恒久配置・default.target登録 | 未実施 | 停止方式が未成立のため、生成unitを有効化しない |
| linger変更 | 未実施 | Linger=noを維持 |
| systemd start/stop、今回のThinking ON API | 未実施 | Phase B開始gate未達。前回のAPI成功を今回の成功に流用しない |
| SSH切断耐性、今回のGPU解放 | 未実施 | 今回はHalogenを起動していない |
| OS再起動・boot後API自動復帰 | 未実施 | 再起動0回。安全な停止方式の承認・検証が先 |
| 最終のHalogen状態 | 停止中 | container一覧空、8731 listenなし。再起動ループなし |

初回のpreflightではHalogen unit検索が0件であるためコマンド全体が非zeroとなった。また `/etc/pam.d/systemd-user` とパッケージ一覧に出る圧縮manファイルは実ファイルがなく、vendor PAMと公式ソース/実行ファイルの出力で確認を続けた。これらは読み取り確認の経路差であり、設定・サービスの変更は発生していない。

## 7. 変更・切戻し・Git

- Ubuntuに残した新規の恒久ファイル・設定は**なし**。linger、Quadlet配置、systemd drop-in、サービス操作、apt、モデル/image取得、既存run.sh変更、rebootはいずれも行っていない。
- generator検証の一時候補はruntime領域で自動削除済み。既存モデル・cache・graphrootは削除していない。今回のための恒久設定の切戻しは不要。
- 代替案を後日実装した場合の切戻しは、idle状態から正常停止・GTT解放を確認し、そのtaskで作るQuadletと2つの専用drop-inだけを除去して各managerをdaemon-reloadする手順となる。lingerを戻す場合も当該ユーザーの他用途がないことを確認する。今回はこれらの削除を実行していない。
- 今回のtracked変更は本レポート**1ファイルのみ**。許可対象の `deploy/halogen-flash/halogen-active.container` は、安全な実装を確定できなかったため作成・commitしない。動作しないStopTimeout=-1の候補を本番用設定として残さない。
- 対象差分・秘密情報・`git diff --check`を確認し、本レポートだけを明示的にstageしてcommit/pushする。実際のcommit SHA、pushと `origin/main` 包含確認は最終チャットで報告する。
- 再開時は更新済み指示書を確認し、既存モデル・前回の準備作業を再実行しない。今回の検証済み事実を利用し、必要な停止設計の変更とPhase Bに進む。

## 8. 参照

- [Podman Quadlet公式仕様](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)。user配置先、generator、Install処理とStopTimeoutの意味を参照。実機の5.7.0を最終判定に使用。
- [Podman v5.7.0 Quadlet実装](https://github.com/containers/podman/blob/v5.7.0/pkg/systemd/quadlet/quadlet.go)。StopTimeoutがrunのstop-timeoutへ渡され、ExecStop/ExecStopPostにrm -fが追加される実装を実機dry-runと照合。
- [Podman stop公式仕様](https://docs.podman.io/en/latest/markdown/podman-stop.1.html)。stopのtime=-1は無限待機であり、runの符号なしstop-timeoutとは区別する。
- [Ubuntu user manager仕様](https://manpages.ubuntu.com/manpages/resolute/man5/systemd-user-runtime-dir.5.html)。実効limit・停止期限は当該ホストのunit/proc/PAMも照合した。
