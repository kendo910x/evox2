# Halogen Flash Server 0.18.4 → 0.19.1 更新・3モデルセレクター整合 指示書

作成日: 2026-11-08 JST  
対象: `kendo910x/evox2` / `origin/main`  
作成時の参照HEAD: `7389dffeaa8b0d6b3453dc2e53777980c690c31a`  
実行主体: Windows開発PC上のCodex。EVO-X2 Ubuntuには既存SSH別名 `evox2` で接続する。  
この指示書の保存コミットを作業開始基準とし、実作業前に最新 `origin/main`・実機との差を確認する。

## 1. 目的・決定済み方針

**Flash系推論サーバーのコンテナだけを `ghcr.io/peonist-ai/halogen-flash-server:0.19.1` に更新し、既存の3択モデル切替、モデルの内容・品質設定、安全停止・復旧を維持する。**

| 選択値 | 現行image（Git管理定義） | 更新後 | ホストAPI |
| --- | --- | --- | --- |
| `flash`: 公式Qwen3.8-Flash-Next v2 | `halogen-flash-server:0.18.4` | **`halogen-flash-server:0.19.1`** | 8731 |
| `dense`: Qwen3.8-27B Dense | `halogen:0.1.4` | **変更しない** | 8732 |
| `uncensored`: 固定Flash-Next abliterated r2 | `halogen-flash-server:0.18.4` | **`halogen-flash-server:0.19.1`** | 8733 |

モデル選択は従来どおり**排他**。唯一の `halogen-active.service` が選択中のモデルだけを提供する。作業開始時に選択されているモデルを勝手に `flash` に変更しない。現時点の稼働モデルはリポジトリからは確定できないので、必ず実機で確認する。

**対象外:** モデル重み（標準v2 HGN、固定Uncensored r2、Dense）の再取得・再量子化・修正、MTP/Thinking/temperature/context変更、別モデル採用、NPUモデル・Agent Guardの新規有効化、GPU/カーネル/BIOS/OS/Podman更新、OpenCode/OpenWebUI/v3等の別環境変更。特に `HALOGEN_NPU_MODELS`、`HALOGEN_AGENT_GUARD` は今回追加しない。

公式根拠（2026-11-08確認）:
- https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md （0.19.1 / 0.19.0、既存Flash checkpoint変更なし）
- https://github.com/peonist-ai/halogen-flash-server （Quickstartが`:0.19.1`を指定）
- https://github.com/peonist-ai/halogen-flash-server/pkgs/container/halogen-flash-server/versions （0.19.1公開manifest digest: `sha256:7ab5c3dfd77acb2387603f1807069cac3494e678f413c0670745ba2df74c0f0e`）
- 0.19.0には全ファイル書換え等の高速化、0.19.1にはツールschema異常時のslot解放などの修正がある。ただし速度向上を無条件に保証せず実機で測る。NPU向けXRT同梱は今回のNPU未使用構成では移行操作不要。

## 2. 最初に読む資料・現状の注意点

1. `AGENTS.md`（権限・Git・秘密情報・安全停止の規約）。
2. `deploy/model-selector/llm-select.sh`、`deploy/halogen-flash/halogen-active.container`、`deploy/halogen-flash-uncensored/halogen-active.container`、`deploy/halogen-dense/halogen-active.container`、3モデルそれぞれの `90-safe-stop.conf`、`deploy/halogen-flash/run.sh`。
3. `docs/investigation/2026-10/2026-10-17_halogen_flash_uncensored_third_model.md`（3モデル実機受入と固定r2）。
4. `docs/investigation/2026-10/2026-10-15_halogen_interactive_model_selector.md`（第11～13節の停止イベント・GTT・往復再起動）。
5. `docs/investigation/2026-10/2026-10-15_halogen_systemd_boot_service.md`（rootless Quadlet、Linger、停止drop-in、LAN）。
6. 公式CHANGELOGの0.18.4より後～0.19.1、および版が変わったAPI・起動フラグの仕様。

**重要な実装上の落とし穴:** selectorは3候補のQuadletと停止drop-inをSHA-256で固定し、Flash/Uncensoredのコンテナimage ID、`/health`のversion、実効systemd unit、GTTなどまで検査する。**QuadletのImageタグだけ書き換えてはいけない。** さらにUncensoredのQuadletには0.18.4の実image IDを照合する`ExecStartPre`がある。ここも更新する。Denseのimage/正常停止exit 143契約は変更しない。

参照HEAD時点の配置:
- ローカル正本: `/srv/llm/engines/model-selector/` 配下のscript・`templates/{flash,dense,uncensored}/`
- 実効Quadlet: `~/.config/containers/systemd/halogen-active.container`
- 実効停止設定: `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf`
- modelは`/srv/llm/models/`以下、rootless Podman storageは`/srv/llm/containers/podman`。
- `/usr/local/bin/llm-select`は既存scriptへのsymlink。既存の所有者・配置を実機で照合する。これらは**参照時点の構成**であり、実機が違えば追跡してから判断する。

## 3. 変更可能範囲・副作用

Gitで変更を許可するのは以下のみ:
- `deploy/halogen-flash/halogen-active.container`
- `deploy/halogen-flash-uncensored/halogen-active.container`
- `deploy/halogen-flash/run.sh`（旧タグの手動起動を残さない）
- `deploy/model-selector/llm-select.sh`
- 必要最低限の限定テストを追加する場合は`tests/`以下
- 実施レポート `docs/investigation/2026-11/2026-11-08_halogen_flash_server_0191_upgrade.md`

**変更しない:** `deploy/halogen-dense/*`、3モデルの既存stop drop-in、既存指示書・過去の実施報告・`AGENTS.md`、モデル実ファイル。既存契約の修正が不可欠と判明した場合は根拠を示して停止・相談し、ついでの整理をしない。

実機で許可する副作用は、0.19.1コンテナimage**1種類の取得**、対象専用テンプレート/script/実効Quadletの更新、選択中Flash系サービスの**通常停止と再起動（systemd start、OS rebootではない）を各最大1回**、必要な最小限のAPIテスト、対象作業の一時退避とGit commit/push。停止失敗時の追加stop/startや環境全体の復旧操作は独断で繰り返さない。`systemctl --user daemon-reload`は許可する。

**OS再起動は今回の基本作業に含めない。** 3択UIの実切替はユーザーが明示的にYesを選ぶとOSを再起動する仕様なので、別途ユーザー承認がある場合のみ実施。通常は隔離fixtureで3候補を検査し、未起動の候補を「実機推論までPASS」と報告しない。`sudo`は必要な読み取り確認のみ。ホスト全体の更新・再起動や別repositoryへの書込みは禁止。

## 4. Phase A: 変更前ベースラインと版・互換性確認（read-only）

**Windows/Codex:** `git fetch`、branch/HEAD/`origin/main`包含・作業ツリー状態を確認。無関係の変更をstage・削除せず、指示書のcommitを含む版で作業する。`AGENTS.md`の指示に従う。

**EVO-X2/SSH:** ログイン先が対象Ubuntuであることを確認。現在の選択は `llm-select --show` とactive Quadlet/実効unitの両方で特定する。`systemctl --user show/cat`、`podman ps -a`、image ID/digest、`curl /health`、`/v1/models`、listen port、GPU GTT/busy、rootless、memlock、`/srv/llm` mount、Linger=yes、空き容量、現行script/template/active対のhashを記録する。秘密情報・IP・全文プロンプトは公開レポートへ記録しない。稼働中モデルと3候補の整合を確認し、正常時は無断停止しない。

開始時点の`Image`と実コンテナIDを区別し、旧`:0.18.4` image ID/manifest digestと新imageの識別子を保存する。**既存imageは切戻し用に保持**する。0.19.1の配布tag/manifest、ホストアーキテクチャ、checkpoint/HGN読み込み条件、必要ディスク容量、ライセンスを公式資料で確認。上記の0.19.1 manifest digestと配布先に不整合があれば原因調査、解消不能なら取得/反映を停止（manifest digestとローカルimage IDは別の識別子なので混同しない）。

現在選択がDenseなら**Denseを停止しない**。Flash/Uncensored稼働中ならAPIの既存短問・tool呼び出し（可能なら）・Thinking ON・短いコード編集風タスクを数回測定して、後比較の基準にする。記録は入力長、reasoning有無、モデルID、completion、pp/tg tok/s、TTFT・wall（取得できる範囲）、finish_reason、tool call構造。全出力・思考本文は記録しない。`busy`や`in_flight`が0でないなど使用中ならサービス停止に進まない。

## 5. Phase B: image取得、ソース修正、無停止検証

1. **イメージ取得:** `/srv/llm`の空きとPodmanの保存先を確認し、専用の `ghcr.io/peonist-ai/halogen-flash-server:0.19.1` だけ `podman pull`。必要なら既存`/srv/llm/containers/tmp`の利用を検討。取得後は`podman image inspect`で実image ID、RepoDigests、manifest/architecture、image metadataを記録。旧0.18.4とDense 0.1.4は消さず、`latest`に置き換えない。`Pull=never`を維持。モデル本体をダウンロードさせる`HALOGEN_DOWNLOAD`は追加しない。
2. **Quadlet:** 標準FlashとUncensoredの両方のImageを0.19.1へ。Uncensoredの`ExecStartPre`で照合するimage IDも新取得imageの実測値に更新。ポート8731/8733、固定r2のsize/HGNとRO companion、既存model ID、GPU、memlock、IPC、rootless、`Restart=no`、`ConditionPathIsMountPoint`などを維持。変更のないDense/stop drop-inは触らない。
3. **script:** `deploy/halogen-flash/run.sh`のタグとpreflightを更新し、通常のrootless・`--pull=never`・既存設定と整合。実行は不要。
4. **selector:** `qhash()`は更新したFlash/Uncensored Quadletの実SHA-256へ、`dhash()`は既存3 drop-inの実SHAを維持。`image_name()` / `image_id()`をFlash/Uncensored 0.19.1へ、Denseは0.1.4のまま。`health_idle()`のFlash/UncensoredのAPI/engine期待版を0.19.1へ更新。model ID、slot数、context 262144、KV pool 524288、prompt cache mode 2、MTP、DenseのDFlash2と143許容、停止/GTT/空port検査、ログ、ユーザーのYes gate、rollbackは維持。新versionの`/health` schema差異があれば仕様と実測で調べ、確認を安易に緩めない。
5. **GTT:** Flash系の従来`expected_gtt`および±512MiB検査はまず維持。新engineで実測変化が生じた場合のみ、差分と再現性を示して**必要最小限のmodel別閾値**へ調整。GPU解放baseline（約18,661,376B）や他モデル同時起動禁止は緩めない。
6. **隔離検証:** Bash構文（`bash -n`）と`git diff --check`、全テンプレートのsource hash/mode、Podman Quadlet generator `--user --dryrun`で3候補それぞれの実効ExecStart/stop/post、image/port/checkpoint/default.targetを確認。必要なら既存レポートと同じ一時fixtureで`llm-select`の3択・6方向モデル組合せ、No/Cancel/Esc/同じ選択、非TTY、image/hash不一致、busy、停止失敗、GTT未解放、Dense exit 143、rollbackを検査。systemctl/stop/rebootはmockとし、実サービスに触れない。fixture用の危険なbypassを本番scriptに残さない。

**ここまでの証拠と差分に問題が出たら本番停止・配置に進まない。** 新版imageが既存HGNを読めない根拠がある場合も同様。

## 6. Phase C: 安全な実機反映（選択中モデルに応じて）

共通条件: モデルを利用するOpenCode/OpenWebUI等のクライアント作業が終了していることを確認し、メンテナンス中の新規APIリクエストを避ける。開始直前にidle、source hash、実unit/stop契約、container/ports、GPU、起動先のモデル、イメージを再確認する。既存`/srv/llm/engines/model-selector`**ディレクトリのinodeを維持**し、そのflockで既存セレクターとの並行更新を防ぐ。旧script（0755）、3テンプレート、active Quadlet+stop対、旧image ID/タグを専用ローカル退避。退避は必要最小限、同一filesystem上の一時ファイル→hash/mode確認→atomic renameを基本とし、混在中はselectorを実行しない。退避場所と復元方法を記録する。

### C1. 現在選択が `flash` または `uncensored`

1. 変更前のidleを再確認し、既存`halogen-active.service`を`systemctl --user stop`で**通常停止**。既存stop drop-inによる非強制`podman stop --time=-1`、systemd Result、実container終了イベント/exit、container/全port消失、GPU GTT基準への返却・busy=0を確認。従来の最大10秒観測を参考にし、停止が確認できなければ新imageを起動・設定を切替えない。force-kill/再起動でごまかさない。
2. 3候補の新テンプレートと新scriptを配置する。選択中のactive Quadletは**同じモデルの0.19.1版**へ変更。既存stop drop-inは同一hashのまま対で整合を検証。新Quadlet/selectorのハッシュ・所有者・modeがGit成果物と一致することを確認。
3. `systemctl --user daemon-reload`し、生成されたunitのimage/checkpoint/port/stop/post、`Restart=no`、WantedBy、memlock等を`systemctl --user show/cat`、`systemd-analyze --user --generators=true verify`で確認。`llm-select --show` と3候補のpreflightに矛盾がないことを確認して**元と同じモデル**を`systemctl --user start`で1回起動する。
4. `/health`、`/v1/models`、実image ID、port分離、GTT、ログ・OOM・GPU fault等を確認。Thinking ON日本語回答、非stream/stream、OpenAI互換tool callと引数の正しい終端、follow-up、cache、必要なら`/v1/responses`を短く試す。既存クライアントの書換えなしでWindowsからLAN直接応答を確認。更新前と同一条件で速度/終了理由/品質を比較する。実測値の悪化と既知不具合（途中停止、偽ユーザーターン、tool引数欠落、slot枯渇）を注意して観察する。ただし有害な模擬prompt注入などの高負荷試験は不要。
5. **もう片方のFlash系候補は実機で未起動なら未検証と明記**する。3候補の静的整合PASSを、全モデルの新エンジン上の実動作PASSへ読み替えない。

### C2. 現在選択が `dense`

Dense `halogen:0.1.4`、active Quadlet/stop対、稼働プロセスは変更しない。フラッシュ系の候補テンプレートと新selector/手動run.shのみ、前述の排他・退避・atomic renameで安全に更新する。Denseの実効unit・/health・GTT・portが不変、`llm-select --show`が正常、3候補のimage ID/hash preflightが成立することを確認。**Denseを止めてFlashを同時ロードしたり、勝手にモデル切替/OS再起動を行わない。** Flash系の実推論検証は次回ユーザー承認のモデル切替後の保留項目とする。

### 共通の切戻し

起動・unit・health・重要機能の不一致、繰返す性能大幅悪化、モデル読み込み失敗、OOM/GPU faultがあれば、まず状況を記録。通常停止でき、container/port消失・GTT返却が確認できる場合のみ、**新scriptと3テンプレートおよびactive Quadlet/stop対を旧版へ一貫して戻し**、旧0.18.4/0.1.4のimageが存在することを確認、`daemon-reload`、旧unit整合確認後に元モデルを通常起動してAPI復旧を検証する。旧image/重みを削除しない。

通常停止が完了せずGPUが返らない、rollbackに必要なファイルが足りない、状態が矛盾する場合は**そこで停止し、二重起動・force kill・OS rebootをしない**。操作段階、サービス/GTT/portの現況、復旧に必要な判断を報告。部分適用のまま「更新完了」としない。

## 7. 受入条件と検証の線引き

- Flash/Uncensoredの候補`:0.19.1` image、検証済image IDとtemplate SHA-256が一致し、旧`:0.18.4`は保持。Dense`:0.1.4`は不変。
- selectorの全3候補の静的検査・UI無変更経路・停止と復元のfixtureがPASS。選択中モデルのservice/stop contract、常駐自動起動定義、port排他、262144 context、Thinking/MTP/キャッシュ、rootless等が維持。
- 選択中がFlash系の場合は、更新後の**実モデルAPI・短いツール呼び出し・日本語Thinking ON・停止/起動**の実機証拠がPASS。ユーザー側OpenCode/OpenWebUIの設定変更不要。選択中Denseの場合は現行稼働維持と新候補の登録までを完了範囲とし、Flash系の実機受入は**DEFERRED**。
- 0.19.1について「性能が何%改善」と断定するのは実際に同条件で比較した場合のみ。上流のベンチ数値をこのEVO-X2の実測と混同しない。性能目標のためにcontext短縮、Thinking OFF、重み/量子化変更をしない。
- 起動後の自動起動定義は確認するが、今回OS再起動をしない場合は**boot後再稼働の実測は未実施**と明記。
- 成功・部分完了・ロールバック・停止を区別する。検証PASSと未実施を混同しない。

## 8. 禁止事項・停止条件

禁止: 新NPU/Agent Guard有効化、未承認の複数モデル常駐、別ports/API公開範囲の拡大、rootful/privileged Podman、`--replace`に任せた他container削除、`podman image prune`、旧image/model削除、無条件`sudo reboot`、`kill -9`/force removal、OS/カーネル/BIOS/UEFI/GRUB/ネットワーク/認証変更、Windows SSD/他repository/クライアント設定変更、資格情報やモデル本文のpublic repo掲載。

次の場合は停止・報告: リポジトリと実機の配置/ハッシュが想定から実質的に異なる、0.19.1 imageの同一性が不明、公式checkpoint/Uncensored r2との互換性に具体的な疑義、停止契約不成立、稼働中クライアントあり、非idle/GTT未解放、原状復帰できない、許可外操作が必要。勝手に安全ゲートを緩めない。

## 9. 実施レポート・Git反映

レポート: `docs/investigation/2026-11/2026-11-08_halogen_flash_server_0191_upgrade.md`。

最低限: 指示書path/commit、開始時Git HEAD/branch/dirty状態、実行主体・日時、実機の選択モデルと開始/終了状態、旧新image ID/RepoDigestとコンテナ設定、変更したtracked/localパス、3候補の新hash、検査件数とPASS/FAIL、変更前後のAPI/性能比較（測定条件付き）、止めた/起動したserviceと終了イベント/GTT証拠、実機未検証モデル、ロールバック可否、残課題・再起動未実施、最終のモデル/port/Linger/Restart。

実装＋レポートだけを明示的に`git add`して`git diff --check`、mode、LF、秘密情報を確認しcommit/push。`origin/main`への自commit包含とcleanを確認。force pushや別タスク差分の破棄は禁止。報告文は「稼働中モデルだけ実機PASS」「3候補の設定PASS」「他モデル未実機検証」など**どこまで確認できたか**を明確にする。
