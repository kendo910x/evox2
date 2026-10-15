# Halogen Flash-Next 常駐化・OS起動時自動起動 実施レポート

> **ネットワーク設定の最新追補:** 同日13:56 JST、ユーザーの追加明示指示に従い `PublishPort=0.0.0.0:8731:8731` へ変更・実機反映した。正常停止・GPU解放後にサービスを起動し、WindowsからSSH転送なしのLAN直接接続を確認済み。詳細は **第12節**。それ以前のloopback限定・設定hashは当時の履歴である。

> **最新状態: `PASS / RUNNING`（2026-10-15 再開追補）。** 更新指示書commit `88dfed241f2042c975f9c3b208536246c8409eb5` に従い、QuadletとHalogen専用停止drop-inを配置した。正常停止・GTT解放、SSH切断耐性、OS再起動1回後のログイン前自動起動、Thinking ON APIを実証した。最終状態は `active/running`、Linger=yes、Restart=no。詳細は **第9節以降**。第1～8節は前回の停止調査の履歴であり、当時の未実施・要承認の記載を保持している。親ユーザーマネージャーを変更する旧提案は採用していない。

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

## 9. 再開追補: 実施条件と採用構成

### 9.1 受領・最小限の再確認

- 実施日: 2026-10-15、13:31～13:40 JSTに実機検証。その後レポート追補・Git反映。実行主体はWindows開発PC上のCodex、実機操作は `ssh evox2` 経由のEVO-X2 Ubuntu。公開レポートへ実ユーザー名、UID、LAN情報、UUID、認証情報は保存しない。
- 指示書pathは第2節と同じ。今回実行した版は **`88dfed241f2042c975f9c3b208536246c8409eb5`**。前回レポートcommitは `cff21e783898e14b6622c5619c58426fad3e4beb`。
- Windows側開始branch=`main`、開始HEAD=`cff21e783898e14b6622c5619c58426fad3e4beb`、作業ツリーclean。他タスク変更なし。`AGENTS.md` を先に読み、fetch・ancestor検査後に更新指示書commitへfast-forwardした。更新指示書、前回停止調査、初回導入成功レポート、既存run.shを確認した。
- SSH/sudo、実OS・アカウント、既存mount、rootless Podman/cgroup v2、image識別、モデルの存在・size、GPU権限、manager実効memlock、ポート・コンテナ競合なしだけを再確認した。モデルの110 GiB再hash、再取得、ディスク全面調査は行っていない。
- 開始時は既報と同じUbuntu 26.04.1 / kernel `7.0.0-38-generic`、Linger=no、Halogen停止、GTT=18,661,376 bytes。配置対象2ファイルがないことを確認してから作成した。
- 親 `user@<UID>.service` は前回どおり `TimeoutStopUSec=5s / KillMode=mixed / SendSIGKILL=yes`。実managerのMax locked memoryはsoft/hardともunlimited。親設定、PAM、limits.dへの変更やmanager restartは行っていない。

### 9.2 配置した2ファイル

| tracked正本 | 実機配置（対象rootlessユーザー） | SHA-256（Windows・実機・boot後で一致） |
|---|---|---|
| `deploy/halogen-flash/halogen-active.container` | `~/.config/containers/systemd/halogen-active.container` | `49723c646d114b70e15f33eaacbcdcf5c10c9c7375aac6620da3265201b13f2b` |
| `deploy/halogen-flash/halogen-active.service.d/90-safe-stop.conf` | `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf` | `790f8cc28a2c035c32a9436745bd946f00dc2ea9c088d5c5851cbface958605e` |

停止drop-inを先に配置し、Quadlet配置後に `systemctl --user daemon-reload`。両ファイルmode=0644。必要な親ディレクトリだけを作成した。対象ユーザーだけ `sudo -n loginctl enable-linger <対象ユーザー>` を実行し、Linger=yesと永続lingerファイルを確認した。

構成は固定image `ghcr.io/peonist-ai/halogen-flash-server:0.18.4` / Pull=never、container名 `halogen-flash`、既存モデルディレクトリを `/models:ro`、checkpoint=`/models/qwen38-flash-next-v2.hgn`、HALOGEN_DOWNLOAD未設定。image IDは `556c3c8179d8a566cc0ec0a7f7f54f9f3cb8b77e7bc4a4175e7c23ae359ad80a`、digestは `sha256:1a458cd6decdd3a2c27f96196cc3a0bc853cbb3905320c3461d29137072faa78` で初回導入時と一致する。今回のネットワーク取得はない。Podman journalにはローカルimage選択時にも `image pull` というイベント名が出たが、生成ExecStartは `--pull never` で既存IDを使用している。

`/dev/kfd`・`/dev/dri`、keep-groups、IPC=host、memlock=-1:-1を指定し、ホスト公開は **127.0.0.1:8731のみ**。コンテナ内の0.0.0.0:8731というAPIログをホストのLAN公開と混同しない。inspectでROモデルmountとloopbackのPortBindings、実際の `ss` でもloopback bindを確認した。

mountpoint、既存graphrootディレクトリ、v2/ngram/tokenizerの可読・非空、GPUデバイスのread/write、非root/rootless、soft/hard memlock、既存image、同名コンテナなし、8731未使用を起動前に確認する。`ConditionPathIsMountPoint=/srv/llm` により未mount時は起動しない。generatorの `--replace` より先に同名の稼働中・停止済みコンテナを拒否する。

### 9.3 生成unitと停止経路

生成unitはType=notify / NotifyAccess=all、MainPIDはconmon、engineは同サービス配下のcontainer cgroupに入る。ExecStartの主要引数は以下であり、不正な `--stop-timeout -1` は含まない。

```text
podman run --name halogen-flash --replace --rm --cgroups=split --pull never
  --ulimit memlock=-1:-1 --group-add keep-groups --sdnotify=conmon -d
  --device /dev/kfd --device /dev/dri
  -v /srv/llm/models/halogen-flash:/models:ro
  --publish 127.0.0.1:8731:8731
  --env HALOGEN_CHECKPOINT=/models/qwen38-flash-next-v2.hgn
  --label io.evox2.halogen.service=halogen-active --ipc=host
  ghcr.io/peonist-ai/halogen-flash-server:0.18.4
```

drop-in適用後の **実効値** は以下。generator本体に残る `podman rm -v -f -i` は、空のExecStop/ExecStopPostによるリセットで両方とも上書きされ、実効停止経路には存在しない。

```ini
ExecStop=/usr/bin/podman stop --ignore --time=-1 halogen-flash
ExecStopPost=-/usr/bin/podman rm --ignore --filter label=io.evox2.halogen.service=halogen-active --filter name=^halogen-flash$$
TimeoutStopSec=infinity
Restart=no
KillMode=mixed
SendSIGKILL=no
LimitMEMLOCK=infinity
```

`$$` はsystemdから実行時に渡すリテラル `$` の表記。ExecStopPostはサービス所有ラベルと完全一致名の両条件を持つ停止済みコンテナだけを非強制削除する。指示書の基本形を、この所有範囲の限定だけ補強した。`--rm` で消滅済みの場合も正常終了する。

既存保護の確認には、既存imageからGPU・モデルなし、network=none、entrypoint=/bin/trueの同名・ラベルなしコンテナを **createだけ** 実行し、起動していない。同名検出の終了コード1を確認し、同じ後処理のlabel/name filterを実行してもID・created状態が維持された。検証用に作った当該IDだけを非強制rmで片付けた。Halogenへの障害注入・強制停止は行っていない。

`systemctl --user cat/show` と `systemd-analyze --user --generators=true verify halogen-active.service` はPASS。最初のverifyでgeneratorsを有効にせず「Unit not found」となったが、適切なオプションで検証成功した。実サービスのLoadStateはloadedで、起動失敗ではない。

`[Install] WantedBy=default.target` により、runtimeの `systemd/generator/default.target.wants/halogen-active.service -> ../halogen-active.service` が生成され、default.targetのWantsにも含まれた。UnitFileState=generatedであり、`systemctl --user enable` は実行していない。boot後にも同じリンクを確認した。

## 10. 再開追補: 起動・停止・再起動の実測

### 10.1 systemd起動とSSH切断

13:35:28 JSTに `systemctl --user start halogen-active.service` が成功。MainPID=conmonでactive/running、containerはrunning。初回warmロードはweights pin 0.7秒、engine内部のmodel ready 2.5秒、engine listening after 4秒。`/health`・`/v1/models` はHTTP 200、engine.responds=true、モデルID一致、Thinking control probe passedだった。

前回と同じcontext=262144、slots=4、KV pool=524288、MTP depth-2、prompt cache mode=2。image・checkpoint・chat template hashは既存値を維持。API/engineとも0.18.4。vision未ロード、独自watchdog追加なし。イメージに元から含まれるwatchdogは既存のまま。

操作SSHを閉じた13:36:02から新規接続13:36:43まで、同一container IDとMainPID・起動時刻を維持し、healthはok、NRestarts=0。セッション確認では操作中のsshdセッション以外はsystemd-userのmanagerセッションだけだった。正常停止検証後も13:37:06にstartし直してSSHを終了、13:37:49の新規接続で同一コンテナ・readyを確認した。最後のSSH終了に伴ってengineが終了する既往事象は再発しなかった。

### 10.2 正常停止とGPU解放

いずれも直前のhealthがbusy=false / in_flight=0 / queued=0であることを確認し、**systemctl経由**で停止した。

| 機会（JST） | 停止前GTT bytes | stopのwall秒 | 停止後GTT bytes | 結果 |
|---|---:|---:|---:|---|
| 13:36:45～46、最初の正常停止検証 | 29,085,544,448 | 1.179 | 18,661,376 | PASS |
| 13:37:50～51、計画再起動の直前停止 | 29,054,521,344 | 1.189 | 18,661,376 | PASS |

両方ともsystemdのResult=success、ExecMainStatus=0、ExecStop/ExecStopPostのstatus=0、inactive/dead、コンテナ一覧空、8731 listenなし、NRestarts=0。journalの `stop requested; shutting down`、engine/APIの正常終了、`GTT in use after the engine exited: 0.0 GiB`、Stoppedを照合した。実行済みExecStopは `podman stop --ignore --time=-1` であり、強制kill・force rmは実行していない。GTTは開始時の18,661,376 bytesに完全に戻った。

### 10.3 1回のOS再起動とログイン前自動起動

既存efibootmgrでBootCurrent=Ubuntu、BootOrder先頭=同Ubuntu、BootNextなしを再確認した。GRUB_DEFAULT=0、最初のmenuentry=Ubuntu、grubenvは空。UEFI/GRUBに変更していない。

第10.2節の2回目停止の後、停止状態・ポート消失・GTT一致・Linger=yesの永続ファイル・default.target登録を確認し、**13:38:00 JSTに `sudo -n reboot` を1回だけ**実行した。Halogenの停止を親managerの5秒期限に委ねていない。Windowsや別ホストへの再起動はない。

再起動後は `start` を一切実行せず、新規SSHで次の証拠を得た。

| 事象 | bootからの時刻（秒） | 証拠 |
|---|---:|---|
| Halogenサービス開始処理 | 6.101 | user journal |
| サービスactive | 6.597 | ActiveEnterTimestampMonotonic・journal |
| weights pin完了 | 45.350 | 62.11 GiB、pin処理34.8秒、1.9 GB/s |
| model ready | 47.407 | engine内部経過36.8秒 |
| API startup complete / listen | 49.733 | user journal |
| 再起動後最初のSSHログイン | 62.015 | 当該sshdセッションのTimestampMonotonic |

最初のSSHは13:39:12 JSTで、サービスは13:38:16から既に稼働。boot時刻の変化も確認した。**API起動完了はSSHログインより約12.3秒早い**。service activeだけでreadyと判断せず、最初の接続から `/health`・`/v1/models` がHTTP 200であることも確認した。coldロードは最初のwarmロードより長いが、起動失敗・restart loopはない。

boot後の実ユーザーマネージャープロセス、コンテナPID 1、実 `flash_serve` プロセスのMax locked memoryはsoft/hardともunlimited。service LimitMEMLOCK=infinity、GPUデバイスのread/write可。既存limits.d規則がログイン前のmanager・コンテナへ継承された。親managerの停止期限5秒・KillMode・SendSIGKILL・vendor drop-in一覧も変更前と同じだった。

起動後GTT=29,054,521,344 bytes、MemTotal=127,102,676 kB（約121.21 GiB）、観測時MemAvailable=95,607,680 kB、swap使用0。MemAvailableはGPUにpinされたweightsを過大評価する既知の表示で、約91 GiBを実用空き容量とは扱わない。engineの内訳はweights 62.1 GiB、KV 14.4 GiB、work 12.5 GiB、合計89.0 GiB、ngram 47.7 GiBはfile cache経由のまま。

boot後kernel journalをOOM/kill・GPU error/fault/reset/timeout/hangの語境界付きパターンで限定確認し、該当0。最初の広いパターンが通常のTMZ disabled `(default)` 行の `fault` 部分へ誤一致したため、語境界付きで確認した。コンテナOOMKilled=false。既知のFastAPI on_event DeprecationWarningは出るがAPIは正常であり、今回修正対象にしていない。この短い確認は全障害の不存在を保証するものではない。

### 10.4 Thinking ON API・Windowsからの疎通

**[EVO-X2 Ubuntu/SSH]** Python標準HTTP clientで逐次2問だけ検証。model=`halogen-qwen3.8-flash-next`、enable_thinking=true、reasoning_effort=low、temperature=0、max_completion_tokens=4096、stream=false、seed/top_p/top_kは未指定。既存構成のMTPを使用した。2問ともHTTP 200 / finish_reason=stop、非空reasoning_contentと正しい日本語最終回答を確認した。思考本文は保存しない。

| 機会・短問 | 最終回答 | input / completion（reasoning）tokens | pp tok/s | tg tok/s | prompt / generation ms | HTTP wall秒 |
|---|---|---:|---:|---:|---:|---:|
| 初回systemd起動後、12人の握手 | 66回、組合せの説明 | 67 / 142（91） | 165.187 | 74.043 | 405.6 / 1917.8 | 2.358 |
| OS再起動後、りんご17個を5人に配る | 一人3個、余り2個 | 74 / 68（56） | 167.686 | 65.815 | 441.3 / 1033.2 | 1.510 |

reasoning_contentは274/180文字。MTP draft/acceptedは125/96と55/43、cache_n=0。tgはThinkingを含むcompletion全体のserver predicted_per_second、wallはclientの全応答受信まで。非streamなのでTTFTは未測定。短い日本語計算2件・low/greedyの疎通確認であり、xhigh/長文の品質・持続速度やWindows実測との厳密比較を主張しない。

**[Windows開発PC]** 30秒で自然終了するSSHを `-L 127.0.0.1:18731:127.0.0.1:8731` 付きで開き、Invoke-RestMethodからhealth/models正常応答を確認。転送は自然終了済み、Windowsの18731 listenなし。再起動後も全操作SSH・一時転送が終了した後の13:40:33の新規接続で同じboot後container・起動時刻を維持し、active/running、NRestarts=0、health ok/idleを確認した。確認SSHも終了し、サービスを稼働させたまま残した。

## 11. 再開追補: 判定・運用・切戻し・Git

| 項目 | 今回の判定 |
|---|---|
| Quadletと専用停止drop-inの生成・実効値・ファイル一致 | PASS |
| 既存image/model再利用、rootless、GPU、RO mount、loopback公開 | PASS |
| 同名コンテナ拒否と無関係コンテナを削除しない後処理 | PASS（非GPUのcreateのみの小規模確認） |
| systemd起動・正常停止検知・GTT解放 | PASS（正常停止2回、再起動直前を含む） |
| SSH切断耐性・linger永続化 | PASS（再起動前後で確認） |
| Ubuntu再起動後のログイン前自動起動 | PASS（計画再起動1回、boot後の手動startなし） |
| memlock継承・boot後の実engine無制限 | PASS |
| health/models・Thinking ON日本語・Windows SSH転送 | PASS |
| 最終稼働 | PASS: active/running、Linger=yes、Restart=no、NRestarts=0 |
| 今回の機能検証FAIL | なし。前回StopTimeout=-1互換性FAILは履歴として保持 |
| 突然のOS shutdown、異常停止・GPU hang、失敗注入、強制kill | 未実施・保証対象外 |
| 長文/長context、画像、tool calls、耐久、MTP品質比較、Dense切替 | 未実施・今回対象外 |

**残る運用上の制約:** 子サービスの停止は無期限に待ち、SIGKILLを送らない。停止が固まったらforce kill/reboot/restartで進めず報告する。親ユーザーマネージャーの5秒制限は承認済み方針どおり維持したため、突然のOS shutdown時に親からの強制終了を完全に避ける保証はない。Restart=noなので異常終了時は自動復旧せず、状況確認とユーザー判断を必要とする。今回、通常停止・計画再起動に関する未解決の阻害要因はない。

将来のモデル切替・計画再起動は、**リクエストなし確認 → `systemctl --user stop halogen-active.service` → inactive/container消失/8731消失/GTTが基準付近へ戻ったことを確認 → 承認済みactive定義を選択・照合 → OS再起動**の順とする。Dense用定義や切替コマンドは今回作っていない。systemd管理中に手動run.shを実行しない。

恒久変更は上記ユーザー設定2ファイルと当該ユーザーのlingerのみ。付随してQuadlet生成unit・default.targetリンク・rootlessコンテナ・journalが生じる。ソフトウェア追加、モデル/imageの取得、既存モデル/cache/graphrootの削除、run.sh変更、親user manager/PAM/limits/カーネル/GPU/BIOS/UEFI/ネットワーク設定変更はない。既存run.shのSHA-256 `5cb53066f338a15cb9c621d0b330998e1ed8da9dcd830d67e07971a9df15d0a9` も不変。

**切戻し手順（未実施）:** idleから上記systemctl正常停止・GPU解放を確認し、今回作った `~/.config/containers/systemd/halogen-active.container` と `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf` の2ファイルだけを除去し、`systemctl --user daemon-reload`。空になった今回専用ディレクトリだけ必要に応じて除去する。生成されたdefault.targetリンクが消えたことを確認し、他用途がない場合だけ対象ユーザーのlingerをdisableする。モデル・image・graphroot・run.sh・既存memlock規則・親managerは維持する。旧第5/7節の親drop-in追加/削除案は今回の構成には適用しない。

今回のtracked変更は **Quadlet、停止drop-in、本追補レポートの3ファイルだけ**。対象差分・公開情報・`git diff --check`を確認し、指定pathだけをstageしてmainへcommit/pushする。自己commit SHAとpush・origin/main包含確認は最終チャットで報告する。指示書・AGENTS.md・run.shに変更はない。

追加参照: [Podman 5.7の非強制rmとlabel/name filter](https://docs.podman.io/en/v5.7.0/markdown/podman-rm.1.html)。異なるfilter keyをAND条件で使い、サービス所有コンテナだけを後処理対象とした。公式仕様だけで済ませず、上記実機確認を行った。

## 12. LAN待受への変更・実機反映（追加明示指示）

### 12.1 指示・変更範囲

- 実施日時: 2026-10-15、13:55～13:57 JSTに実機検証、その後Git反映。Windows開発PC上のCodexから `ssh evox2` で同じUbuntuホスト・rootlessユーザーを操作した。
- 今回の実行指示は、このチャットのユーザーによる `PublishPort=127.0.0.1:8731:8731` → `PublishPort=0.0.0.0:8731:8731` の追加明示依頼。アイドル確認、systemd正常停止、GPU解放確認、設定反映、サービス起動を承認し、OS再起動は不要、ルーターのポート転送・外部公開は行わないという範囲だった。既存指示書commit `88dfed241f2042c975f9c3b208536246c8409eb5` のloopback制限はこの追加指示で変更された。新しい指示書commitはない。
- `AGENTS.md` を先に読んだ。Windows側branch=`main`、開始HEAD=`75118e558ec3b91cb88669440642b89cd50028e0`、clean、fetch後もorigin/mainと一致。他タスク変更なし。実機の既存Quadlet/drop-in hashは第9.2節と一致し、同じサービスがactive/running、NRestarts=0であることを確認した。
- tracked変更は `deploy/halogen-flash/halogen-active.container` の **PublishPort 1行** と、本レポートの追補のみ。実機では既存 `~/.config/containers/systemd/halogen-active.container` だけを更新した。停止drop-in、親manager、run.sh、モデル/image、認証、Firewall、SSH、ルーター設定は変更していない。

### 12.2 正常停止と設定反映

**[EVO-X2 Ubuntu/SSH]** `/health` がstatus=ok、engine.responds=true、busy=false / in_flight=0 / queued=0であることを停止直前に確認した。13:55:52～53 JSTに `systemctl --user stop halogen-active.service` が1.193秒で正常完了した。

- GTT: **29,085,544,448 → 18,661,376 bytes**。前回の停止時基準と一致。
- systemd: inactive/dead、Result=success、ExecMainStatus=0、ExecStop/ExecStopPostともstatus=0、NRestarts=0。
- container消失・8731 listen消失、journalのstop requested / engine・API shutdown complete / GTT 0.0 GiB / Stoppedを確認。force killやforce rmは実行していない。

**[Windows開発PC→EVO-X2 Ubuntu]** 変更後のQuadletを既存配置先へコピーし、SHA-256一致を確認した。新hashは **`cb6c6357066d68a0a7a8a035c8b61de8950ffa8847665b4bae23689c8ec03446`**。停止drop-inのhashは第9.2節から不変。`systemctl --user daemon-reload`、`systemd-analyze --user --generators=true verify halogen-active.service` が成功し、実効ExecStartに `--publish 0.0.0.0:8731:8731` が入ったことを確認した。

13:56:11 JSTに `systemctl --user start halogen-active.service` を実行し、active/runningへ復帰。warmロードはmodel ready 2.5秒、engine listening after 4秒。停止経路は従来の非強制stop/rmのまま、TimeoutStopSec=infinity、SendSIGKILL=no、Restart=no。コンテナ内soft/hard memlockはunlimited、Linger=yes、既存image IDも不変。**OS再起動は0回**で、boot時刻が前回検証後のままであることも確認した。

### 12.3 LAN直接接続の検証・最終状態

**[Windows開発PC]** SSH設定の接続先をローカルで参照し、実IPをレポートへ保存せず `http://<EVO-X2のLANアドレス>:8731` へ直接HTTP接続した。SSHトンネルなし、HTTP proxyなし、Authorizationヘッダーなしで確認した。

| 検証 | 結果 |
|---|---|
| `/health`・`/v1/models` | PASS。正常HTTP応答、status=ok、engine.responds=true、model=`halogen-qwen3.8-flash-next`、thinking_control=true |
| Thinking ONの日本語短問 | PASS。「りんご17個を5人に配る」への回答は「一人3個、余り2個」、finish_reason=stop、非空reasoning_content（180文字） |
| 設定・実待受 | PASS。Podman PortBindingsはHostIp=0.0.0.0 / HostPort=8731。実際のssはIPv6側のwildcard socket `*:8731` として表示され、IPv4 LANからのHTTPも成功した |
| 最終状態 | PASS。13:57:13 JST、active/running、NRestarts=0、health ok、busy=false / in_flight=0 / queued=0。操作SSHを終了し稼働を維持 |
| OS再起動・ルーター変更・Firewall変更 | 未実施。今回必要なし |

推論1件の条件はenable_thinking=true、reasoning_effort=low、temperature=0、max_completion_tokens=4096、stream=false、seed/top_p/top_k未指定。既存context=262144、MTP、checkpointは変更なし。input=74、completion=68（reasoning=56）tokens、pp=173.140 tok/s、tg=66.471 tok/s、prompt=427.4 ms、generation=1023.0 ms、Windows client wall=1.489秒。tgはThinkingを含む生成全体、TTFTは未測定。疎通確認1問であり性能比較・品質評価ではない。

公開範囲は全インターフェースの8731待受へ拡大し、認証は従来どおり追加していない。自宅LAN利用というユーザー指定に基づく変更であり、アプリ側に接続元LANの制限を追加したものではない。観測時のglobal-scope addressはprivate IPv4が1件、IPv6は0件、公的アドレスは0件だった。`ufw status` はufw未導入のため確認できず、導入・設定変更はしていない。ルーターの既存設定やWANからの到達性は未検証で、外部公開・ポート転送の操作は行っていない。

切戻し（未実施）は、同じidle確認→systemd正常停止→GPU解放確認の後、PublishPortを127.0.0.1へ戻してコピー・daemon-reload・startし、loopback待受を確認する。モデルやコンテナ保存先を削除する必要はない。今回の2ファイルだけの差分・`git diff --check`を確認してcommit/pushする。自己commit SHAとorigin/main包含確認は最終チャットで報告する。
