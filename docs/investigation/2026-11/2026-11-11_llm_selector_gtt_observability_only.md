# HalogenモデルセレクターのGTT閾値撤去・無停止反映

2026-11-11 JST、EVO-X2の `llm-select` を更新した。GTT使用量とGPU busyは、利用者が切替をYesで確定した後の診断ログに記録する。正常停止後に切替が中断した場合は、旧設定対を復元できることを確認し、サービスを停止状態に保つ。実機では標準Flash 0.20.1が同じPID `811249` と同じコンテナでLAN 8731を提供し続けた。隔離試験は79/79件合格した。

## 1. 作業基準と対象

- Windows開発PC上のCodexが `main` で作業し、SSH別名 `evox2` でUbuntuの既存rootlessユーザーとして実機を確認した。開始時HEADは `a335f77baba20014e3d4cc4097baaa34fe69d9b9`、作業ツリーはclean。fetch後の差分は指示書1件で、`f1351d6397c47b3d417120256fc1f1001a35dc16` の `origin/main` 包含を確認してfast-forwardした。[実行した指示書](../../instructions/2026-11/2026-11-11_llm_selector_gtt_observability_only_instruction.md)
- 08:36:48 JSTの実機ではUbuntu 26.04.1 LTS、kernel `7.0.0-42-generic`、`/srv/llm` はext4マウント、Podmanはrootlessだった。旧版の `--show` と読取り専用の全preflightが合格した。既存selectorのSHA-256、3候補のQuadletと停止drop-in計6件、active対、各image IDもGit定義と一致した。
- 前回の更新で標準Flashの稼働GTT中心を29,669,548,032 Bに補正していた。今回はモデル選択がOS再起動を経由する設計に沿って、モデル別の校正自体を撤去した。[前回の実測](2026-11-11_halogen_flash_server_0201_upgrade.md)・[停止結果とコンテナ終了イベントの経緯](../2026-10/2026-10-15_halogen_interactive_model_selector.md)・[3モデルの設定と固定r2](../2026-10/2026-10-17_halogen_flash_uncensored_third_model.md)

## 2. 実装と復旧動作

Gitの実装変更は `deploy/model-selector/llm-select.sh` 1本。実機の配置先は `/srv/llm/engines/model-selector/llm-select.sh`。[実装コミット f75b18a](https://github.com/kendo910x/evox2/commit/f75b18a1aef4b92907de3c5832ace6ec39a41f29)

| 箇所 | 変更後の動作 |
|---|---|
| `running_idle()` | 3モデルの `expected_gtt`、±512 MiB、数値形式、GPU busy=0%の条件を撤去した。systemdの稼働、唯一のコンテナ、image・PID・mount・port、APIのbusy/in_flight/queuedを引き続き確認する。 |
| `empty_runtime()` / `verify_stopped()` | 停止後の基準18,661,376 B＋16 MiBとGPU解放待ちを撤去した。Podmanの全コンテナ不在、8731/8732/8733の全listen不在を検査する。systemd inactive/success、ExecStopとExecStopPostが両方実行されexit 0、対象コンテナIDの単一diedイベント、ExecMainCode/Statusとの一致を確認し直す。Denseは終了0または143、Flash系は0を受理する。 |
| `gpu_counter()` / `log_gpu_observation()` | Yes後の停止前と、stopコマンドが成功を返した直後に1回ずつ既存 `logger -t llm-select` に記録する。停止前の観測の後にAPI idleを再確認する。単一デバイスに帰属するカウンタを個別に読み、欠落・非数値・読取エラーは該当欄を `unavailable`、複数デバイスで帰属不明なら両欄を `unavailable` とする。読取り用 `cat` に1秒のtimeoutと追加1秒の終了期限を設けた。観測のための待機ループや永続ファイルはない。 |
| Yes後の通常切替 | 正常停止と終了イベントを確認し、停止中にQuadletとstop設定を対で配備してreloadする。実効unit、default.target、全コンテナ・ポート不在を検証した後に再起動を1回要求する。選択したモデルの起動は次のbootで行う。 |
| `cleanup()` / `restore_file()` | 正常停止後、再起動受理前の失敗では、停止状態と空のruntimeを確認する。配備済みまたは途中の設定対は、旧退避2件のhashを先に検証し、隣接一時ファイルから復元してreloadする。旧対・unit・停止状態の整合を記録し、旧モデルの自動startを廃止した。復元不能・runtime競合時は退避を保持して異常終了する。復元中の追加HUP/INT/TERMによる二重中断を避け、受理済み再起動へのHUPは従来どおりロールバックを起こさない。 |

`qhash`、`dhash`、`image_name`、`image_id`、`templates_ok`、`identify`、`unit_ok`、`stop_commands_ok`、`wait_container_exit`、`health_idle`、`preflight` の11関数は変更前後の定義がバイト一致した。終了イベントを対象IDに限定して最長10秒再読取する処理、rootless・memlock・GPUデバイスへのアクセス権、Ubuntu起動先、Yesの初期値No、ディレクトリinodeのflockも維持した。

以下は隔離fixtureのjournal記録例。各行は当該時点の観測であり、GPUの物理的解放に関する判定は出力しない。

~~~
phase=preflight 停止前 GPU観測: GTT(bytes)=45000000000 gpu_busy_percent=96
phase=stop-command 停止コマンド後 GPU観測: GTT(bytes)=45000000000 gpu_busy_percent=96
phase=stop-command 停止コマンド後 GPU観測: GTT(bytes)=unavailable gpu_busy_percent=3
~~~

## 3. 隔離検証

タスク専用ディレクトリに実行用コピーと各ケースのHOMEを作り、擬似TTYでセレクターを実行した。systemctl・Podman・sudo・whiptail・loggerは模擬し、診断対象のsysfsもfixture内に置いた。各ケースで終了コード、journal、操作順、最終のQuadlet/stop対、退避の有無を照合した。本番スクリプトにテストモードはない。

| 試験群 | 合格 | 確認事項 |
|---|---:|---|
| UI、読取り、排他 | 23/23 | 各モデルの `--show`、sysfsなしの `--show`、非TTY、Cancel、Esc、同一選択、Noの計21件。加えてflock競合とYes前のHUP。設定対への書込み、journal追加、サービス操作は0回。 |
| 3モデル全6方向 | 6/6 | 各モデルのimage/health/unitを照合。停止後GTT 18,661,376 Bのケースで設定対切替→模擬reload→模擬reboot。Denseの143も終了イベントとsystemdの両方で照合。全方向で同bootのstartは0回。 |
| GTT・busyの観測 | 15/15 | 各モデルで従来の上限超過45,000,000,000 Bおよび下限未満1 Bを停止後にも維持して通過。ほかに0 B、busy 96%、非数値、sysfsなし、複数候補、読取権限なし、FIFO読取timeout、片方のカウンタだけ取得可能の2通りを確認。該当欄の実値・unavailableを停止前後で照合した。 |
| 停止前の異常 | 8/8 | template hash、image ID、health版、API busy・in_flight・queued、BootNext、余分なlisten port。全件でstop・設定切替・rebootを実行せず終了。 |
| 停止処理・終了証拠の異常 | 18/18 | stopコマンド失敗、systemd Result不良、stop/postの非0、died欠落・他IDのみ・重複・誤コード、systemdとの終了値不一致、Flash/Uncensoredの143、無関係のコンテナ残留、各3 portの残留、Podman/ss読取失敗、stop中のHUP。設定対とboot先を維持。 |
| 配備・復元・再起動境界 | 9/9 | 片側rename失敗、片側配備後のHUP、復元中の追加signal、生成unit不整合、模擬reboot拒否では旧対と停止状態を確認。復元rename失敗・復元reload失敗・外部コンテナ出現では旧退避2件を保持。受理される模擬reboot中のHUPでは選択済みの対を維持。全件で自動start・reboot再試行は0回。 |
| **合計** | **79/79** | **失敗0件** |

別途、実Podman Quadlet generatorの `--user --dryrun` と隔離先への生成を3候補で実行した。実効ExecStart、モデル固有のport・RO mount・checkpoint、stop/post、default.targetリンク、Dense限定143を `systemd-analyze --user verify` と合わせて確認した。3/3候補で合格。テンプレート6件は実機と同一だった。`bash -n`、Git差分・実行属性・LFも確認した。

## 4. 無停止での配備と前後比較

既存selectorディレクトリのinodeを `flock` し、他の切替と排他して実機のPID・コンテナ・元script・idle・設定対を再照合した。旧scriptを専用退避へコピーし、SHAを照合した。新scriptを配置先と同じfilesystemの隣接一時ファイルで構文・SHA・所有者・0755を検証し、atomic renameした。`llm-select --show` は配置完了後の解錠中に実行し、再取得後に新scriptの読取り専用preflightと実機の同一性を再検証した。反映完了は08:47:47 JST、最終実機照合は08:48:38 JST。

| 観測 | 開始時 → 反映後 |
|---|---|
| 選択・サービス | 両時点とも `flash` / `halogen-active.service`、active/running、Result=success |
| サービスとbootの同一性 | MainPID `811249`、InvocationID、単調時計の起動時刻、boot IDが一致。NRestarts=0、Restart=no、Linger=yes |
| コンテナ | `halogen-flash` のみ。ID `0e8feffdc340a4c869b4976d4dd087235c119154a76c714ab7642f0980077a7b` で一致 |
| image | `ghcr.io/peonist-ai/halogen-flash-server:0.20.1`、実ID `b0973fd66e5aa886b54cfaf2e4ad976b8d56ad2a2640221beec8dc920ade6e37` で一致 |
| API・port | `/health` はok、api/engine 0.20.1、`halogen-qwen3.8-flash-next`、context 262144、4 slots、KV 524288、cache mode 2、MTP、busy=false、in_flight=queued=0。対象3 portのうち8731のみlisten |
| systemd/設定 | `systemctl --user cat` のSHA-256 `836fe09a4c5be7a198157ecb7dc6243048538b67d590dfea4b438cbb36031b9a` が一致。3候補・activeの設定対が一致。selectorディレクトリinode `25165830`、既存symlink・所有者・0755を維持 |
| script SHA-256（Git内容と実機） | 旧 `1b90b6a0d9774d5dc6a9014fb0c4aa2d94087c70ab38cba20c443b33b7ce3763` → 新 `c4247a559c2e5be63aa7a900e88aa79247cb7f43317e22147c3c963c07ae4b2f` |

実機のモデル切替、サービスstop/start/restart、daemon-reload、OS再起動はすべて0回。作業開始から最終照合まで実サービスの起動停止ログ、対象コンテナの起動停止イベント、実機の `llm-select` journal追加はいずれも0件だった。性能・推論内容の再測定は実施していない。実モデル間の切替、Uncensoredの新エンジンでの実メモリ・推論、次bootの自動起動も未検証である。

## 5. 今回のセレクターだけを戻す手順

今回の旧scriptは `/srv/llm/engines/model-selector/backup-selector-gtt-20261110T234744Z-KaCbGiAY/` に `llm-select.sh` と `SHA256SUMS` を保存した。反映後も照合済み。前回の `backup-0201-20261110T224141Z-KPzZ78H7/` は保存し、既存manifestの11項目が一致した。今回のfixtureと配備用一時ファイルは実機・Windowsの両方で片付けた。

次は今回の新scriptが配置されている間の切戻し手順。EVO-X2の同じrootlessユーザーのBashで実行する。実施時は旧版のGTT閾値と旧モデル自動start動作も戻る。今回の実機で切戻しは実行していない。掲載手順は隔離コピーで3件を検証した。正常時に旧hash・0755に戻り、解錠後の確認に進んだ。flock競合と現行hash不一致ではファイルを保持して中断した。

~~~bash
bash <<'RESTORE'
set -euo pipefail
base=/srv/llm/engines/model-selector
live=$base/llm-select.sh
saved=$base/backup-selector-gtt-20261110T234744Z-KaCbGiAY
expected_new=c4247a559c2e5be63aa7a900e88aa79247cb7f43317e22147c3c963c07ae4b2f
expected_old=1b90b6a0d9774d5dc6a9014fb0c4aa2d94087c70ab38cba20c443b33b7ce3763
sha() { sha256sum -- "$1" | cut -d ' ' -f1; }

exec 9<"$base"
flock -n 9
[[ $(readlink -f /usr/local/bin/llm-select) == "$live" && ! -L "$live" ]]
[[ $(sha "$live") == "$expected_new" ]]
(cd "$saved" && sha256sum --check --strict SHA256SUMS)
[[ $(sha "$saved/llm-select.sh") == "$expected_old" ]]
tmp=$(mktemp "$base/.llm-select-restore.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT
install -m 0755 -- "$saved/llm-select.sh" "$tmp"
bash -n "$tmp"
[[ $(sha "$tmp") == "$expected_old" ]]
[[ $(stat -c '%u:%g:%a' "$tmp") == "$(stat -c '%u:%g:%a' "$live")" ]]
mv -fT -- "$tmp" "$live"
[[ $(sha "$live") == "$expected_old" ]]
flock -u 9
llm-select --show
RESTORE
~~~

切戻し後は `systemctl --user show halogen-active.service -p MainPID -p ActiveState -p Result` と選択中モデルの `/health` を照合する。上記の実装コミットをpush後、`git ls-remote` で `origin/main` の反映を確認した。実施レポートのコミットと最終のremote包含は納品時のチャットに記録する。
