# Halogen 対話式モデル選択・再起動切替 実施レポート

> **最新状態（2026-10-16 06:46 JST）: `PASS`。追加最大2回の再起動承認を受け、修正版selectorの既存UIからFlash→Dense→Flashの実機往復切替に成功した。両回とも正常停止・GPU解放後に設定対を切り替え、ログイン前自動起動・LAN API・Thinking ONを確認。現在はFlashのみactive/running、Dense停止。今回2回、以前の試験と通算4回の再起動。詳細は第13節。第1〜12節は過去の実施履歴。最初の中断原因が確定したという意味ではない。**

## 1. 初回実施時の結論・中断状態

**状態: `BLOCKED_DENSE_SYSTEMD_EXIT_143`。実装・Flash→Denseの自動起動検証は完了したが、往復の受入は未完了。** Dense→FlashのTTY Yes後、Denseのsystemd停止が`failed / Result=exit-code / ExecMainStatus=143`になったため、指示書A2・Phase Bの停止条件に従って保留した。`SuccessExitStatus`を追加して成功扱いにする変更はしていない。

**最終確認（2026-10-15 17:58:31 JST）:** 選択設定はDenseの対、`halogen-active.service`はfailed、MainPID=0。Flash/Denseのcontainerはともに存在せず、8731/8732は閉鎖、GTT=18,661,376 bytes、GPU busy=0%。**Flashの常駐復帰は未実施であり、現在APIを利用できない。** Linger=yesとdefault.targetの登録は維持されているため、次回OS起動の選択はDenseのまま。無断で再起動・別モデル起動を進めない。

OS再起動は許可上限2回のうち **1回**。2回目は発行していない。停止失敗を無視してFlashへ手動切替する操作も行っていない。再開に必要な設計判断を第8節に示す。

## 2. 指示・実行環境

- 指示書: `docs/instructions/2026-10/2026-10-15_halogen_interactive_model_selector_instruction.md`。
- 実行した指示書commit: `b1c3d7ec1fee2b252ded8b2ecfb9b5597e60fa2d`。
- 実施日: 2026-10-15。Windows開発PCのCodexで実装・Git操作、`ssh evox2`でEVO-X2 Ubuntuの配置・検証を実施。実ユーザー名、UID、IP、UUID、思考本文・生ログは公開しない。
- Windows開始branch=`main`、HEAD=`359445694e4602cf72af31e005c4e47ecc51083e`、clean。`AGENTS.md`を先に読み、fetch・指示書commitのorigin/main包含を確認し、指示書commitへfast-forwardした。他タスクの変更なし。
- Flash初回導入レポート、常駐化レポート第9〜12節、Dense初回導入レポート、既存Flash正本2件とDense `run.sh`を確認。モデルの配布metadata照合済み証拠は再利用し、巨大ファイルの再hash・再取得は行っていない。
- 実hostname・非root実行ユーザーを照合。Ubuntu 26.04.1 / kernel `7.0.0-38-generic`、systemd 259.5、rootless Podman 5.7.0。Linux用`/srv/llm`は既存ext4 LV、空き667,787,325,440 bytes。MemTotal=127,102,676 kB、固定VRAM=2 GiBを確認した。
- `sudo -n true`、KFD/renderアクセス、SSHのmemlock soft/hard unlimited、Linger=yes、既存image ID・モデルファイル存在を確認。開始時Flashはactive/running、NRestarts=0、health ok / busy=false / in_flight=0 / queued=0、設定2件のhashはGit正本と一致した。
- `flock`、curl、Python 3は既存。JSONの厳密な解析だけにPython標準ライブラリを使用し、Python環境・ライブラリ・jqを追加していない。shellcheckは未導入のため未実施。

参照資料: [Podman 5.7 Quadlet](https://docs.podman.io/en/v5.7.0/markdown/podman-systemd.unit.5.html)、[whiptail公式Ubuntu manpage](https://manpages.ubuntu.com/manpages/noble/man1/whiptail.1.html)、[systemd.service公式Ubuntu manpage](https://manpages.ubuntu.com/manpages/noble/man5/systemd.service.5.html)、[Dense公式README](https://github.com/peonist-ai/halogen-server/blob/main/README.md)。外部資料は仕様確認用とし、実効値は本機で確認した。

## 3. 実装・追加配置

tracked変更は次の新規4件のみ。既存Flash正本とDense `run.sh`、指示書は変更しない。

1. `deploy/halogen-dense/halogen-active.container`
2. `deploy/halogen-dense/halogen-active.service.d/90-safe-stop.conf`
3. `deploy/model-selector/llm-select.sh`
4. 本レポート

**[EVO-X2 Ubuntu/SSH]** Ubuntu公式aptのsimulateで対象を確認し、次を実行した。

```bash
sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
  apt-get -y --no-upgrade --no-install-recommends install whiptail
```

新規は`whiptail`と通常依存`libnewt0.52`、ともに`0.52.25-1ubuntu3`の2件だけ。upgrade=0、削除=0、取得65.8 kB、追加241 kB。libnewtのpackage-managed palette/alternativesとapt/dpkgログが生じた。needrestartはサービス再起動不要と報告した。新しいデーモン・timerは作っていない。

root所有の既存`/srv/llm/engines`は変更せず、その下の新規`model-selector`だけを`sudo -n install -d`で実行ユーザー所有0755として作成。次を配置した。

| 実機パス | 内容・mode |
|---|---|
| `/srv/llm/engines/model-selector/llm-select.sh` | セレクター、実行ユーザー所有0755 |
| 同ディレクトリの`templates/flash/halogen-active.container`と`templates/flash/halogen-active.service.d/90-safe-stop.conf` | 既存Flash正本のコピー、0644 |
| 同ディレクトリの`templates/dense/halogen-active.container`と`templates/dense/halogen-active.service.d/90-safe-stop.conf` | 新規Dense正本のコピー、0644 |
| `/usr/local/bin/llm-select` | 上記scriptへのroot所有symlink。同名不存在を確認して新規作成、解決先・実行権を確認 |
| `~/.config/containers/systemd/halogen-active.container` | 唯一のactive Quadlet。Flash→Denseの成功時に対で更新 |
| `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf` | 同じactive serviceの専用停止設定、対で更新 |

テンプレートはQuadletの常時探索先の外に置いた。別モデルの自動起動unitを追加していない。現実の選択はactiveの2ファイルで識別し、独自のstate/pendingファイルはない。排他には既存selectorディレクトリのinodeを`flock`し、lockファイルも作らない。

| ファイル | SHA-256（Git内容・実機一致） |
|---|---|
| Flash Quadlet（変更なし） | `cb6c6357066d68a0a7a8a035c8b61de8950ffa8847665b4bae23689c8ec03446` |
| Flash stop（変更なし） | `790f8cc28a2c035c32a9436745bd946f00dc2ea9c088d5c5851cbface958605e` |
| Dense Quadlet | `52a90d1a9ed70c95c84f42fd8edefa3cd293ef874ef7d048ed7d9166b67b9466` |
| Dense stop | `85a0498391669910604ae207b180edacb149af5deb1bdfbcefbc5f3a4ee46a23` |
| selector最終版 | `579027b9c3076e8350ed133e8a94655595f08099f22aba533214ba9b273a8e3b` |

### 3.1 Dense unit・停止設定

既存`ghcr.io/peonist-ai/halogen:0.1.4`をPull=neverで使用。ID=`7f87d073e63491e65fcdce6fb52c2faf2ded22229638f4ed2438096b11cb66c6`、digest=`sha256:dc0a39a0016d6cfc58a197978febaafdf8d28403f724ded6111d98b5fb7ac0ea`。container名は`halogen-dense`、サービス所有ラベルは`io.evox2.halogen.service=halogen-active`。

標準checkpoint=`/models/qwen3.8-27b-p1w4d-d2.hgn`、既存モデル全体とtokenizerをRO mount、HALOGEN_TOKENIZER=/tokenizer、HALOGEN_DOWNLOADなし。0.0.0.0:8732→8731のみ公開し、内部8730は非公開。GPUデバイス、keep-groups、memlock=-1:-1、IPC=host、Dense限定seccomp=unconfinedを維持する。contextやW4A4/DFlash2/KV/prompt cache/Thinkingのserver既定を上書きしない。

起動前にmount、モデル/tokenizer、image、GPU、rootless、memlock、ポート、既存Flash/Dense/bootstrap container不在を検査。既存同名containerのチェックは生成`--replace`より前に動く。`[Install] WantedBy=default.target`、Restart=no、LimitMEMLOCK=infinity。

実効停止設定は以下。Flashも同じ構造で名前だけFlashを使用する。生成unitのforce rmは両Execの空行によるリセットで実効値から除外した。

```ini
ExecStop=/usr/bin/podman stop --ignore --time=-1 halogen-dense
ExecStopPost=-/usr/bin/podman rm --ignore --filter label=io.evox2.halogen.service=halogen-active --filter name=^halogen-dense$$
TimeoutStopSec=infinity
Restart=no
KillMode=mixed
SendSIGKILL=no
```

`$$`はsystemdのリテラル`$`表記。stop後処理は所有ラベルと完全一致名のAND filterを使う非強制rm。`StopTimeout=-1`、`SuccessExitStatus=143`、親user managerへの変更は入れていない。

### 3.2 セレクター

通常の起動方法は **`ssh -t evox2 llm-select`**、またはSSHログイン後に任意ディレクトリで`llm-select`。矢印で移動、Spaceで1モデルを選択、TabでOK/Cancelへ移りEnter。続くReboot画面はNoが初期フォーカス。現在モデルと同じ選択なら再起動せず終了する。`llm-select --show`は完全read-onlyの状態表示。

今回のCodex Windows PTYはTERM=dumbを渡したため、最初のUI呼出は安全に拒否された。試験時のPowerShellプロセスだけ`$env:TERM='xterm-256color'`を設定して実端末UIを検証した。恒久的な環境変数・SSH設定変更はない。利用端末でもTERM=dumbの場合は端末種類を正しく設定する必要がある。

No/Cancel/Esc/確認前のSSH切断ではサービス操作、設定書込、daemon-reload、rebootを実行しない。確認を省略する切替オプションはない。Yes後に両モデルの全テンプレートとactive対のhash・所有者・modeを再検査し、rootless・memlock・image ID・モデル・Ubuntu boot先・service/container/APIの一致、idle、他container/他モデルport不在、GTTが既知モデルの範囲内でGPU busy=0を確認する。

正常停止後のGTT許容上限は過去基準18,661,376 bytes＋16 MiB、加えてGPU busy=0、container一覧空、両port閉鎖を要求する。今回実測はすべて過去基準と完全一致。基準外なら別モデルのロード・設定更新・rebootに進まない。停止待ちは既存の無期限・非強制契約を維持する。

停止後、各activeファイルと同じディレクトリに元ファイルの退避と新ファイルを置き、hashを確認してrenameする。停止済み＋排他を前提に2件を対で扱い、2件目失敗やdaemon-reload/検証/reboot要求失敗では旧対を復元する。runtimeが外部操作で再び動いていた場合は上書き復元せず退避を保持する。復元成功かつGTT解放済みの場合だけ旧モデル起動を1回試みる。

generatorで期待する起動引数を作り、systemctlの実効起動引数の全項目・値を照合する。Go map由来の独立オプション順の違いだけは許容する。stop/stop-post両方、専用drop-in以外がないこと、Restart、memlock、default.targetの依存、systemd-analyze verifyも検査する。成功後だけ`sudo -n reboot`を実行する。

最終版は`--rm`で消えるcontainerの終了値を、完全IDと停止開始時刻で限定した`podman events --stream=false`のdiedイベントから取得する。実機切替時の版ではread-onlyの`podman wait`で取得していたが、失敗時に背景waiterが排他FDを保持し得るため最終整理でイベント参照へ変更した。実際のDense停止イベント143の読み取りと隔離試験で最終版を確認し、追加の実機再起動は行っていない。

## 4. UI・安全性試験

| 試験 | 結果・証拠 |
|---|---|
| `bash -n` | PASS。最終版も確認 |
| Flash/Dense generator dry-run、専用drop-inを含めた実効stop、systemd verify | PASS。隔離した一時unitディレクトリで実施し、自動起動へ追加していない |
| 実TTYのラジオUI・2択・Space/Tab/OK | PASS。Flash選択時とDense起動後の現在選択を表示 |
| Cancel / Reboot No / Esc / 同一モデル選択 | PASS。Flash MainPID=21654、ActiveEnterTimestampMonotonic、設定hash2件、Linger=yes、boot時刻が不変。health ok / idle |
| 確認前のSSH切断 | PASS。UI表示中にOpenSSHの切断操作で終了、旧選択・PID不変。切断後に排他も解除 |
| 非TTY・TERM=dumb | PASS（拒否）。停止・書換え・rebootなし |
| 排他競合 | PASS。実UI起動中の別呼出を拒否、サービス非変更 |
| 誤テンプレート・busy・停止失敗・GTT未解放・systemd143 failure | PASS（隔離fixtureで拒否）。実機への障害注入なし |
| 2個目rename失敗・daemon-reload失敗・生成unit検証失敗・reboot要求失敗 | PASS（隔離fixture）。旧2件復元、条件成立時だけ旧モデル起動1回。実機reboot失敗注入なし |
| 切替途中HUP・外部からの再起動との競合 | PASS（隔離fixture）。HUPでは旧対復元、runtimeが稼働へ変化した場合は書戻しとrebootを拒否し退避を保持 |
| 通常成功経路 | 隔離fixture PASS、実機Flash→Dense PASS |
| Dense→Flash→再起動後Flash API | 未実施。第7節の停止条件で中断 |

一時fixtureはPython標準ライブラリのTemporaryDirectory内でproduction scriptの関数・トランザクション部分を使い、systemctl/Podman/reboot等を偽物へ置換して実施。12ケースを最終版で通過し、fixtureは削除済み。production scriptにテスト用バイパスや環境変数による変更先切替を追加していない。実機でのforce kill/rm、GPU hang、長時間負荷、停電試験は未実施。

## 5. Flash停止・最初の試行と1回目の再起動

17:50:21〜22 JSTの最初のTTY Yes試行でFlash停止自体は成功した。systemd inactive/dead / Result=success / ExecMainStatus=0、container exit=0、GTT **29,085,544,448 → 18,661,376 bytes**。engineとAPIのshutdown完了、GTT返却ログも確認した。

ただし直後の複合`container/port/GTT/GPU busy`検査が不成立となり、設定更新前に終了した。当該瞬間のbusy/port詳細は旧版が出力しておらず、**失敗した内訳・原因は未確定**。17:50:37の追加確認ではcontainerなし・両port閉鎖・GTT基準一致・busy=0で、設定対は旧Flashのままだった。OS再起動は発行されていない。診断表示を追加し、上記全条件と旧unitを再確認してFlashをsystemdから1回復帰させた。判定を緩めたり待機sleepで回避したりしていない。

17:52:09〜10の再試行でもTTYの選択・Yesを通過。Flash停止はResult=success、status=0、container exit=0。GTT **29,054,521,344 → 18,661,376 bytes**、busy=0、container/port消失を確認した。Dense対へrename、daemon-reload、実効unit/停止処理/default.targetの照合に成功。**17:52台に1回目の`sudo -n reboot`を発行**した。

各試行前に、観測時のAPI接続・別SSH作業sessionがないこと、health idle、BootCurrent=Ubuntu / BootOrder先頭同Ubuntu / BootNextなし、GRUB_DEFAULT=0・先頭Ubuntu・grubenv空を確認した。UEFI/GRUB等に書き込んでいない。新規HTTPがidle確認直後に来る競合までは完全に排除できず、利用者が作業クライアントを終了することが前提である。

## 6. Denseのログイン前自動起動・API

reboot後に手動`start`やDense `run.sh`を実行していない。最初はSSHを開かずWindowsからLAN HTTPを確認し、17:53:05にhealth/models正常応答を得た。その後の最初のSSHは17:53:23。

| 事象 | bootからの秒 |
|---|---:|
| `halogen-active.service`開始 | 6.019 |
| サービスactive | 6.460 |
| 35.9 GB checkpoint登録完了（登録23.5秒） | 31.587 |
| engine listen確認 | 32.606 |
| API listenログ | 35.208 |
| 最初のSSH session | 62.814 |

API起動ログはSSHより約27.6秒早く、LAN HTTPもSSHより先に成功。containerはDenseだけ、8732 listen、Flash containerなし/8731閉鎖。Dense選択のactive hash2件と再起動前の値が一致した。通常の`[Install] WantedBy=default.target`による生成リンクを維持し、enableコマンドは使っていない。

healthはmodel=`halogen-qwen3.8-27b`、api/engine=0.1.4一致、context=262144、slots=1、drafter_default=dflash2、prompt cache AUTO / cap_mb=58,999 / align=2048。既存の量子化・W4A4=64・Thinking既定は変更していない。GTTは21,176,967,168 bytes、短問後21,213,184,000 bytes。

user manager実プロセスとcontainerのmemlock soft/hardはunlimited。Linger=yes、Restart=no、NRestarts=0。親managerのTimeoutStopUSec=5s / KillMode=mixed / SendSIGKILL=yes、vendor drop-in一覧は従来どおりで、変更なし。SSHを一度終了した後の接続でも同一Dense container・稼働を確認した。

### Thinking ON日本語短問

**[Windows開発PC]** SSH転送・HTTP proxyなしでLAN8732へPOST。プロンプトは前回と同じ「りんご17個を5人に同じ数ずつ配ります。一人何個で、余りはいくつですか。日本語で短く答えてください。」。

条件: enable_thinking=true、reasoning_effort=low、temperature=0、max_completion_tokens=4096、stream=false。top_p/top_k/seedはリクエスト未指定。既存標準HGN、native context、DFlash2を維持した。

**PASS:** HTTP正常応答、finish_reason=stop、最終回答「一人3個、余り2個。」、非空reasoning_content=138文字。input=74 / completion=57 tokens、reasoning token内訳はAPI未提供。prompt=446.2 ms / generation=1732.3 ms、**pp=165.845 tok/s / tg=32.904 tok/s / Windows wall=2.324秒**。cache_n=0、draft_n=14、draft_n_accepted=44。tgはThinkingを含む全生成、TTFTは非streamのため未測定。短い疎通確認であり、創作品質の再評価や長context性能比較ではない。

公開は既存方針の家庭内LAN HTTP・認証なし、0.0.0.0:8732。ssはIPv6側wildcard socketとして表示しIPv4 LAN到達も成功した。ルーター/NAT/Firewall/IPv6公開設定は変更しておらず、WAN到達性は未検証。

## 7. Dense停止143と切替中断

17:54:33 JST、Dense idle・競合なしを再確認し、実TTYでFlashを選択→Reboot Yesを入力。セレクターが`systemctl --user stop halogen-active.service`を実行した。

| 観測 | 結果 |
|---|---|
| ExecStop（podman stop --ignore --time=-1） | status=0 |
| ExecStopPost（専用label/nameの非強制rm） | status=0 |
| container終了コード | **143**。実行時のpodman waitと停止後のdiedイベントが一致 |
| systemd主プロセス | **ExecMainCode=1（exited）、ExecMainStatus=143** |
| unit結果 | **ActiveState=failed / SubState=failed / Result=exit-code** |
| GTT | **21,213,184,000 → 18,661,376 bytes** |
| 残存container / port / GPU busy | containerなし、8731/8732閉鎖、busy=0 |
| その後の設定変更・2回目reboot | **未実施**。Dense設定対を維持 |

停止ログはsystemdのStopping/Main process exited 143/Failed/Stopped、Podman died/removeを示した。Flashにあるengine/APIの明示的shutdown-completeログは今回Denseでは得られていない。前回確認済みのentrypoint（TERM trapからengineへTERM、`set -e`下の`wait -n`）と143は整合するが、**全内部cleanupの完了やexit=0を証明したことにはしない**。GPUメモリ返却・プロセス消滅と、systemdの正常判定を分けて報告する。

selectorはResult=successを要求するためここで拒否し、force kill、force rm、親manager変更、SuccessExitStatusの追加、reset-failed、手動Flash切替、2回目rebootは実行していない。現在bootのkernel journalをOOMとamdgpu fault/reset/timeout/hang/errorに限定して確認し該当0だったが、全障害の不存在を保証するものではない。

## 8. 未承認の再開案・残課題

指示書A2の「必要なら限定的な`SuccessExitStatus`設計を理由と共に提案して一度止まる」に該当する。**以下は提案であり未適用。**

1. Dense専用stop drop-inだけに`SuccessExitStatus=143`を追加する。Flashと親user managerには追加しない。
2. selectorのDense stop hashとDenseに限る実効SuccessExitStatus検査を更新する。切替直前idle、実際のsystemctl stop、終了イベント、container/port消失、GTT基準復帰の各gateは維持する。単に143だけでrebootを許可しない。
3. 現在のfailed状態、GTT解放、設定対を確認したうえで承認済みDense設定を反映し、Denseを1回通常起動。TTYでFlash選択→Yes→Dense停止のsystemd結果を再検証する。
4. 条件が成立した場合だけ、今回残っている1回のOS再起動でFlashを選択・自動復帰させ、Thinking ON/LAN8731・Dense停止・元Flash hash一致まで確認する。

`SuccessExitStatus=143`は当該Dense unitでの**予期しない143終了もsuccess分類にする**点が判断事項。Restart=noは維持されるが、engine/APIの全終了処理を追加検証することとは別である。この分類変更を承認しない場合は、停止契約の別設計、またはGPU解放を確認した現在状態からFlash正本の対へ手動復旧する限定手順について、ユーザー判断を受けてから進める。

ほかの残課題は、最初のFlash停止後の複合gate不成立の内訳未確定、idle検査とHTTP到着の競合、突然のshutdown/停電に対する親managerの5秒期限である。異常時の無条件restartや常駐監視は追加していない。長文創作・長context負荷・量子化比較は今回対象外として未実施。

## 9. 復旧・撤去手順（未実行）

現時点で通常の`llm-select`を再実行しても、稼働中Denseの前提を満たさず停止する。ここからの復旧は上記判断後に行う。

- Flashへ戻す際は、対象モデルの正常停止結果を確認し、containerなし・両port閉鎖・GTT基準復帰を確認した後に、`templates/flash`のQuadletとstopを**対で**activeの2パスへ反映する。片方だけ差し替えない。hash一致→daemon-reload→実効stop/start/default.target検証の順を守る。
- 起動/再起動を行う範囲は再開承認に従う。残りの自動起動受入を行うならTTY Yesを通し、今回通算3回目のrebootはしない。Flash起動後のAPIを確認するまで復旧成功とは記載しない。
- Flash正本の対で通常サービスが稼働した後なら、selectorを使っていないことと専用symlinkの解決先を確認して`/usr/local/bin/llm-select`だけを除去し、`/srv/llm/engines/model-selector`の今回のscriptと4テンプレートだけを撤去できる。activeの2ファイル、Linger、既存model/image/run.sh、memlockは維持する。全体prune/resetを使わない。
- 取り消しは撤去や復旧を意味せず、設定を一切適用しない。途中失敗の退避ファイルが残っていれば、現状態を確認してから復元に使う。今回最終確認でactive両ディレクトリに退避/next残骸はない。
- whiptail/libnewtが他用途で不要な場合の削除はapt simulateで影響を確認して別途行う。今回は削除・autoremoveしていない。

既存Flash image ID/digest、Flash/Dense `run.sh` hashは開始時と一致した。モデル/量子化/コンテキスト/キャッシュ設定、PAM/sudoers/SSH/Firewall/UEFI/BIOS/kernel、Windows SSD・別PC・v3は変更していない。Dense選択のactive対とselector関連ファイル、aptの上記2パッケージ以外の恒久設定変更はない。

## 10. Git反映

指定の4つのtracked pathだけを明示的にstageし、selectorの実行属性、LF、対象差分、`git diff --check`、秘密情報混入を確認する。無条件`git add -A`、force push、history rewriteは行わない。自己commit SHAとpush・origin/main包含・最終cleanの実確認は最終チャットで報告する。

本レポートは部分完了の証跡である。Flash復帰や往復受入完了を成功扱いにしない。

## 11. 承認後の再開: Dense停止判定修正・Flash自動復帰

### 11.1 承認・開始時の確認

- 再開日: 2026-10-15。実機反映・受入は18:09〜18:16 JST、以後レポート・最終確認・Git反映。実行主体は同じWindows開発PCのCodex、実機操作はSSH alias `evox2`経由。
- 指示の基礎は第2節の指示書commit。追加の承認はこのチャットのユーザーによる「提案された修正と残り1回の再起動を承認します」という明示指示。Dense専用`SuccessExitStatus=143`、selectorのhash/実効値検査更新、Dense通常起動、既存UIのFlash選択・Yes、全停止条件成立後の残り1回のrebootを承認した。Flash正本と親user managerの変更は引き続き禁止。
- `AGENTS.md`を先に読み、元の指示書の停止・再起動条件と前回レポート・実装を確認した。開始branch=`main`、HEAD=`48e0deca1388d205dd26b0bcf121a04eafe38a77`、clean。fetch後もorigin/mainと一致し、既存差分・競合はなかった。
- 18:09:44 JSTに同一ホスト・非rootユーザー・Linux用mount・kernel・sudoを最小限確認。Dense選択、unit failed / Result=exit-code / ExecMainStatus=143 / MainPID=0、全container不在、8731/8732閉鎖、**GTT=18,661,376 bytes / busy=0%**で前回状態と一致した。
- 配置済みselector、両モデルテンプレート、active対のSHA-256が前回commitと一致。Linger=yes、memlock unlimited、親managerの5秒期限・KillMode=mixed・SendSIGKILL=yes・vendor drop-inは不変だった。モデル再hash、再ダウンロード、パッケージ再導入はしていない。

### 11.2 変更差分・実機反映

変更したtracked fileは **Dense stop drop-in、selector、本レポートの3件だけ**。Dense Quadlet、Flashの全trackedファイル、両モデルの既存run.shは変更していない。

Dense専用`90-safe-stop.conf`に次の2行だけを追加した。

```ini
# Dense 0.1.4 returns 143 on TERM; selector still verifies stop and GPU release.
SuccessExitStatus=143
```

selectorはDense stopの固定hashを更新し、実効`SuccessExitStatus`がDenseでは厳密に`143`、Flashでは空であることを検査する。さらに停止後は既存のinactive / Result=success判定に加え、以下を要求する。

- ExecStopとExecStopPostが実際に実行され、各`code=exited / status=0`であること。ExecStopPostはunit側がignore_errors=yesのため、Resultだけで後処理成功を推定しない。
- containerのdiedイベントがFlashは0、Denseは0または143であり、systemdのExecMainCode=exited / ExecMainStatusとも一致すること。
- 従来どおりcontainer不在・両port閉鎖・GTT基準付近への返却・GPU busy=0。143という数値だけで設定更新やrebootを許可しない。

| 更新ファイル | 新SHA-256 |
|---|---|
| Dense stop | `6586664d17de8b7a888002fcd382012974219c1eb2a1d4517436e22fbfaf35f2` |
| selector | `570823a8d141e2d7a261208d3c8185054354243c6b8d7961c08f80a118fb1f7f` |

**[Windows→EVO-X2 Ubuntu]** 新版をselector配置先の一時ファイルへ転送、`bash -n`とhashを確認した。既存ディレクトリにflockを取り、旧active対・failed状態・GTT解放を再確認してからDenseテンプレートstopとactive stop、selectorを更新した。旧stop/scriptを一時退避し、activeと同じディレクトリの一時ファイルからrenameした。Dense Quadlet自体は同じhashのまま。`systemctl --user daemon-reload`とselectorの実効unit検査、`systemd-analyze --user --generators=true verify`が成功した後、今回だけの退避を除去した。

実効SuccessExitStatus=143、Restart=no、LimitMEMLOCK=infinity、非強制ExecStop/ExecStopPost、default.target登録を確認。失敗履歴を`reset-failed`で消す操作はしていない。

### 11.3 変更箇所の検証とDense通常起動

`bash -n`はPASS。実機設定のread-only照合でDenseの143を受理し、Flashとして143を受理しないこと、Denseで143が未設定なら拒否することを確認した。前回と同じ隔離fixture方式で変更した停止条件を6ケース確認し、全件PASS。

| 隔離ケース | 期待した結果 |
|---|---|
| Dense143＋Result=success＋両停止コマンド0＋GTT解放 | Flash対への切替とreboot呼出を許可 |
| 143でもsystemdのResultが失敗 | 設定変更・rebootを拒否 |
| Dense143でもGTT未解放 | 設定変更・rebootを拒否 |
| ExecStop失敗 | 設定変更・rebootを拒否 |
| ignore_errors対象のExecStopPost失敗 | 設定変更・rebootを拒否 |
| systemdとcontainerの終了値不一致 | 設定変更・rebootを拒否 |

上記は一時ディレクトリ内の偽runtimeによる検証であり、実機GPUやサービスへの障害注入ではない。fixtureは自動削除済み。UIのNo/Cancel処理は変更しておらず、前回の実TTY無変更検証を再利用した。

**18:13:02 JST**、もう一度container/port不在とGTT解放・Dense unit整合を確認し、承認どおり`systemctl --user start halogen-active.service`でDenseを通常起動した。手動run.shは使っていない。active/running、Result=success、NRestarts=0、container内memlock soft/hard unlimited。

18:13:07にはWindowsからLAN8732のhealth/modelsが正常応答。api=engine=0.1.4、model=`halogen-qwen3.8-27b`、context=262144、slots=1、DFlash2、busy=false / in_flight=0 / queued=0。モデル/image、RO mount、port、containerのconmonとservice MainPID一致を含む実機preflightもPASS。Denseの創作・速度ベンチは繰り返していない。

### 11.4 UIからDense停止・Flash選択・最後の再起動

別の作業SSH session・APIの確立済み接続がないことを確認し、`ssh -t evox2 llm-select`を起動。画面の現在選択DenseからFlashへSpace/Tab/OKで変更し、Reboot画面の初期Noから**Yesへ明示的に移動してEnter**した。確認迂回オプション・手動ファイル切替は使っていない。

セレクターがboot先・unit・idleを再検査し、**18:14:02 JST**にsystemd経由でDenseを停止した。

| 必須条件 | 実測・判定 |
|---|---|
| `systemctl --user stop` | 終了コード0 |
| unit結果 | **inactive/dead / Result=success** |
| ExecStop | podman stop --ignore --time=-1 halogen-dense、code=exited / status=0 |
| ExecStopPost | 専用label＋Dense完全一致名による非強制rm、code=exited / status=0 |
| 主プロセス・container | ExecMainCode=1（exited）、ExecMainStatus=143、diedイベント=143。一致 |
| GTT | **21,176,967,168 → 18,661,376 bytes** |
| その他の解放 | container一覧空、8731/8732閉鎖、GPU busy=0% |
| journalの停止経過 | Stopping 18:14:02.277894 → Stopped 18:14:02.523391、約0.245秒。今回の停止にMain process failed/Failed with resultログなし |

**すべての条件が成立してから**Flash正本のQuadletとstopを対で設置し、daemon-reload、生成unitとFlash stop両方、SuccessExitStatus空、Restart=no、default.targetを照合。もう一度空runtimeとGTTを確認した後、`sudo -n reboot`を1回実行した。今回の再起動は **1回、前回分と通算2回**。3回目や予備のrebootは行っていない。

143は承認されたDenseのTERM時終了分類として扱った。engine/APIの全内部cleanupを証明したという主張ではなく、systemd成功・停止コマンド成功・実リソース返却の全条件を実測した結果である。強制kill/force rmや親managerへの変更はない。

### 11.5 Flashのログイン前自動起動・LAN API

reboot後に手動startは実行していない。SSHを開く前にWindowsからLAN8731へ接続し、**18:15:33 JST**にhealth/models正常応答を確認した。その後の最初のSSHは18:16:27。

| 事象 | bootからの秒 |
|---|---:|
| Flash service開始 | 6.087 |
| active | 6.536 |
| engine model ready | 51.039 |
| API listen / startup complete | 53.819 |
| 最初のSSH session | 135.229 |

**APIはSSHより約81.410秒早く起動**し、LANからのHTTPもログイン前に成功した。coldロードでservice activeからAPI readyまで時間を要する点を区別し、初期のHTTP未readyを手動startで補っていない。

active対はFlash正本の既存hashに戻った。Quadlet=`cb6c6357066d68a0a7a8a035c8b61de8950ffa8847665b4bae23689c8ec03446`、stop=`790f8cc28a2c035c32a9436745bd946f00dc2ea9c088d5c5851cbface958605e`。現在のSuccessExitStatusは空で、Dense用143はFlashに残っていない。

Flashのみactive/running、Result=success、NRestarts=0、Restart=no、Linger=yes。containerはFlashだけ、8731 listen、Dense containerなし/8732閉鎖。user manager実プロセスとcontainerのmemlockはunlimited。親managerの5秒期限・KillMode・SendSIGKILL・vendor drop-inは開始時と一致し、変更していない。

healthはmodel=`halogen-qwen3.8-flash-next`、api=engine=0.18.4、engine.responds=true、Thinking control=true。context=262144、slots=4、KV pool=524288、prompt cache mode=2、MTP depth-2、既存checkpoint/量子化を維持。boot後のselectorによるFlash unit/runtime照合もPASS。

**[Windows開発PC] Thinking ON日本語API:** LAN8731へSSH転送・proxyなしで前回と同じ「りんご17個を5人へ配る」短問を送信した。enable_thinking=true、reasoning_effort=low、temperature=0、max_completion_tokens=4096、stream=false、top_p/top_k/seedはリクエスト未指定。

HTTP正常応答、finish_reason=stop、回答「一人3個、余り2個です。」、非空reasoning_content=180文字で **PASS**。input=74、completion=68（reasoning=56）tokens、prompt=435.1 ms / generation=1033.9 ms、**pp=170.076 tok/s / tg=65.770 tok/s / Windows wall=1.583秒**。MTP draft=55 / accepted=43、cache_n=0。tgはThinkingを含む生成全体、TTFTは非streamのため未測定。server既定のThinking effortを変更したものではなく、長文品質・持続性能の再評価でもない。

### 11.6 完了判定・残る制約・Git

**承認された再開分はPASS。** Dense専用143設定、停止結果の個別照合、Dense通常起動、TTYによるFlash選択、全停止条件成立後の最後のreboot、Flashのログイン前自動起動、LAN8731/Thinking ON、Dense停止まで完了した。前回のFlash→Dense自動起動実証と合わせ、往復受入を完了した。

**最終実機確認は18:19:23 JST。** 操作SSH終了後の新規接続でも、Flashの同じcontainer・MainPID・起動時刻を維持し、active/running / Result=success / NRestarts=0 / health ok / idleだった。実`flash_serve`プロセスのmemlockもunlimited、container OOMKilled=false。Dense containerなし、8732閉鎖。現在bootのkernel journalで限定したOOM/amdgpuエラー検索は該当0。Flash/Dense両run.shとFlashテンプレートhashは不変、転送・切替用の一時ファイル残骸もなかった。

現在の利用方法は`ssh -t evox2 llm-select`。取消時は変更を適用せず、切替失敗時は無条件にrebootしない。第9節の撤去手順はFlash復帰後の現在にも適用できる。今回追加の一時転送・退避ファイルは除去済みで、残る追加状態は更新したselector/Dense stopテンプレートと通常journalのみ。新規パッケージ・モデル・image・常駐サービスは追加していない。

残る制約は、Denseの予期しない143終了も当該unitではsuccess分類になること、明示的なengine/API全cleanupログが得られないこと、idle検査と新規HTTP到着の競合、突発shutdown時の親managerの5秒期限。第5節の初回Flash複合gate不成立の内訳も未確定の履歴として残す。これらを解消したとは主張せず、今回の通常切替・資源返却の成功と区別する。

対象3ファイルだけをstageし、差分・LF・hash・実行属性・秘密情報・`git diff --check`を確認してcommit/pushする。Flash正本、Dense Quadlet/run.sh、指示書・AGENTS.mdに変更はない。今回の自己commit SHA、push結果、origin/main包含・最終cleanは最終チャットで報告する。

## 12. 2026-10-16: 切替中断の調査・停止観測の修正

### 12.1 今回の目的と確認できた事実

ユーザーから、切替後もモデルが変わらず、再度実行すると「前提/idle/boot先/実効unitが不一致」となる報告を受けた。解決対象は**最初のモデル切替が完了しなかったこと**であり、再実行のエラー説明やFlash復旧だけでは完了としない。

`AGENTS.md`と同じ指示書commit `b1c3d7ec1fee2b252ded8b2ecfb9b5597e60fa2d`、既存レポート・selectorを再確認。Windows開始branchはmain、HEADは`ef709e7c7d8286ab17d4a6aaf9d0ebe795f958dc`、cleanで、fetch後のorigin/mainも同じ。WindowsからSSH alias `evox2`で同一Ubuntuホスト・非rootユーザーを確認した。既知のモデル・OS等の全面的な再調査は行っていない。

10月16日06:25 JST以降の読み取り専用調査では以下を確認した。

| 項目 | 証拠・結果 |
|---|---|
| 起動中OS | 最終bootは10月15日18:14:12 JST。今回の切替操作後のboot記録なし |
| 選択対 | Flash正本のQuadlet/stop hashと一致。両ファイルmtimeも10月15日18:14:02 JSTのまま |
| サービス | inactive/dead、Result=success、MainPID=0、ExecMainCode=1、ExecMainStatus=0 |
| 実リソース | 全container不在、8731/8732閉鎖、GTT=18,661,376 bytes、GPU busy=0% |
| selector | 配置hashは前回commitの`570823a8d141e2d7a261208d3c8185054354243c6b8d7961c08f80a118fb1f7f`と一致 |
| 読み取り専用preflight | 環境・boot先・unit照合を通過し、running_idleのActiveState=active条件で拒否 |

user journalの時刻をJSTへ換算した停止経過:

- 06:13:44.480574: systemdがFlash停止を開始。
- 06:13:44.618905: API application shutdown complete。
- 06:13:44.633888: engine shutting down。
- 06:13:45.508325: engine終了後のGTTを0.0 GiBとするHalogenログ。
- 06:13:45.514821943: 対象containerのdiedイベント、終了コード0。
- 06:13:45.588677334: 同containerのremoveイベント。
- 06:13:45.631880: systemdがStoppedを記録。ExecStop/ExecStopPostともcode=exited、status=0。
- 06:13:45.773以降: SSH session終了。OS再起動の証拠ではない。

このため、**Flashの正常停止後、Denseへの切替・reboot完了へ進まなかった**ことは確認できる。一方、当時の端末出力は残っていないとユーザーから回答があり、旧selectorは判定結果をjournalへ保存していなかった。終了イベント未観測、GPU状態の一時的不一致、割込み等のどれで止まったかは確定できない。後から同じcontainer ID・停止時刻を指定した終了イベント照合と全停止条件はPASSしたが、当時の各読取値が同じだったとは推定しない。

### 12.2 修正内容と適用範囲

旧コードは、systemctl stopの直後に`podman events --stream=false`とGPU状態を一度だけ読み、全条件成立前に失敗すると設定変更も旧モデル起動も行わず終了する。この状態では次回のselectorも稼働前提で拒否される。

Podman 5.7.0の[公式journal読取実装](https://github.com/containers/podman/blob/v5.7.0/libpod/events/journal_linux.go)でも、Stream=falseの読取りはjournalの末尾に達すると追加イベントを待たずに終了する。これは観測遅延を考慮すべき根拠であり、今回実際にイベントが遅れたという証明ではない。

変更tracked fileは**selectorと本レポートの2件のみ**。Flash/DenseのQuadlet、停止drop-in、143の許容範囲、モデル・image・量子化・Thinking・context、親user managerは変更しない。

1. 対象container IDと停止開始時刻に限定した終了イベント取得を、最大10秒の確認期限内で再読取りする。空の結果を終了コード0とみなさず、重複/非数値イベントや読取エラーも拒否する。再読取りでstopを再実行しない。
2. GTTとGPU busyの既存条件が成立するまで最大10秒確認する。0.2秒間隔で条件そのものを読み直し、成立すれば即座に進む。固定時間待っただけで成功にはしない。
3. Result=success、inactive、実行済みExecStop/ExecStopPostの終了0、containerとsystemdの終了コード一致、Flashは0/Denseは0または143、container/port不在、GTT基準＋16 MiB以下、busy=0を維持する。待機後に資源とsystemd結果を再確認する。未解放や終了失敗のまま設定更新・起動・rebootする経路は加えていない。
4. **Yes後だけ**、既存journalへtag `llm-select`で処理段階と結果を記録する。停止結果、イベント取得、GPU解放、設定対設置、unit検証、rebootのどこで中断したかを残す。新しい選択state、ログ専用ファイル、常駐監視を作らない。No/Cancelではこのログも書かない。
5. 停止済みサービスを前提検査で拒否した場合、その実状態を表示する。停止済み状態から無条件に別モデルへ進める仕様には変更しない。

新selector SHA-256: `5e90a54121ac4c543a964948314a1dc2067281d07271e4c28fd1414cd4b8a0f3`。

### 12.3 修正箇所の検証

**Windows開発PC:** Git for Windows付属Bashによる`bash -n`はPASS。`.git`配下の一時fixtureに限定し、Podman/systemd/reboot/loggerを偽コマンドに置き換えた24ケースは全件PASS。実機への障害注入や再起動ではない。fixtureは試験後削除し、検証コードはtracked pathへ追加していない。

| 試験群 | 判定 |
|---|---|
| 即時Flash0、Dense143、終了イベント遅延、GPU観測遅延 | 新版が停止条件成立後に成功 |
| 同じイベント遅延・GPU遅延を旧版で再生 | 旧版は切替前に失敗。対象経路の再現に成功。実際の障害原因の確定とは区別 |
| 終了イベント欠落、GPU未解放 | 確認期限後も失敗。安全条件を無視しない |
| systemd失敗、ExecStop失敗、ExecStopPost失敗、Flash143、終了値不一致、重複イベント、想定外終了値 | すべて拒否 |
| 想定外container・listener | すべて拒否 |
| Yes前/Yes後の診断記録 | Yes前は記録なし、Yes後は段階を記録 |
| 実際の停止後コードから設定対更新・reboot呼出までのfixture | イベント/GPU遅延とDense143では正しい対へ更新後に偽reboot。イベント欠落/GPU未解放では設定不変、daemon-reload・start・rebootなし |

**Windows→Ubuntu:** 新版関数だけをメモリ上で読み込み、保存済みの実container終了イベント、現在のsystemd停止結果、container/port不在、GTTで照合した結果もPASS。この段階では配置済みscript・実サービスを変更していない。既存logger/timeoutも確認し、追加パッケージは導入しなかった。

### 12.4 配置と実機の現在状態

**Windows→Ubuntu、06:35 JST:** 候補をselector専用ディレクトリの一時ファイルへ転送。既存ディレクトリinodeのflock下で旧script hash、candidate hash、Bash構文、Flash設定対、環境・boot先・実効unitを検査した。停止済み状態は保存済み終了イベントと全停止条件で別途確認し、GTT基準復帰を確認してからscriptのみ0755でatomic renameした。旧scriptの一時退避・転送用ファイルは除去済み。

その後、`systemctl --user start halogen-active.service`を1回実行。**06:35:55 JSTにactive/running、Result=success、NRestarts=0**を確認した。Quadlet/stopの差替え、daemon-reload、stop、OS rebootはこの追補作業では実行していない。

- WindowsからLAN8731の`/health`と`/v1/models`に直接GETし、Flash応答を確認。
- health: status=ok、model=halogen-qwen3.8-flash-next、api/engine=0.18.4、context=262144、slots=4、drafter=mtp、engine.responds=true、busy=false / in_flight=0 / queued=0。
- 新版の**実機preflight全体もPASS**。GTT=29,054,521,344 bytes。Dense container不在・8732閉鎖。
- 配置script hashは新版と一致。active Quadlet/stopのhashは従来Flash正本のまま。

ここで確認したのは**Flashの復旧と切替前提の成立**である。新規Thinking生成、Denseへの実切替、切替後boot/API、往復成功は未実施であり、切替不具合を解決済みとは記載しない。

### 12.5 残る検証・再起動承認・Git

現在の状態は`WAITING_FOR_USER_REBOOT`。元指示書第5節Bの「合計最大2回」「3回目の再起動へ独断で進まない」に対し、前回までの実機試験で2回を使用済み。この追補では追加rebootを発行していない。

必要な次の試験は、改修済みselectorの対話UIで**Flash→Dense→Flash（追加最大2回）**を通し、各回の正常停止・終了イベント・GTT解放・設定対照合、reboot後のログイン前自動起動、各LAN APIとThinking ON、他モデル停止を確認すること。今回加えたjournal記録も照合する。失敗時は記録された段階を原因特定に使用し、条件を無視したrebootは行わない。

切戻しが必要なら、モデル切替が実行中でないことと現行hashを確認し、selectorだけを前回commitの内容へ戻せる。active Quadlet/stopやモデルに触れる必要はない。旧版へ戻すと今回の観測遅延対処・journal記録も失われる。いずれの版でも稼働中モデル・GPU異常を無視して切り替えない。

selectorと本レポートのみを明示stageし、差分、LF、実行属性、秘密情報、`git diff --check`を確認してcommit/pushする。自己commit SHA・origin/main包含確認は最終チャットで報告する。今回の隔離試験PASSを、実機切替成功へ読み替えない。

## 13. 2026-10-16: 追加承認後の実機往復切替

### 13.1 承認と開始状態

ユーザーは「安全条件を確認しながらFlash→Dense→Flashを追加最大2回の再起動で検証してよいか」という確認に「はいよいです」と明示承認した。この承認で第12節の再起動待ちは解消した。対象・品質・正常停止条件は元指示書と既存のDense143承認を維持する。

- 作業時間: 2026-10-16 06:40〜06:46 JSTに実機検証、以後レポート・Git反映。
- Windows開始branch=main、HEAD=`5cde8d194fb20be6a3cc78946017a254779e6da9`、clean。`AGENTS.md`を先に読み、fetch後のorigin/main一致、指示書と第12節、実装を確認した。
- WindowsからSSH alias `evox2`で同一Ubuntuホスト・非rootユーザーを確認。実機selectorのhashは`5e90a54121ac4c543a964948314a1dc2067281d07271e4c28fd1414cd4b8a0f3`、active対はFlash正本と一致。
- Flash active/running、Result=success、NRestarts=0、health ok/idle、APIの確立済み接続なし。全preflight（boot先、memlock、Linger、image/model、実効unit等）を通過した。操作用SSH以外の作業sessionはなかった。
- この再開ではコード・恒久設定を追加変更せず、前回配置した修正版をそのまま使用した。変更tracked fileは**本レポートのみ**。

### 13.2 既存UIによる切替と停止条件

いずれもWindows上で`ssh -tt evox2 llm-select`を開き、ラジオ選択をSpaceで確定してOKへ進み、Reboot画面の初期NoからYesへ移動してEnterした。確認を迂回するオプションや手動の設定差替えは使っていない。

| 条件 | 1回目: Flash→Dense | 2回目: Dense→Flash |
|---|---|---|
| UI Yes/切替開始 | 06:40:50 JST | 06:44:02 JST |
| systemd停止開始 | 06:40:51.937826 | 06:44:03.378495 |
| systemd停止完了 | 06:40:53.093429 | 06:44:03.634118 |
| 停止所要時間 | 約1.156秒 | 約0.256秒 |
| systemctl stop | 成功 | 成功 |
| 停止後systemd | inactive / Result=success / ExecMainCode=1 / ExecMainStatus=0 | inactive / Result=success / ExecMainCode=1 / ExecMainStatus=143 |
| 対象containerのdiedイベント | 0 | 143 |
| ExecStop/ExecStopPost | 実行済み・code=exited/status=0の照合PASS | 実行済み・code=exited/status=0の照合PASS |
| GTT停止前→停止後 | 29,054,521,344 → **18,661,376 bytes** | 21,213,184,000 → **18,661,376 bytes** |
| 解放確認 | 全container不在、8731/8732閉鎖、GPU busy=0 | 全container不在、8731/8732閉鎖、GPU busy=0 |
| 設定対の切替・daemon-reload | Dense正本のQuadlet＋専用stopへ切替、実効unit照合PASS | Flash正本のQuadlet＋専用stopへ切替、実効unit照合PASS |
| reboot直前 | inactive、空runtimeとGTTを再確認 | inactive、空runtimeとGTTを再確認 |
| OS reboot | 06:40:53頃に要求、06:41:03 boot | 06:44:04頃に要求、06:44:13 boot |

ExecStop/ExecStopPostの成功は、`verify_stopped`内でsystemdの実行recordを照合し、成功後にのみ設定対更新へ進んだ証拠による。reboot後の新しいunitから前bootの実行recordを再取得したという意味ではない。停止結果・container終了値・GTT・選択確認の各段階は、端末出力に加え既存journalのtag `llm-select`へ記録された。

両回とも終了イベント・GPU解放が最初の観測で成立し、今回の実機試験では期限付き再読取りの待機メッセージは発生しなかった。期限付き経路の検証は第12節の隔離試験による。Denseの143だけで成功扱いせず、上記すべての条件成立後にrebootした。

### 13.3 ログイン前の自動起動・モデル分離

再起動後はSSHを開く前にWindowsからLANの対象portへ直接GETし、health/modelsが期待するモデルを返すことを確認した。再起動後に手動startやrun.shを実行していない。

| 項目 | Dense boot | Flash boot |
|---|---:|---:|
| unit開始（boot後秒） | 6.222 | 6.141 |
| unit active（boot後秒） | 6.687 | 6.580 |
| API listen（boot後秒） | 35.369 | 55.983 |
| 最初のSSH session（boot後秒） | 89.474 | 73.716 |
| WindowsのLAN health/models成功 | **06:41:40 JST / 8732** | **06:45:11 JST / 8731** |
| 最初のSSH | 06:42:32 JST | 06:45:27 JST |
| 稼働container | halogen-denseのみ | halogen-flashのみ |
| 他モデル | Flash不在・8731閉鎖 | Dense不在・8732閉鎖 |
| 実効SuccessExitStatus | 143 | 空 |

両モデルともactive/running、Result=success、NRestarts=0、Restart=no。起動後のselector全preflightもPASSした。Denseはapi/engine=0.1.4、context=262144、slots=1、DFlash2。Flashはapi/engine=0.18.4、context=262144、slots=4、MTP、KV pool=524288、prompt cache mode=2。配置済み正本のimage/checkpoint/RO mount/portを維持した。

user managerとcontainerのmemlock soft/hard unlimitedを確認した。親user managerのTimeoutStopUSec=5s、KillMode=mixed、SendSIGKILL=yes、vendor drop-inは従来どおりで、変更していない。

### 13.4 Thinking ONの日本語APIと実測

**Windows開発PCからLANへ直接POST**。両モデルに同一条件で1リクエストずつ実行した。

- 質問: 「りんご17個を5人に同じ数ずつ配ります。一人何個で、何個余りますか。日本語で簡潔に答えてください。」
- `enable_thinking=true`、`reasoning_effort=low`、`temperature=0`、`max_completion_tokens=4096`、`stream=false`。
- top_p/top_k/seedは未指定。モデル・量子化・context・drafterは変更せず、サーバ既定のThinking effortも変更していない。

| 実測 | Dense | Flash |
|---|---:|---:|
| HTTP / finish_reason | 200 / stop | 200 / stop |
| input / completion tokens | 74 / 86 | 74 / 76 |
| 非空reasoning_content | 275文字 | 190文字 |
| reasoning tokens内訳 | API usageに内訳なし | 60 |
| prompt時間 | 447.2 ms | 439.5 ms |
| generation時間（Thinking含む） | 2104.0 ms | 1123.0 ms |
| pp | **165.474 tok/s** | **168.373 tok/s** |
| tg | **40.875 tok/s** | **67.676 tok/s** |
| Windows wall time | **2.659秒** | **1.655秒** |
| cache_n | 0 | 0 |
| 回答内容 | 一人3個、2個余る | 一人3個、余り2個 |

どちらも日本語の正答と非空Thinking出力を確認してPASS。FlashのThinking APIは最初のSSHより前、06:45:22 JSTに完了した。TTFTは非streamのため未測定。これは切替後の最小疎通確認であり、長文創作品質・長context・持続速度やモデル間の優劣を示すベンチマークではない。思考本文・生応答はGitへ保存していない。

### 13.5 最終状態・完了範囲・Git

**06:46:03 JSTの新規SSHで最終確認:** Flashの同じMainPID・containerが継続稼働し、active/running、Result=success、Restart=no、NRestarts=0、Linger=yes。LAN8731 listen、health ok/idle、Dense不在・8732閉鎖。GTT=29,085,544,448 bytes、busy=0%。実`flash_serve`のmemlockもunlimitedだった。

Flash active Quadlet/stop hashは従来正本の`cb6c6357066d68a0a7a8a035c8b61de8950ffa8847665b4bae23689c8ec03446` / `790f8cc28a2c035c32a9436745bd946f00dc2ea9c088d5c5851cbface958605e`と一致。selector hashも開始時と一致。切替・転送用の一時ファイル残骸はなかった。両bootのkernel journalでOOM、GPU reset、ring timeout、amdgpu fault/failed/errorを単語境界付きで検索し、該当なし。

**修正版による実機往復切替・自動起動・Thinking ON APIの受入はPASS。** 再起動は追加承認の範囲で**今回2回**、前回までと通算4回。今回の承認枠は使い切っており、追加のrebootは実行していない。終了時は指定どおりFlash常駐・Dense停止。

残る不確実性は、ユーザーの最初の中断でどの条件が不成立だったかを事後確定できないこと。今回の往復成功を、初回原因の特定や将来の全切替の無条件保証とはしない。idle検査と新規HTTP到着の競合、突然のshutdown時の親manager期限等の既存制約も維持される。再発時は`journalctl -t llm-select`の対象時刻・bootで停止段階を確認できる。

コードの追加変更はなく、本レポートだけを明示stageしてdiff check・秘密情報を確認し、commit/pushする。自己commit SHA、push・origin/main包含・最終cleanは最終チャットで報告する。
