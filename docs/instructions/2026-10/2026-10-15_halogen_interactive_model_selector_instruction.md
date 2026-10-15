# Halogen Flash / Dense 対話式モデル選択・再起動切替 指示書

作成日: 2026-10-15

## 1. 依頼・運用方針

| 項目 | 指定 |
|---|---|
| Repository / branch | `kendo910x/evox2` / `origin/main` |
| 基準commit | `359445694e4602cf72af31e005c4e47ecc51083e` |
| Codex開始基準commit | **本指示書を含むChatGPT commit**（受渡しチャットで通知） |
| 指示書作成 | ChatGPT |
| 実施主体 | Windows開発PC上のCodex。実機は `ssh evox2` でEVO-X2 Ubuntu |
| ユーザーの要望 | OSインストーラ風の端末UIでFlash/Denseをラジオボタン（カーソル/Space/Tab/OK）選択、続けて「Reboot?」のYes確認で停止・切替・再起動 |
| 変更対象tracked files | `deploy/halogen-dense/halogen-active.container`（新規）、`deploy/halogen-dense/halogen-active.service.d/90-safe-stop.conf`（新規）、`deploy/model-selector/llm-select.sh`（新規）、`docs/investigation/2026-10/2026-10-15_halogen_interactive_model_selector.md`（新規）の4ファイルだけ |
| 参照する既存Flash正本 | `deploy/halogen-flash/halogen-active.container`、`deploy/halogen-flash/halogen-active.service.d/90-safe-stop.conf`（内容・ハッシュは参照だけ。今回は変更しない） |
| 最終状態 | 試験を完了し、**Flash選択・Flash自動起動・Dense停止**を基本とする。Dense起動で運用を終えることがユーザーから別途指定された場合のみ例外 |
| 対象外 | LLM品質の再ベンチ、コンテキスト変更、モデル再ダウンロード、キャッシュ/量子化/デコーダ設定変更、JIT、model router、リモートAPI認証/TLS、他PCやv3操作 |

**基本構造:** 既存の **単一の `halogen-active.service`** を維持し、次回OS起動するモデルに応じて **Quadlet本体と専用停止drop-inを対で差し替える**。新しい常駐デーモン、タイマー、監視サービス、複数の自動起動Quadletは作らない。`[Install] WantedBy=default.target` と `Linger=yes` を維持し、常に1モデルだけがOS起動時に自動起動すること。

**UI仕様:** 必要最小限の `whiptail --radiolist` を採用（Ubuntu apt公式の `whiptail` がなければ **`whiptail`と通常依存に限り追加インストール可**、`apt upgrade`は禁止）。ラジオ選択はFlashまたはDenseの**いずれか一方だけ**。タイトル、現在選択中、選択モデル、サービス/APIポート、操作説明を表示。ラジオメニューのOK後に **`whiptail --yesno --defaultno`** で「リクエストを終了し、モデルを変更してOSを再起動しますか？」と確認。Yesを選んだ場合だけ変更を始める。**No/Cancel/Esc/SSH切断ならモデル選択も設定も変更しない**（後日適用のpending状態を新設しない）。同じモデルを選んだ場合は「現在選択中」を示し、原則再起動しない。

実際の利用方法の目標: `ssh evox2` → `llm-select`、またはTTYを割り当てた `ssh -t evox2 llm-select`。実ユーザー名、LAN IP、UID、秘密情報をpublic repoへ書かない。

## 2. 必ず読む資料と開始時gate

1. `AGENTS.md`、本指示書。
2. `docs/investigation/2026-10/2026-10-15_halogen_flash_initial_deployment.md`。
3. `docs/investigation/2026-10/2026-10-15_halogen_systemd_boot_service.md` の第9〜12節（FlashのQuadlet、正常停止、LAN直接公開）。
4. `docs/investigation/2026-10/2026-10-15_halogen_dense_initial_deployment.md`（Dense通常起動、モデル整合性、停止143、GTT返却）。
5. Flash既存Quadlet/drop-inと `deploy/halogen-dense/run.sh`。
6. Podman 5.7.0 Quadlet仕様、systemdユーザーサービス/drop-in、whiptailの公式manpage。

- Windows側checkoutでGitのbranch、HEAD、remote、`git status`を確認。指示書commitを`origin/main`で確認して安全にfetch/fast-forward。関係ない差分をstash/reset/破棄しない。
- EVO-X2でSSH別名の実機/非root実行ユーザー、`sudo -n true`、Linux用 `/srv/llm` mount、rootless Podman、`/dev/kfd`/`/dev/dri`、Linger=yes、memlock unlimited、既存image、モデルファイル・ディレクトリ、既存 `halogen-active.service`の実状態を確認。
- 開始時Flashは既存サービスとしてactive/runningの想定。実機の `~/.config/containers/systemd/halogen-active.container` と `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf` がGitのFlash正本と一致することを確認。違う場合は独断で上書きしない。
- Denseの既存 `ghcr.io/peonist-ai/halogen:0.1.4` image、`/srv/llm/models/halogen-dense`内の標準 `qwen3.8-27b-p1w4d-d2.hgn` と tokenizer が存在。モデルは既に全ファイル配布metadata照合済み。再hash（約36GB）・再ダウンロードはしない。
- CPU側RAM約121GiB、UMA=2GiB、OSはUbuntu Server、現時点のbootはUbuntu先頭という既知前提が維持されていることを最小限に確認。UEFI/GRUB/BIOSへは触れない。
- Flashで既存API公開 `0.0.0.0:8731`、Denseで `0.0.0.0:8732`（容器内8731）を維持。ユーザー指定の自宅LAN HTTP、認証なしでよい。ただしルーター・NAT・Firewall・IPv6のWAN公開を変更しない。
- 競合しているrootless容器/別taskの生成物、新規のサービス、対象pathの所有者・内容が想定外なら停止・報告。

公式資料:
- https://docs.podman.io/en/v5.7.0/markdown/podman-systemd.unit.5.html
- https://manpages.ubuntu.com/manpages/noble/man1/whiptail.1.html
- https://github.com/peonist-ai/halogen-server/blob/main/README.md

## 3. Phase A: モデルごとの設定を完成

### A1. 現行Flashを正本にする

既存のFlash用Quadlet/drop-inは**一文字も変更しない**。ユーザーの実機ではFlashは既に常駐稼働、LAN8731、`Restart=no`、正常停止`podman stop --time=-1 halogen-flash`＋安全な非強制rmで検証されている。これが切替・rollback用の基準。

### A2. Dense版のactive Quadletと停止drop-in

tracked新規:
- `deploy/halogen-dense/halogen-active.container`
- `deploy/halogen-dense/halogen-active.service.d/90-safe-stop.conf`

**両モデルともファイルの最終名は `halogen-active.container`、生成unitは `halogen-active.service` のまま**。Dense版も `[Install] WantedBy=default.target` とし、既存のFlash用active定義と**決して同時設置しない**。

Dense Quadlet:
- Image=`ghcr.io/peonist-ai/halogen:0.1.4`、`Pull=never`、`ContainerName=halogen-dense`。
- Dense所有ラベル=`io.evox2.halogen.service=halogen-active`を維持、名前はモデル別。
- Denseの `/srv/llm/models/halogen-dense:/models:ro`、tokenizer `/srv/llm/models/halogen-dense/tokenizer:/tokenizer:ro`。
- `HALOGEN_CHECKPOINT=/models/qwen3.8-27b-p1w4d-d2.hgn`、`HALOGEN_TOKENIZER=/tokenizer`。**HALOGEN_DOWNLOAD未設定**。0.1.4のDFlash2（2）、W4A4（64）、context（262144）、slots（1）、prompt cache自動など既定を維持。別量子化・低品質モード・context縮小をしない。
- `PublishPort=0.0.0.0:8732:8731`のみ。外部公開は自宅LAN内前提。コンテナ内部engine用8730は公開しない。
- `/dev/kfd`、`/dev/dri`、`GroupAdd=keep-groups`、`--security-opt seccomp=unconfined`（Denseコンテナ限定）、`--ipc=host`、`Ulimit=memlock=-1:-1`。rootless。 `Restart=no`、`LimitMEMLOCK=infinity`。
- Flashと同等のread-only `ExecStartPre`ガード：/srv/llm mount、Dense image/モデル/tokenizer、GPU、rootless/memlock、8732未使用、既存の同名containerなし。Quadlet生成`--replace`が異なる所有の同名containerを消すことのないよう**生成ExecStart前のガードを必須**とする。
- 前回Dense手動停止は`podman stop --time=-1`成功・GTT基準復帰でも、容器exit=**143**（SIGTERM相当）。専用drop-inはDense名を使い、`ExecStop`を`podman stop --ignore --time=-1 halogen-dense`、`ExecStopPost`を**非強制・サービス所有ラベル＋Dense名のAND filter**にする。Flashの停止drop-inを流用して文字列`halogen-flash`を残さない。 `TimeoutStopSec=infinity`、`Restart=no`、`SendSIGKILL=no`などFlash実績に合わせる。ただし**exit 143を無条件で成功と塗りつぶさない**。systemdが実際に報告するResult・ExitStatus/Signalと、API/engine正常終了・コンテナ消滅・GTT返却を分けて確認し、必要なら限定的な`SuccessExitStatus`設計を理由と共に提案して一度止まる。
- Podman 5.7.0で`StopTimeout=-1`は拒否されるため絶対に使わない。Quadlet自動生成のforce rmはdrop-inで実効停止コマンドから除く。親user managerの5秒制限は前回同様変更しない。

この時点では**両方のテンプレートをGitに置くだけ**であり、DenseのQuadletを常時起動用の探索先へ追加してはならない。

### A3. selector配置とUI

tracked新規 `deploy/model-selector/llm-select.sh` を作成。Ubuntu上では `/srv/llm/engines/model-selector/llm-select.sh` として設置。Flash/Denseの各Quadletとdrop-inテンプレートを、モデル別のサブディレクトリにGitとハッシュ一致で設置する。実機のactiveパスは従来の2ファイルを維持。

シェル実装は過剰なライブラリ・プログラミング言語・HTTP常駐daemon不要。通常の Bash + whiptail + systemctl + Podman + coreutils + `flock`（標準util-linux）で十分。実機で使用可能な`flock`を確認。存在しない場合は勝手に別frameworkを入れず報告。

ユーザーがどのディレクトリからでも `llm-select` と実行できるよう、**`/usr/local/bin/llm-select`** に当該スクリプトへの専用symlink/小さなwrapperを新規作成してよい（同名が存在したら停止し上書き禁止）。インストール後、実行権・所有者・シンボリックリンク解決を確認。

UIは端末必須（non-TTYからの呼出は安全に拒否しrebootしない）。`whiptail --radiolist`で候補 **Flash-Next、27B Denseの2択**、現在選択を反映、選択/OK/Cancel、続く`--yesno --defaultno`のReboot確認。画面表示で「Flash API 8731、Dense API 8732。クライアントの進行中処理は切断され得る」「Noは変更を適用しない」を明示。任意文字列、第三のモデル、複数選択、勝手なオートタイマーなし。

設定の正本は**現在実機に設置されている active Quadlet + stop drop-in**。このモデル識別とテンプレートハッシュが一致しない場合は安全のため拒否する。独自の選択stateやpendingファイルを別途作らず、モデル名はFlash/Denseのallowlistに限定。検証用`--show`等の**完全read-only操作**は許可するが、確認を迂回して切り替え・再起動する隠しオプションは設けない。

UIでNo/Cancel/同一モデル選択した場合には、サービス・ファイル・daemon-reload・rebootを一切変更しない。

## 4. Phase B: 承認後の切替トランザクション

**切替はユーザーが画面上のYesを明示的に選んだ場合に限る。** テンプレート上書き前に全前提と両方のSHA-256を検証、他の切替実行を`flock`で排他。すべての実行対象はユーザー単独の既存 `halogen-active.service` と専用activeファイル2件。

以下の順序を守る:

1. 実際に現在起動中の `halogen-active.service` / container / `/health` / `busy=false, in_flight=0, queued=0` などのidle条件を確認する。API応答不能、長いOpenCode tool処理中、想定外の同名/別モデル稼働、GPU使用やsystemd stateが矛盾する場合は**停止せず失敗終了**。ユーザーに作業中クライアントを終了してから再実行してもらう。直前に再確認するが、idle検査と新規HTTP到着の競合を完全に排除する保証はないと明記。
2. `systemctl --user stop halogen-active.service` で**通常停止**。容器が消え、ポートが消え、GTTが停止後の過去基準（約18,661,376 bytes）付近まで戻ったことを確認。force-kill/reboot禁止。停止不能・GTT未解放なら**テンプレートを書き換えず停止**。
3. 選択したモデルのQuadletとstop drop-inの**2ファイルを対で**設置。別々のコピーが一時的に生じる点は、すでにサービス停止済みの条件と排他で制御。各ターゲットの同ディレクトリにテンポラリを配置し、ハッシュ確認、原本をロールバック可能に退避してからrenameする。他のファイル・設定は変更しない。1個目の反映後に2個目が失敗したら確実に旧2ファイルへ戻す。独自sleepでタイミングを隠さない。
4. `systemctl --user daemon-reload`でgenerator再生成。 `systemctl --user cat/show halogen-active.service`、`systemd-analyze --user --generators=true verify`等で**選択モデルのimage/model/port、Stop/StopPost両方、Restart=no、active default.targetの依存**が整合することを確認。model/idと停止処理が異なる組合せならrebootしない。
5. 今回の選択を表示した後、**選択内容が正しいと検証できた場合のみ** `sudo -n reboot` を実行。ユーザーがYesを押す前には`sudo reboot`を呼ばない。実行失敗時は旧定義へロールバックし`daemon-reload`、可能なら旧モデルの正常起動を試みる（原因不明/GTT異常なら重ね起動せず報告）。SSH切断によってrebootが正常に進む場合を単純な失敗と誤認しない。

**重要:** 手動切替のために強制的に子プロセスを終了しない。sysfs GTTが返らない場合、以前のFlash導入調査と同じくGPU保持異常の疑いがあるため別モデルをロードせず保留。意図しないshutdownや停電まで正常停止を保証するわけではなく、親user-managerの5秒制限は維持する。

**バリエーション:** Denseの正常停止がsystemd上でexit 143によりfailure扱いになる場合は、当該Dense実装の停止契約と生成unitの実効値を調べ、単にforceやrootfulへfallbackしない。SIGTERM起因の終了コードと実際のメモリ解放を区別して評価、必要な追加設定は承認範囲を超えるなら停止・報告。

## 5. テスト方針と再起動

### A. 実機状態を壊さない試験

- `bash -n`、`shellcheck`が存在するなら任意で静的確認（新規導入は不要）、whiptailのUI表示、初期選択、キャンセル、No、同一モデル選択、非TTY失敗、誤テンプレート拒否、排他競合の狭い確認を行う。
- **No/CancelでQuadlet hash、service PID、Linger、API応答、reboot状態が不変**であることを確認。
- 双方テンプレートに対しPodman 5.7.0 generatorのdry-runとサービスの停止設定を確認。Denseも公式image・modelを使い、Flash版との重複GPUロードが生じない。

### B. 受入: Flash → Dense → Flash

- Codexによる**実際のモデル切替テスト用OS再起動は、合計最大2回まで**に制限する（各回、対象Ubuntu機のみ、現在のリクエストが終了済みであることを必ず再確認）。毎回TTYのYes確認を通す。ユーザーが当該時点で作業中、またはboot先に不確実性があれば実行せず `WAITING_FOR_USER_REBOOT` と報告する。無理に2回再起動することを成果条件にしない。
- 1回目にDenseを選択。既存Flashからの停止・GTT解放・設定対の整合→OS再起動。ログイン前の`halogen-active.service`自動起動、Dense container名`halogen-dense`、Denseの`/v1/models`、8732のLAN利用、Flash停止/8731閉鎖、実モデルGTT、Thinking ON日本語短問を確認。**Dense起動用の手動run.shは利用しない**。
- Dense→Flashの切替前に **Dense serviceのsystemd停止結果、container終了状態・exit=143が許容できる正常TERM経路か、GTT解放**を明記。想定外なら二度目のrebootに進まない。
- 2回目にFlashを選択してOS再起動。ログイン前にFlash自動復帰、health/models/Thinking ON、Flash8731のLAN直接HTTP、Dense containerなし/8732閉鎖、既存Flash設定hash/機能が不変であることを確認。Linger=yes、memlock unlimited、no restart loops。
- どちらかでboot失敗・SSH不達などが起きたら無限試行、別ホストへの操作、3回目の再起動、UEFI/GRUB修正へ独断で進まない。検証を留保し原因・復旧案を報告。終了時状態を明確にする。

### 受入条件

1. whiptailラジオUIがキー操作・キャンセル・No・Yesで期待どおり動作。
2. 選択が**唯一の`halogen-active.service`**の起動対象としてOS再起動後まで維持。SSHなしで起動。モデルが同時常駐しない。
3. 各モデル独立したimage/checkpoint/port/DFlash2/MTP/Thinking/量子化/262144 contextを保持。途中で自動的にlower qualityや小contextへ落とさない。
4. **停止にforce killを使わない**。退出コード143の読み方を含め、正常停止・GTT返却とsystemdの有効状態を区別して記録。
5. Flash→Dense→Flashでboot/APIの実証。問題が発生した場合は到達点と現状を明示し、PASSを誇張しない。

## 6. 禁止事項・承認境界

許可:
- Ubuntu公式`whiptail`の必要時最小導入、対象のテンプレート・selector・コマンドsymlinkの新規設置、**ユーザーがYesを選んだ条件付き**の選択中サービスのsystemd正常停止/設定対の更新/daemon-reload/`sudo -n reboot`。
- 実装受入試験としてUbuntu機の条件付き再起動合計最大2回、`/health`等の短いAPI検証、指定Git4ファイルのcommit/push。

禁止:
- 既存Flash Git正本・イメージ・モデル・stop drop-in内容の無断変更、Dense既存image/model/run.shの変更や再取得、Podman/systemdの全体reset・prune、rootful/`--privileged`への切替、強制kill/force rm、親user-manager/PAM/sudoers/SSH/firewall/ルーター/UEFI/BIOS/UMA/カーネル更新。
- 外部WAN公開、追加のネットワークlistener/HTTP proxy、認証変更、model router/JIT/常駐監視timerの追加、OpenCode/Open WebUIやv3への操作。
- 再起動を避けるための同時メモリロードや両モデルの自動起動登録、テストのための長編・長時間負荷試験。
- コンテキスト・モデル品質パラメータの暗黙変更。ユーザーは**長い設計相談の品質と精度を重視**しており、コンテキストは両モデルとも既定ネイティブ262144、FlashのKV pool/prompt cache 2、DenseのKV slot 1/prompt cache AUTO、Thinking ON既定のまま。モデル切替とは独立の品質議論・検証で扱う。

失敗時は必ず元データ/現稼働モデル/設定の状態を区別し、今後の判断材料とする。代替パッケージや新たな上位管理システムへ無断切替しない。

## 7. 報告・Git反映

レポート:
`docs/investigation/2026-10/2026-10-15_halogen_interactive_model_selector.md`

必須記載:
- 実行した指示書SHA、起点HEAD、branch、Windows/EVO-X2の実行分担と対象host確認（公開repoへIP/ユーザー名/UID/UUID/secretを載せない）。
- selector UIの使用方法 `ssh -t evox2 llm-select`、操作キー、No/Cancel時の動作、モデルとAPIポート、ファイル配置と追加パッケージ。
- Flash/Denseテンプレートのhash/生成unitの設定・有効な停止コマンド、唯一のactiveモデル状態、Lingerとユーザーマネージャー継承。
- 正常停止/GTT前後・rebootの実施回数・各bootのSSH前自動起動とAPI/Thinking ON・Dense143判定、PASS/FAIL/未実施の厳密区分。
- ロールバック：対でFlashの設定へ戻す操作は、必ず対象モデルを正常停止・GTT解放した後。取消では変更しない。専用symlink/selector/templatesを撤去しても既存Flash通常サービスが維持される手順。
- 追加した実機ファイル/symlink、保存先、必要な操作と元へ戻す方法、未解決事項、他タスク/既存設定の非変更。
- 対象**4つのtracked fileのみ**を明示的stageし、`git diff --check`、秘密情報検査、pushと`origin/main`への包含・clean確認。実施レポートの自己commit SHAは最終チャット報告でよい。

原則、最終状態は**Flash自動常駐、Dense停止**。改修不成立の場合でも無断のforce/rebootをせず、ユーザーが再開判断できる証跡を残す。
