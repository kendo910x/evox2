# Halogen Flash-Next Uncensored HGNを第3のモデルとして追加する指示書

作成日: 2026-10-17

## 1. 目的・方針・モデルの選択

| 項目 | 内容 |
|---|---|
| Git正本 | `kendo910x/evox2` / `origin/main` |
| 作成時基準commit | `8a7585b1be82d4694c7d3484408c4f02c11f7620` |
| Codex開始基準 | 本指示書を含むChatGPTのcommit（受渡しチャットで通知） |
| 実行主体 | Windows開発PCのCodexがGit操作、EVO-X2 Ubuntuへは `ssh evox2` |
| 目的 | 既存の `llm-select` に「Flash-Next Uncensored」を第3の**排他的**選択肢として追加する |
| 原則 | **現行Flash（標準v2）とDense 27Bを一切上書きせず、1つの `halogen-active.service` だけを次回起動させる** |
| 終了時の状態 | 最終は原則Flash-Next標準版がactive/running、Dense/Uncensoredは停止。3候補のテンプレート・UIを残す |
| 対象外 | 既存モデル再量子化、モデル再学習、Halogenエンジンupgrade、コンテキスト/Thinking/precision調整、独自router/daemon/監視、Windows/他PC/v3の変更 |

### 採用する配布物（重要な版選択）

リポジトリ: https://huggingface.co/Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated

**初回採用は2026-09-30の歴史的r2版（revision固定）とする。** 現行`main`の同名ファイルを無条件で取得しないこと。

- **revision**: `e7783c5822dfda2785a0f5b435abf54df89fe8ee`
- **filename**: `qwen38-flash-next-v2-abliterated.hgn`
- **expected bytes**: `88,737,777,792`
- **expected SHA-256**: `7bbac319851b500639462133085156b4f998dec562f511e65ca1c14d7af5163e`
- **起源**: Peonist Halogen Flash v2に、OrcaRouter Uncensoredの拒否応答関連の改変を反映したコミュニティHGN。著者のr2検証には公式v2の同伴n-gram/tokenizerとの起動・推論・品質/速度測定がある。**現行EVO-X2のHalogen 0.18.4での動作は未確認**であり、今回実機で確認する。
- **現行main（2026-10-11）について**: 同名のHGNがBF16由来ネイティブ変換版へ置き換えられ、66,687,678,432 bytes、SHA-256 `b5bd925fa2b44343be4a2cd328cae6b57ce7ffa2fe2cc56281717377e5a1ce8a`。作者はこの現行版と旧公式n-gram/visionを組み合わせたサービングを未検証と明記。**今回の初回導入で選ばない。** 後日ユーザー判断による別評価とする。
- モデルカードの古いr1実測値とr2、そして現行ネイティブ変換版の品質を混同しない。古い/新しいどちらも拒否低減が長文理解力や真実性向上を意味するわけではない。
- ライセンスに注意: 最新のモデルカードは源流BF16の実ライセンスを `Qwen Community License 1.0` としており、過去のApache-2.0表記と異なる。Codexは**採用する固定revision、元donor、Halogen本体の各ライセンス原文をダウンロード前に確認**し、非互換/未承認の利用条件があれば停止して報告。公開Gitにモデルバイナリ/提供者のコード一式を再配布しない。

根拠資料:
- https://huggingface.co/Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated/blob/main/README.md （現在のrelease説明とr2固定revision）
- https://huggingface.co/Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated/blob/main/LICENSE-QWEN
- https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/FLAGS.md （checkpoint/model id/ngram）
- https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/precision.md

**補助ファイルの再利用:** r2の作者は標準Peonist v2のn-gram・tokenizerを同伴させた構成で検証している。本機にある `/srv/llm/models/halogen-flash/qwen38-flash-next-ngram.hgn`（初回導入時bytes `51,200,246,144`、SHA-256 `3450acada94e19aabad88bd49b45eb70304820949c2240fc178067b20ae5dffe`）とtokenizerを**新規ダウンロードも複製もせずRO共有**する案とする。ただし、r2が要求するrevisionの配布メタデータと現物ファイルのSHA-256/sizeが一致することを一度検証し、一致しない場合は勝手に互換と扱わず停止・報告。付属visionは今回text-onlyの受入に必須でない。

## 2. 読むべき既存資料と変更範囲

最初に `AGENTS.md`、次に本指示書を読む。

加えて:
1. `docs/investigation/2026-10/2026-10-15_halogen_flash_initial_deployment.md`（第9節：checkpoint/ngram/tokenizer実hash）。
2. `docs/investigation/2026-10/2026-10-15_halogen_systemd_boot_service.md`（第9～12節：Flash rootless QuadletとLAN公開）。
3. `docs/investigation/2026-10/2026-10-15_halogen_dense_initial_deployment.md`（Dense停止143の由来）。
4. `docs/investigation/2026-10/2026-10-15_halogen_interactive_model_selector.md`（**第11～13節まで**、2026-10-16の往復修正と検証を含む）。
5. 既存の `deploy/model-selector/llm-select.sh` とFlash/Dense両方の `halogen-active.container`＋ `halogen-active.service.d/90-safe-stop.conf`。
6. Podman 5.7 Quadlet/systemdのmanpageとHalogen Flash公式0.18.4の対応要件。

**許可するtracked変更（4ファイルだけ）:**
- 新規 `deploy/halogen-flash-uncensored/halogen-active.container`
- 新規 `deploy/halogen-flash-uncensored/halogen-active.service.d/90-safe-stop.conf`
- 修正 `deploy/model-selector/llm-select.sh`（3モデル対応）
- 新規 `docs/investigation/2026-10/2026-10-17_halogen_flash_uncensored_third_model.md`

既存Flash/Dense両モデルのtracked Quadlet、drop-in、run.sh、過去の指示書とレポート、AGENTS.mdは変更しない。上記新ファイルは実機用正本・実施報告だけであり、モデル実体はGit管理外。

## 3. Phase A: 事前確認とモデル取得

**Windows側Codex:** repo/branch/HEAD/clean/remote、指示書commitの包含確認。fetch/fast-forward、他タスク差分保護。勝手なreset/force pushは禁止。

**EVO-X2 Ubuntu:** 対象ユーザー・OS・Linux専用 `/srv/llm` ext4 mount・disk空き・Podman rootless・Linger=yes・memlock unlimited、GPU read/write、Flash active/running・health idle、Dense inactive、他用途のcontainerがないこと、選択中のFlash active2ファイルがGitの既存hashに一致すること、現在のselector scriptとtemplate hashがリポジトリ最新版と一致することをread-only確認。既存選択がFlashでない、端末/boot条件が変わった、意図しないファイル変更があるなら停止して報告。現行Halogen Flash image `ghcr.io/peonist-ai/halogen-flash-server:0.18.4` とimage IDを記録して固定し、pull/upgradeしない。

**取得量:** r2 HGN約88.74GB（約82.64GiB）。`/srv/llm`実空きと一時領域を確認。転送サイズや実容量が予告から乖離して100 GiB以上の追加データを必要とする場合は停止・報告。モデル領域は新規 `/srv/llm/models/halogen-flash-uncensored/r2/`（既存/別用途のファイルがあれば無断上書きしない）。root/HOME/Windows SSDにGB級コピーを作らない。Flash標準HGN・Dense HGN・n-gramを削除しない。

ダウンロードは公開モデルの**指定filenameかつ`--revision e7783c5822dfda2785a0f5b435abf54df89fe8ee`を必須**とする。再開可能なHF公式クライアントを優先。既存`hf`コマンドがなければ、`/srv/llm`配下の今回専用の軽量venvで`huggingface_hub`/Xetを導入することを許可する（ホストglobal pip/ROCm/apt upgradeは禁止）。取得は一度だけで、失敗時は安全なresume、盲目的な無限retry禁止。コミュニティ提供のtoolingスクリプトや実行バイナリをダウンロードして**実行しない**。チェックポイント本体とライセンス等のテキスト情報だけを取得。

取得後、実ファイルのbytesとSHA-256を**本指示書のr2値**および採用revisionのHFメタデータに対して検証。`b5bd925...`の現行ネイティブ版や`e38f58...`のr1版だった場合、**登録・起動せずSTOP**。既存公式n-gramとtokenizerは現物のハッシュ・要求revを照合し、別コピー不要を証明。付属ファイルの出自と再利用の妥当性を実施レポートに記録。モデルとキャッシュの作業用隠しファイルについても完了時の使用量を記録。

## 4. Phase B: 第3のQuadlet/templateとセレクター拡張

### B1. 3番目のモデルとして追加

表示名: **Flash-Next Uncensored (r2)**、内部選択値: `uncensored`、他の内部値 `flash` / `dense` は維持。

| 項目 | 既存Flash | 既存Dense | 新規Uncensored |
|---|---|---|---|
| ホストAPI | 8731 | 8732 | **8733** |
| 公開先 | 自宅LAN HTTP | 自宅LAN HTTP | **自宅LAN HTTP（0.0.0.0:8733）** |
| container name | `halogen-flash` | `halogen-dense` | **`halogen-flash-uncensored`** |
| model id | `halogen-qwen3.8-flash-next` | `halogen-qwen3.8-27b` | **`halogen-qwen3.8-flash-next-uncensored`** |
| image | `halogen-flash-server:0.18.4` | `halogen:0.1.4` | **既存Flash用0.18.4と同一image/ID** |
| context | 262144 | 262144 | 262144 |
| KV slots | 4 | 1 | 4 |
| KV pool/prompt cache | 524288 / mode 2 | 公式AUTO | 524288 / mode 2 |

新規Uncensored Quadlet:
- 単一 `halogen-active.service` の**候補テンプレート**として作成し、通常のQuadlet探索先に追加の別サービスは作らない。所有label=`io.evox2.halogen.service=halogen-active`、`[Install] WantedBy=default.target`、`Restart=no`、`LimitMEMLOCK=infinity`、rootless、GPU権限、無限memlock、Podman `--ipc=host`などFlash既存と同じ。
- `Image=ghcr.io/peonist-ai/halogen-flash-server:0.18.4`、`Pull=never`、`ContainerName=halogen-flash-uncensored`、`PublishPort=0.0.0.0:8733:8731`。
- **専用HGNをRO mount** `/srv/llm/models/halogen-flash-uncensored/r2:/uncensored:ro`。**既存公式補助ファイルはROで共有** `/srv/llm/models/halogen-flash:/models:ro`。
- `Environment=HALOGEN_CHECKPOINT=/uncensored/qwen38-flash-next-v2-abliterated.hgn`、`Environment=HALOGEN_NGRAM_TABLE=/models/qwen38-flash-next-ngram.hgn`、`Environment=HALOGEN_TOKENIZER=/models/tokenizer`、`Environment=HALOGEN_MODEL_ID=halogen-qwen3.8-flash-next-uncensored`。**HALOGEN_DOWNLOADは設定しない**。Checkpointが自身のdraft headを持つr2なのでGGUF向け `HALOGEN_MTP_HEAD`は指定しない。Visionは今回text-only、余計な再取得・無断有効化をしない。
- モデル、GPU、rootless、image、memlock、/srv/llm、ngram/tokenizer、同名または他のFlash/Denseモデルcontainerの不在、ホストport8733空きなどの `ExecStartPre`ガードを用意。**生成`--replace`による無関係コンテナ削除禁止**。モデル本体のSHA-256チェックを**毎起動/毎切替に行って遅延させない**（Phase Aでの全量照合を証跡化し、起動前はsize・ファイルアクセス・モデルpath等をチェック）。
- 停止drop-inはFlashの同一imageの停止契約を基礎にする。**ExecStop=`podman stop --ignore --time=-1 halogen-flash-uncensored`**、ExecStopPostは所有labelと完全一致container名AND filterの非強制rm、`TimeoutStopSec=infinity`・`SendSIGKILL=no`等を維持。Denseの`SuccessExitStatus=143`は流用しない。もしUncensoredが終了コード0でなく想定外の場合は停止して報告。既存Flash/Denseのdrop-inは一字も変更しない。
- API内部のengine port8730は公開せず、家庭内LAN以外への公開/NAT・Firewall変更、認証やTLSの追加は行わない。

### B2. selectorの3モデル化

元の `deploy/model-selector/llm-select.sh` は2026-10-16に停止イベント観測とGPU解放を最大10秒再確認し、Yes後のみjournalへ段階を記録するよう更新済み。**最新版を基準に拡張し、観測・検査の厳しさを緩めない。**

最低限の変更対象:
- `qhash/dhash`、template検証と内部model識別、image_name/image_id、モデルとcontainer名のmapping、port、モデルごとのsystemd実効SuccessExitStatus、API`/health`のmodel/版本/context/KV/prompt cache、停止イベントcode照合、起動時container/mount/portとGTT検査、空runtimeのport監視を**3モデルで完全に整合**させる。
- 現在の `halogen-$model` 文字列連結は `uncensored`で実際のcontainer名と不一致になるため、モデル別`container_name`等の関数へ置換する。ただし既存Flash/Denseの意味・パス・hashを変更しない。
- Flash/Dense/Uncensoredが同時稼働・port占有されていないことを確認。全ポート8731/8732/**8733**を停止条件・起動条件・ガードへ含める。Uncensoredは既存Flashと同程度のGTT使用見込みだが、**現物でGPU使用量を測り**、モデルに適した検査範囲を設定する。過大に緩めて他モデル混入を許さない。
- `whiptail --radiolist` は3択。現在のmodelのラジオ初期選択、矢印/Space/Tab/OKと続く`Reboot?`確認、**初期No**、No/Cancel/Esc/SSH切断時に**変更ゼロ**、同一モデル選択でrebootなし。Yes後だけ停止・GTT解放・Quadletとdrop-inの対の原子的配備・generator照合・reboot。旧モデルへ復帰する既存ロールバック機構を維持。
- 3モデルとも `halogen-active.service` ただ1つ。別のenable/restart loop・JIT/swap proxy/new user-manager drop-inは導入しない。
- 内部ログ `journalctl -t llm-select` を使うYes後の進捗・異常記録を維持、ログにユーザー固有情報・モデル出力本文を追加しない。

### B3. クライアント設定

今回はOpenCode/Open WebUIの設定ファイル/Pod/K8sをCodexが書き換えない。将来の接続先は `http://<EVO-X2 LAN address>:8733/v1`、モデルID `halogen-qwen3.8-flash-next-uncensored`。**動作中のモデルのみ利用可能**であり、Flash/Denseの既存接続は維持。レポートに3rdモデルの追加方法を一段落で記載すればよい。

## 5. Phase C: 実機受入・起動の順序

**Phase A（取得/ハッシュ/互換照合）と、Phase Bのテンプレート生成・コード差分レビューがPASSするまでFlashを停止しない。**

1. read-only dry run: generatorが3候補それぞれのimage/checkpoint/port、stopとstop-post、SuccessExitStatus（Denseだけ143）、default.targetを正しく生成することを隔離して検査。Bash構文、whiptail3択とCancel/No/same choice/nonTTY/別モデル競合のfixture。現在FlashのPID/config/hash/healthがこれらの試験で変化しないこと。
2. 両モデルの既存シナリオに対する回帰：Flash↔Dense（2択時の仕様）、Flash↔Uncensored、Dense↔Uncensoredでの設定整合性をfixtureで検査。3種類のどの組合せでもcontainerとstop drop-inが食い違わないこと。
3. ユーザーの端末からのYesを経由した実切替試験: **最大2回のEVO-X2 Ubuntu OS再起動を許可**（最初にUncensored選択で1回、後にFlashへ戻して1回）。再起動先がUbuntuであること・対象serviceがidle、他のユーザー作業なし、全停止条件成立を毎回確認。**ユーザーのReboot Yes以外で自動的にrebootしない。** 既存モデル稼働を止める際に強制kill禁止。停止・GTT未解放・異常終了・設定不一致時は再起動せず現状報告。
4. Uncensored選択boot後: SSHログイン前に `halogen-active.service` 自動起動、**モデルIDが独立**、8733 LANで/health/ /v1/models、MTP/Thinking ONの日本語短問、1回のfollow-upとcache確認。認識していないモデル、実HGN不一致、無応答、OOM/GPU fault/メモリ異常ならPASS扱いしない。標準Flashとの差は出力品質まで断定せず、モデル側のUncensored挙動は小規模・非機密な比較だけで確認。拒否低減の再現率を根拠なく保証しない。
5. Uncensoredが正常動作した場合、アイドル化を確認してFlashをUIで選択→Yes→正常停止・GTT解放→設定対復帰→最後のreboot。Flashのログイン前自動起動、LAN8731のAPIとThinking ON、日本語短問、Dense/Uncensored停止・8732/8733閉鎖、既存Flashのhash/性能設定不変を確認する。
6. もし初回Uncensored起動に失敗し安全にOSを再起動してFlashへ戻す必要が生じても、合計のrebootを最大2回とし、**強制GPUメモリ解放やboot設定の変更はしない**。既存稼働サービスの復旧を最優先。Uncensoredが未認定なら3択テンプレートへの登録を完成扱いにしない。再起動枠を使い切った/再起動不可能なら停止・報告、独断の3回目をしない。

### PASS条件

- 正確なコミュニティr2ファイル（pin版とSHA）だけ取得し、必要な公式companionの互換とライセンス条件を確認。
- 3択UI、No/Cancel無変更、正しい停止drop-in、1つの自動起動service、3つのポートが矛盾しない。
- UncensoredのThinking ONとモデルIDが区別でき、通常停止とGPUメモリ解放が実機で確認された。
- 再起動後の選択維持が実機で確認され、最後はFlash標準版が常駐（可能な限り確保）。
- モデルや稼働テストが失敗した場合には、「導入完了」とせず正確に到達点と安全な復旧案を提示する。

## 6. 明示許可する副作用・禁止事項

今回、**指示書をCodexへ渡して作業開始を依頼した場合**に許可するもの:
- 一度限りの**固定r2モデル約88.74GB**のダウンロード、採用SHA-256照合、必要最低限のHFダウンロード用独立venv、`/srv/llm/models/halogen-flash-uncensored/r2`への配置。
- 今回のtracked4ファイルと、それを利用する専用ローカルテンプレート/selectorの更新。
- ユーザーがTTY画面でYesを選んだときに限るEVO-X2のモデル正常停止、設定対の切替、最大2回までの予定OS再起動。既存router/API端末を使用中なら手を止める。
- 指定短問/healthと関連ログの確認、Gitへの自タスクのcommit/push。

明示禁止:
- 現行`main`のネイティブHGNへ勝手に切替、別GGUF/ht43/Swift/低量子化への代用、既存標準Flash/Denseのmodel/imageの削除・再取得・書換、Flash/Denseのtracked定義の変更、前回対応したDense143の処理を消す変更。
- HGN提供者の独自ダウンロードスクリプト・converterを無断実行、rootful/privileged Podman、GPUを2モデル同時ロード、無関係のPodman/image pruning、boot/UMA/カーネル/ホストROCm・電力/親systemd/SSH/認証/Firewall/NATの変更。
- 現行のネイティブ262k context、FlashのKV pool/prompt cache/Thinking/MTP、DenseのDFlash2/W4A4などの品質・メモリ設定を無断変更。
- v3など別repository、OpenCode/Open WebUI側の自動書込、長編創作/耐久検証、外部WAN API公開。

## 7. 報告・Git操作

レポート: `docs/investigation/2026-10/2026-10-17_halogen_flash_uncensored_third_model.md`

最低限記録する内容:
- 指示書path/SHA、実施ホスト/操作主体、branch/開始HEAD/dirty差分・競合、公開可能な環境情報。
- 旧r2採用理由と最新66.7GBネイティブ版の保留理由、採用したHF revision/サイズ/SHA・作者の限定品質証拠・ライセンス差異の確認結果。
- 新規保存ファイル、補助ファイル共有の根拠（revision・hash）、ダウンロード時間/容量・一時キャッシュ残量。
- 追加Quadlet/drop-inとselectorの差分、モデルごとのcontainer/image/port/id/停止結果・GTT・boot自動起動、UI操作/Cancel安全性と3モデルfixture回帰。
- 実機reboot回数、各回のpre/post条件、API/Thinking ON/初回受入、どのモデルが最後に稼働中か。観測していない性能・品質・互換性は未確認と明記。
- 切戻しは**GPUとcontainer解放後**に標準Flash正本2ファイルへ戻す。既存stock/Denseは消さない。失敗による停止状態や未認定モデルを稼働中として誤報しない。
- 事後のクライアント追加方法（URL 8733、専用model ID）。実IP/SSHユーザー/UID/token、モデル本文/思考内容、HF大容量ファイル、ダウンロードcacheは公開Gitに含めない。
- 対象tracked4ファイルだけ明示的stage、`git diff --check`・秘密情報・実行権・LFの確認、`origin/main`へのcommit/pushと自commit包含/clean。force push禁止。

**重要:** CodexはEVO-X2上の現在の稼働状態を自分で確認する。Gitに置いた指示書を読んだだけではモデルを取得・実装・起動したことにはならない。条件を満たせない場合は安全に保留して報告する。
