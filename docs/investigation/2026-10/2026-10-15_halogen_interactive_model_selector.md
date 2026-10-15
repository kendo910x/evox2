# Halogen 対話式モデル選択・再起動切替 実施レポート

## 1. 結論・現在状態

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
