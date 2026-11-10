# EVO-X2 HalogenモデルセレクターのGTT閾値撤去・再起動前提の安全条件整理 指示書

作成日: 2026-11-11 JST  
Git正本: `kendo910x/evox2` / `origin/main`  
作成時参照HEAD: `a335f77baba20014e3d4cc4097baaa34fe69d9b9`  
実行主体: Windows開発PC上のCodex。EVO-X2 Ubuntu実機への操作は既存SSH別名 `evox2`。  
Codex作業開始の基準: **この指示書を追加するChatGPTのcommit**。`AGENTS.md`に従ってfetch・包含確認を行う。

## 1. 目的・今回確定した判断

既存 `llm-select` は、**モデル切替のたびにOSを再起動し、旧モデルと新モデルを同一boot内に連続ロードしない**設計である。したがって、過去に測ったGTT（GPUから利用するシステムメモリのAMDGPU計上値）が一定値に収まることを、通常の切替・再起動の**必須条件とするのをやめる**。

従来の2つのGTT判定を廃止する。

1. **稼働中:** `running_idle()` で、Flash / Dense / UncensoredごとのGTT期待値±512 MiB以内を要求する判定。
2. **停止後:** `gpu_released()` / `wait_gpu_released()` および `empty_runtime()` 経由で、GTTが過去の停止時基準（18,661,376 B +16MiB）へ戻り、`gpu_busy_percent=0`であることを必須とする判定。

**GTT・GPU busyは切替可否の根拠ではなく診断ログとして残す。** GTTが取得できない場合も、その事実を`unavailable`等としてログに残し、**それだけでは中断しない**。同時に、既存の**正常なサービス停止結果、停止対象コンテナの終了イベント、全コンテナとポートの消失、設定対・image IDの一致、OS起動先の安全性、ユーザーのYes確認**は厳格に維持する。

重要な限界: OS再起動は、正常完了すれば旧bootのプロセス/GPU割当を引き継がないが、**再起動コマンドを発行しただけでGPU状態が回復する保証はない**。正常停止できない場合、別のGPU負荷や起動先不明などの異常がある場合は、依然として切替を止める。**停止失敗をrebootで押し切る変更ではない。**

現在正常稼働している標準Flash 0.20.1を変更・停止せずに、このセレクターだけを改修・反映する。今回の作業中に実モデル切替、OS再起動は行わない。

## 2. 既存構成と根拠

必ず次を読む:

- `AGENTS.md`、本指示書
- `deploy/model-selector/llm-select.sh` の全体、とくに `gtt_baseline` / `gtt_tolerance`、`gtt()`、`gpu_released()`、`empty_runtime()`、`wait_gpu_released()`、`verify_stopped()`、`running_idle()`、`preflight()`、`cleanup()`、Yes後の切替トランザクション
- `docs/investigation/2026-11/2026-11-11_halogen_flash_server_0201_upgrade.md`（最新0.20.1実機受入・GTT増加・selector hash・退避・OS再起動未実施）
- `docs/investigation/2026-10/2026-10-15_halogen_interactive_model_selector.md`（第11～13節を含む正常停止/復元設計）
- `docs/investigation/2026-10/2026-10-17_halogen_flash_uncensored_third_model.md`（3択の排他・固定r2）
- 現行3モデルのQuadletと `90-safe-stop.conf`（**参照のみ**）

直近レポートでは標準FlashがHalogen `0.20.1`、API `8731`、`halogen-active.service` active/running、Linger=yes、Restart=no。次の設定がGitに記録されている。

- `flash`: API8731、image `halogen-flash-server:0.20.1`
- `dense`: API8732、image `halogen:0.1.4`
- `uncensored`: API8733、image `halogen-flash-server:0.20.1`
- どのモデルも同じ単一 `halogen-active.service` の排他候補。変更するのは選択スクリプトだけ。
- 最新の実行用scriptは `/srv/llm/engines/model-selector/llm-select.sh`、候補 `templates/{flash,dense,uncensored}/`、active Quadletは `~/.config/containers/systemd/halogen-active.container`、停止設定は `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf`。`/usr/local/bin/llm-select`は既存symlink。
- 旧版からの安全切戻し資料 `/srv/llm/engines/model-selector/backup-0201-20261110T224141Z-KPzZ78H7/` は**別タスクの退避として保存し、変更・削除しない**。

実機状態はリポジトリだけでは確定できない。上記は参照実績であり、最初に実機read-onlyで再確認する。

## 3. 実装仕様（GTTに依存しない切替）

### A. 撤去するハードゲート

- `running_idle()`のモデル別 `expected_gtt`、その±536,870,912B判定、GTTの取得・数値形式の成否による`return 1`を撤去。`gpu_busy_percent`単独の0%条件も切替判定から外す。GTT/busyの数値は観測できれば診断に残す。
- `empty_runtime()`は**全containerの不在＋8731/8732/8733の全listen不在**を検査する機能にする。`gpu_released`による成否を合成しない。既存のstrictな「無関係のcontainerも拒否」契約を勝手に緩めない。
- `verify_stopped()`の`wait_gpu_released()`必須待機を撤去。必要条件は引き続き `ActiveState=inactive / Result=success`、`ExecStop` / `ExecStopPost`それぞれexit 0、対象containerの正しい`died`イベント・終了コード、systemdのExitStatusとの一致、全container・全port消失、再確認、である。**Denseのみexit 143を正常終了契約の範囲で許す**。そのほかの異常終了は許さない。
- `gtt_baseline`、`gtt_tolerance`、`gpu_released`、`wait_gpu_released`および使われなくなった関連変数・メッセージは整理する。絶対的GTT基準値を別の形で作り直したり、単に許容範囲を巨大にしたりしない。
- `gtt_files=(...)` が一意・読取可であることを切替の前提にする現行チェックも変更する。診断値が取得不能・複数候補・非数値であっても**診断 unavailable**とし、この理由だけで事前検証を失敗させない。

### B. GTT・GPU busyの記録

- **Yes後のみ**、旧モデル停止前と停止後に、可能な範囲で`GTT bytes`と`gpu_busy_percent`を記録する。採取はread-only、有限時間・簡潔で、失敗しても続行可能。従来の`logger -t llm-select`の既存journalに残し、専用ログ・監視プロセス・状態ファイルを増やさない。
- 稼働中preflightからGTT診断関数を呼ぶなら、成功可否には関与させず、診断のタイミングがNo/Cancel/同一モデル選択で状態やjournalを書かない既存契約を破らないようにする。
- 予期しない使用量・busyの観測結果を**「正常なGPU解放を確認した」や「安全な再ロードを保証した」という意味のログにしない**。`reboot前に確認したのは正常停止・container/port消失であり、GPU物理状態は診断値にすぎない`と区別する。
- 新たに全GPUプロセス検出やメモリ監視サービスを作る必要はない。既存のプロセス/Port/Podman・systemd所有検査は維持する。

### C. 切替・復旧経路の安全性

通常のYes後トランザクションは従来の順序を維持:

1. 本人操作TTYでモデル選択・`Reboot?`の初期`No`から**明示`Yes`**。
2. 対象実機、source/templateとimage ID、rootless/memlock、Ubuntu起動先、systemd/Podman/Health idle、他container/port、排他lockを確認。直前にidle再チェック。
3. `systemctl --user stop halogen-active.service` で通常停止。**強制kill禁止**。`verify_stopped`の上記非GTT条件を確認し、満たせない場合はQuadlet差替・rebootへ進まない。
4. 停止中にactive Quadlet + stop drop-inを**対で**安全に配置・ハッシュ照合、`systemctl --user daemon-reload`、実効unit/`Restart=no`/default.target/stop契約の整合を再検証。`empty_runtime`を再確認。
5. その後はじめて `sudo -n reboot`。新モデルは**再起動後にだけロード**する（同boot内で新モデルをstartしない）。

**重要: reboot失敗時の同boot復旧を見直すこと。** 現行`cleanup()`は切替中断時に元設定へロールバックした後、`safe_stop`が立てば**同じbootで旧モデルを自動startする**。GTT解放を必須判定から外す以上、ここを無条件に残すと「OS再起動のリセットに依存する」という設計と矛盾する。

今回の単純化では、**停止完了後～OS再起動が受理される前に失敗した場合、元のQuadlet/drop-in対を復元してreload・整合検証するが、旧モデルの自動再ロードは行わない**。正常な元設定と復旧状態を記録し、サービスを停止状態に保ってユーザーに状況を報告する。`reboot`が受理された後は、従来どおり勝手にロールバックせず、次bootで選択モデルを起動する。これにより正常切替ではGTTの硬いチェックを使わず、異常時も同bootでモデルを重ねロードしない。

例外として停止コマンド自体が成功したと確認できない場合、`empty_runtime`不一致、コンテナの異常終了・`ExecStop`失敗・systemd状態不一致などでは、**旧設定の復元の可否自体を慎重に判断し、復元が安全に証明できなければ退避を保持して停止・報告**。無条件reboot / reboot retry / rollback-startによる回復を試みない。

停止処理の実行中にSSH接続が切れた場合、`sudo reboot`要求時のHUP/exitの扱い、再起動完了後の診断手順は従来の実績を尊重する。**既存のYes・No・Cancel・Esc・同一モデル・非TTY・flock・hash・atomic rename・rollback復元機能は維持する。** 変更に伴う復旧仕様の差（旧モデルの自動startは廃止）を実施レポートへ明記する。

### D. 既存機能を変えないこと

- 3択UI・モデルID・APIポート・イメージ/コンテナID・model/checkpoint・tokenizer・context 262144・キャッシュ/Thinking/MTP、Active Quadletの対、stop/drop-in（`podman stop --time=-1`、非強制post、Dense143契約）、Linger=yes、Restart=noに変更なし。
- `unit_ok()`、`health_idle()`、`stop_commands_ok()`、`wait_container_exit()`、`templates_ok()`、`identify()`、`preflight()`の**GTTと無関係な安全条件を緩めない**。
- 新しいrootful/privileged Podman、engine、モデル、サービス、追加daemon、設定state、常駐監視、OS/firmware変更は不可。

## 4. 変更・副作用を許可する範囲

許可するtracked変更:

1. **`deploy/model-selector/llm-select.sh`のみ**（実装）。
2. 限定テストが必要なら `tests/` 以下の小規模テスト（既存構成に合わせる。外部依存を追加しない）。
3. **`docs/investigation/2026-11/2026-11-11_llm_selector_gtt_observability_only.md`**（今回の実施レポート）。

**Git上で変更禁止:** `AGENTS.md`、過去の指示書/レポート、3モデルのQuadlet・停止drop-in、他の `deploy/` 配下スクリプト（run.sh含む）、modelファイル。変更必要なら止めて根拠を報告する。

許可する実機の書込み:
- 既存 `/srv/llm/engines/model-selector/llm-select.sh` **1本の置換だけ**。既存所有者/実行権を維持し、旧scriptを同じ領域に限定退避してからatomic rename。
- 必要な限定テスト用の**作業一時ファイル**。完了後削除、既存の`backup-0201-...`は保持。
- Git commit/pushと実施レポート記録。

**実施を許可しない副作用:** `systemctl --user stop/start/restart`、`daemon-reload`、`sudo reboot`、`podman run/stop/rm/pull`、モデル切替`Yes`実行、別PC・OpenCode/OpenWebUI・v3等の変更、apt/package update、BIOS/GRUB/カーネル/driver/ネットワーク設定変更、ファイル/イメージのpruneや破壊的削除。**今回の反映は稼働中のFlashを止めずに行う。** sudoを伴うread-only検査は既存権限の範囲で許可する。

## 5. Codex実施順序

### Phase A: read-only preflight

Windowsで `git fetch`、branch/HEAD、`git status`、`origin/main`包含、指示書commitの取得を確認。想定以外の変更を上書きしない。

EVO-X2で選択中モデル、`llm-select --show`、標準Flash `/health`、`systemctl --user show/cat`、container/image、port、既存script SHA-256/owner/mode、templates/active対のhash、`/srv/llm` mount、rootless・Linger等を確認。開始時のscript・サービスのPIDと設定を記録する。既存scriptとGit現行正本が不一致、既存サービスが正常でない、他の同名操作中の場合は**書込みに進まない**。

### Phase B: scriptのみの修正・隔離テスト

現在の`llm-select.sh`の本体だけを最小差分で修正。`bash -n`、`git diff --check`、必要なら既存方式のmock/pty fixtureで、`systemctl`/`podman`/`sudo reboot`を**模擬**する。実機サービスを変更しない。

最低限の試験ケース:

| ケース | 期待する挙動 |
|---|---|
| Flash/Dense/Uncensoredがそれぞれ有効に識別される | モデル・image・health・systemd照合PASS |
| GTTが新旧基準の±512MiB外（例: Uncensored起動後の増分相当） | **他の条件が正常なら切替前preflight PASS** |
| GTTが高止まり・0・非数値・sysfs取得不可・GPU busy>0 | **GTTだけでは失敗にしない。診断に値またはunavailableを記録** |
| 正常stop、GTT高止まり、全container/3port消失、終了イベント正常 | **設定対切替→模擬rebootまで進む** |
| 正常stop、停止後のGTTが従来の18MB近辺 | 同じく模擬rebootまで進む |
| systemd stop失敗 / `Result!=success` / stop・post exit非0 | 必ず中断、モデル切替/rebootなし |
| 対象containerのdied欠落・誤コード、別container・port残留 | 必ず中断、モデル切替/rebootなし |
| Denseのみexit 143正常、Uncensoredの143拒否 | 以前と同じ |
| No/Cancel/Esc/同一選択/非TTY | 配置・journal追加・service操作・rebootなし |
| 3モデルの6方向の選択 | いずれも同一bootで新モデルをstartせず、整合した設定対の後に模擬reboot |
| unit不整合/テンプレート配備途中失敗/模擬`sudo reboot`失敗 | 旧設定対の復元を確認、**同bootの旧モデル自動startなし**、再bootなし、異常状態を明示 |
| 中断・signal/SSH切断を模擬 | 旧版の誤ロールバック防止・一時ファイルの保護/適切な復元を維持 |
| 診断sysfsが読めないが他は正常 | Yes後のログはunavailable、正常ケースは続行 |

既存fixtureがなければタスク用の小さいmockで構わない。危険な`TEST_MODE`/強制切替コマンド/本番バイパスを常設しない。3候補の`qhash/dhash`や実効generatorも変化しないことをread-onlyで確認する。

### Phase C: 無停止実機反映

1. もう一度現在のFlash APIのidle、サービスPID/コンテナID、元scriptのSHA、テンプレート対/所有者、他の`llm-select`実行・作業競合の不在を確認。
2. **既存selectorディレクトリのinodeを`flock`**し、旧script（0755）とそのSHAを復元可能な形で退避。既存`backup-0201-...`と混同・上書きしない。
3. 新scriptを同じfilesystem上の一時ファイルへ転送。`bash -n`・SHA・mode・所有者を照合し、`atomic rename`で `/srv/llm/engines/model-selector/llm-select.sh` だけ置換。ディレクトリinodeと既存symlinkを維持。
4. `llm-select --show` は自身もflockを取るため、**ロック保持中に再帰実行しない**。一度安全にロック解除して`--show`でモデルとserviceが不変なことを確認、再取得が必要なら適切に確認する。必要なread-only関数検査は`Yes`を呼ばない隔離環境で行う。
5. 現在のFlashが**同じPID・container・image・8731 API・health**で継続、Dense/Uncensoredが停止、ポート8732/8733閉鎖、実行権・対象ファイルSHA一致、Linger/Restartに差がないことを証明。OS再起動は0回。GTTの取得が失敗しても`--show`の成功/失敗に影響しないことをfixtureで確認。
6. 配置・検証で失敗した場合は稼働中のserviceに触れず、旧scriptのみ安全にatomic復元。元状態を再検査し、成功と報告しない。元scriptが見つからない・競合している場合はそれ以上操作せず停止・報告。

## 6. 完了条件・安全停止条件

**PASS:**
- 稼働中GTT期待値の固定閾値/停止後GTT解放閾値/`gpu_busy_percent=0`が通常のモデル切替を阻害しない。
- 代わりに`systemd/Podman`の正常停止と実行対象の終了証拠、全container/port不在、設定と起動先の検証が**引き続き必須**。
- Yes後のGTT・busyは診断専用。sysfs読取不可でもそれ自体は停止理由にしない。
- reboot失敗・設定復元等の中断分岐で**同bootの旧モデル自動startをしない**。退避/復元の整合と異常報告ができる。
- No/Cancel等では副作用ゼロ。3候補・全6方向の隔離テストに合格。
- 実機反映後もHalogen Flash 0.20.1/8731は同一PIDで稼働し、サービスstop/restartもOS rebootも実施0回。ロールバックはscriptだけで可能。

**停止して報告:** GTT以外の安全ゲートが壊れた、停止イベントの成功判定を弱める必要がある、同一bootで新モデルを起動しなければならない、他プロセス/コンテナ/SSH/OS設定変更が必要、実機状態とGitが一致しない、他タスクの同path競合、mockでロールバック不能、許可外のservice操作や再起動が必要。

**未実施扱い:** 実際のFlash↔Dense↔Uncensoredモデル切替、Uncensored新engineの実メモリ・推論、OS再起動後の起動確認（今回の実機では行わない）。fixture PASSをこれらの実機成功として扱わない。

## 7. 報告・Git反映

報告先: `docs/investigation/2026-11/2026-11-11_llm_selector_gtt_observability_only.md`。

最低限、指示書path/commit、開始時branch/HEAD/dirty状態、操作ホスト・開始/終了時モデル、変更したscriptのSHA（Git/実機）、関数別変更箇所、GTT基準を削った範囲、診断ログ例（機密を含めない）、mock検証件数・成功/失敗、実機の旧/新script・PID・port・healthの不変性、復旧自動startをやめた影響、rollback（scriptのみ）の具体手順、未実施項目を記載する。

関係ないファイルをstageせず、`git diff --check`・`bash -n`・mode・LF・秘密情報を確認。`deploy/model-selector/llm-select.sh`と今回のレポート、許可された最小テストだけをcommit/pushし、`origin/main`への包含と作業ツリーcleanを確認する。force push・history rewriteは禁止。
