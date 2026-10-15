# Halogen Qwen3.8-27B Dense 初回導入・単体検証 指示書

作成日: 2026-10-15

## 1. 対象と基本方針

| 項目 | 指定 |
|---|---|
| repository / 正本 | `kendo910x/evox2` / `origin/main` |
| 作成時基準commit | `7d1f31e4fce1b233d76a9b351af2d0288780a9d3`（Flash LAN公開済み） |
| Codex開始基準commit | **本指示書を含むChatGPTのcommit**（受渡しチャットで通知） |
| instruction publisher | ChatGPT |
| 実施主体 | Windows開発PCのCodex。EVO-X2操作は `ssh evox2` |
| 対象OS/機材 | Ubuntu Server 26.04.1 / Strix Halo gfx1151 / 統合メモリ128GB（UMA明示2GiB、Linux約121GiB） |
| 実装範囲 | **Qwen3.8-27B Denseを独立配置し、正常起動・API・日本語Thinking ONを確認** |
| tracked write scope | `deploy/halogen-dense/run.sh`（新規）と `docs/investigation/2026-10/2026-10-15_halogen_dense_initial_deployment.md`（新規）の**2ファイルのみ** |
| 実機保存先 | `/srv/llm/models/halogen-dense`、`/srv/llm/engines/halogen-dense`、既存rootless Podman graphroot |
| 外部取得 | 公式Dense版imageおよび公式HGNモデル一式の初回一度限りの取得を許可 |
| 最終状態 | **Flash-Nextの既存 `halogen-active.service` をactive/runningに復帰させる**。Denseは検証成功後も停止、OS起動時は引き続きFlash |
| 対象外 | Denseの常駐化、再起動式モデル切替の実装、JIT/共通router、Flash設定変更、カーネル/firmware/BIOS変更、長時間ベンチ・長文耐久 |

**目的:** 現在常用中のFlash-Nextサービスを破壊せず、Dense版の**別コンテナ**で実機の速度と品質を確認し、次の「OS再起動でactiveモデルを選択する」taskの判断材料を得る。Flash/Denseの同時GPUロードは禁止。今は既存`halogen-active.container` / `90-safe-stop.conf` の置換やDense自動起動の登録を**しない**。

### 公式配布物（実装前に実在・最新版仕様を再照合）

- Dense専用エンジン: https://github.com/peonist-ai/halogen-server （**Flash版 `halogen-flash-server` とは別リポジトリ**）。
- 公式固定image: `ghcr.io/peonist-ai/halogen:0.1.4`（`latest`は禁止）。
- 公式weights: https://huggingface.co/peonist-ai/halogen-qwen3.8-27b
- 標準HGN: `qwen3.8-27b-p1w4d-d2.hgn`、公称約35.9GB。公式トークナイザは`tokenizer/`直下。
- 公式起動要件: `--device /dev/kfd --device /dev/dri --group-add keep-groups --security-opt seccomp=unconfined --ipc=host`。このseccomp緩和は**Denseのrootlessコンテナに限定して許可**する。rootful/`--privileged`へ拡張しない。
- モデルID: `halogen-qwen3.8-27b`。デフォルトcontext=262144、KV slots=1、drafter=**DFlash2 (2)**。別モデルや低精度版を使用しない。
- 公式の参考速度はDFlash2で平均31.7tok/s、散文では約21～24tok/s、コード等で約33～44tok/s（作者のテスト）。Flashの実測約50～60tok/sより低速でも即失敗としない。**Denseの文章品質・一貫性が主たる評価目的**。
- モデル配布ページのライセンスとエンジンEULAは別。ダウンロード前に両方を確認し、ライセンス条件に未承認の変更があれば報告。
- Dense 0.1.4の公式READMEは `response_format` の `json_object/json_schema` 強制デコードを**未実装として400**にする。OpenCodeの全機能互換性を推測しない。tool callingとは分けて評価する。
- Denseの `HALOGEN_W4A4` は公式既定64で、prefill高速化と数値品質のトレードオフが開示されている。**今回は公式標準の設定のまま計測し、数値品質上の注意を記録**。黙って0等へ切り替えたり、後から品質同等と結論づけたりしない。DFlash2/シリアル出力同等性（条件付き）とも混同しない。

必ず最初に読む:
1. `AGENTS.md`
2. 本指示書
3. `docs/investigation/2026-10/2026-10-15_halogen_flash_initial_deployment.md`
4. `docs/investigation/2026-10/2026-10-15_halogen_systemd_boot_service.md`（第9～12節を含む）
5. `deploy/halogen-flash/halogen-active.container` と `deploy/halogen-flash/halogen-active.service.d/90-safe-stop.conf`
6. Halogen Dense公式README、`docs/FLAGS.md`、`CHANGELOG.md` とモデルカード

## 2. 開始時gate（実機read-only）

**Windows開発PC**でcheckoutのrepo・branch・HEAD・remote・`git status --short`を調べ、`git fetch origin main`後、本指示書commitの包含を確認。競合しない最新変更のみ安全に取り込み、別taskの作業を破棄・stash・resetしない。対象pathの既存ファイル・別task差分があれば停止。

**EVO-X2 Ubuntu**でSSH aliasから実ホスト/非rootユーザー/`sudo -n true`、OS/kernel、`/srv/llm`のLinux専用LVマウントと空き、GPUノードの権限、`loginctl`のLinger=yes、rootless Podmanの`graphroot=/srv/llm/containers/podman`、image管理、8732/TCPの未使用を確認。

**Flashの実動作を必ず現物で確認:** `systemctl --user status halogen-active.service`、実際のQuadlet・drop-inとGit正本の内容/hashes、`/health`、コンテナ/port8731状態を読む。**この時点ではサービスを停止しない**。現行Flashはすでに`PublishPort=0.0.0.0:8731:8731`で家庭内LANから利用している可能性が高い。今回の作業で127.0.0.1へ戻さない。

利用する別ポートはホスト**8732**、Denseコンテナ内のAPIは**8731**。既存Flashの8731とは別。家庭内LAN限定のHTTP、ユーザー指定に従い**認証・TLSなし**を許可するが、ルーター/NAT/Firewall/SSH設定・IPv6公開・外部ポート転送は変更しない。ホストが外部から直接到達可能な構成と分かった場合はLAN全公開をしないで報告。

モデル保存先に100GiB以上の空きがあることを確認。既存Flashのモデル、cache、image、runningコンテナを削除/上書きしない。Pythonのホストglobal pipや追加ROCm一式、GUI、Dockerは導入しない。予想外の権限不足/条件不一致なら停止・報告。

## 3. Phase A: 新規Dense配布物の準備

### A1. 保存先・pull

新規`/srv/llm/models/halogen-dense`、`/srv/llm/engines/halogen-dense`を作成。既存パスにデータがある場合は書き換えず調査。所有者は対象rootless実行ユーザー。Linux SSD以外に大容量ファイルを保存しない。

公式image `ghcr.io/peonist-ai/halogen:0.1.4` をrootless Podmanへ`pull`。`TMPDIR=/srv/llm/containers/tmp`を明示し、home/root/var/tmpをGB単位で使わない。imageのdigest/ID、容量、EULA/版を記録。

モデルの取得予定は約35.9GB＋tokenizer/metadata。**同一モデルの重複取得をしない**。目安を大幅に超え、ネットワークから新たに55GiB以上の取得を要求する場合は停止・報告。モデル専用ディレクトリの使用量と残量も記録。

### A2. Flashの一時停止gate

GPU処理・Dense bootstrapへ入る直前に、Flashの`/health`でbusy=false/in_flight=0/queued=0を確認し、ユーザー処理中なら待機して再確認。**未完了の長いOpenCodeツール処理を確認なしに中断しない。**

idleなら、既存 `systemctl --user stop halogen-active.service` で**正規の正常停止**を実行（今回明示許可）。コンテナ消滅、8731閉鎖、systemd success、GTTが以前の停止後基準（約18.7MB）へ復帰したことを確認。強制kill、`podman rm -f`、`systemctl --user disable`、Quadlet置換、リブートはしない。停止が固まる・GTT未解放なら**Denseを起動せず停止し報告**する。

### A3. 初回モデルダウンロード

公式の `HALOGEN_DOWNLOAD=peonist-ai/halogen-qwen3.8-27b` を使う**初回bootstrap一度限りの取得**を許可。保存先はDense専用RW mountの`/models`とし、`HALOGEN_TOKENIZER=/models/tokenizer`とする。**初回は`/models/tokenizer`を別ボリュームでmountしない**（未作成ディレクトリを自動作成して取得を壊す危険）。checkpointは`/models/qwen3.8-27b-p1w4d-d2.hgn`。

参考形（実際のimage/OS/flagsをCodexが照合すること）:

```bash
# [EVO-X2 Ubuntu] Flashが完全停止・GTT解放済みになってから
podman run -d --rm --pull=never --name halogen-dense-bootstrap \
  -p 0.0.0.0:8732:8731 \
  --device /dev/kfd --device /dev/dri --group-add keep-groups \
  --security-opt seccomp=unconfined --ipc=host \
  --ulimit memlock=-1:-1 \
  -e HALOGEN_DOWNLOAD=peonist-ai/halogen-qwen3.8-27b \
  -e HALOGEN_CHECKPOINT=/models/qwen3.8-27b-p1w4d-d2.hgn \
  -e HALOGEN_TOKENIZER=/models/tokenizer \
  -v /srv/llm/models/halogen-dense:/models \
  ghcr.io/peonist-ai/halogen:0.1.4
```

バックグラウンドコンテナと実`Linger=yes`を確認し、SSH切断による停止事故に備えて状態を監視する。初回ダウンロードが切断等で失敗した場合は原因を確認してから公式の再開機能を用い、blind loop再試行しない。`/health`で初回checkpoint ready確認後、`podman stop --time -1 halogen-dense-bootstrap`で正常停止、GPU解放を確認する。ダウンロード用コンテナが消えない場合は無理に強制削除しない。

ファイルサイズとSHA-256をHugging Faceの配布metadata（LFS/Xetによる信頼できるdigest/リビジョン）と照合する。モデル・tokenizerを別名のFlashファイルに上書きしない。公開repoにはモデル本体やprivate情報をcommitしない。

## 4. Phase B: 再現可能な通常起動・API・品質

### B1. 通常起動script

**Windows repo**に `deploy/halogen-dense/run.sh` を新規作成。最小限のBash。Linuxホストの`/srv/llm/engines/halogen-dense/run.sh`へ1ファイルだけ転送し、ハッシュ・LF形式・`bash -n`と実行権を確認する。

scriptは、Ubuntu・非root・rootless Podman、`/srv/llm` mount、image存在、checkpoint/tokenizerの読み取り可能・非空、GPUアクセス、memlock、**Flashの`halogen-active.service`がinactiveであること**、同名Dense containerがいないこと、8732未使用を検査してから起動する。**Flashサービスをscript内部で勝手に停止しない**。

通常起動は `podman run -d --rm --pull=never --name halogen-dense` とし、公式固定image、GPU、keep-groups、Dense専用`--security-opt seccomp=unconfined`、IPC、memlockを設定。`-p 0.0.0.0:8732:8731`、Denseモデル`/models:ro`、**tokenizer`/models/tokenizer`を`/tokenizer:ro`へ別途明示mount**。これ以外のモデル領域へ書込しない。`HALOGEN_DOWNLOAD`を**指定しない**。checkpoint`p1w4d-d2`を明示、DFlash2は公式既定2を維持。コンテナに新たなsystemd常駐service/Quadlet登録・自動起動・restart policyを与えない。

### B2. APIと実測

`/health`、`/v1/models`に対するHTTP 200、version match、`model=halogen-qwen3.8-27b`、rootless/GPUロード、DFlash2がデフォルトとして有効、Thinking controlとmodel readyを確認する。

最小限の日本語リクエストを逐次実行:
1. 短い日本語の論理/計算質問、**Thinking ON、reasoning_effort=low**、有界なcompletion token数（例4096）、HTTP200、非空最終回答とreasoning、finish_reason=stopを確認。
2. **日本語の短い創作文**（目安500～800字）を依頼し、温度を指定したサンプリング（例 temperature=0.8、top_p=0.95）、Thinking ON、必要なら xhigh と十分なcompletion budget（例8192）で確認。回答の分量、文の自然さ、一貫性、反復/EOS不具合、wall timeを記録。長引けば有界に停止し、途中打ち切りをPASSにしない。
3. 余裕があればOpenAI互換の1往復だけの**合成ツール呼出し**を確認。ツール実行自体や実リポジトリの操作をさせない。`response_format=json_schema`は公式0.1.4では未実装であることを記録し、無断で代替することなく、OpenCodeでの全機能成功と混同しない。

各リクエストのmodel/checkpoint、サンプリング/Thinking、生成・入力・reasoning tokens、prefillとdecodeのtok/s、TTFT（計測できる場合のみ）、wall time、finish_reason、cache、新規/再利用、DFlash2 draft/acceptを記録。性能値はFlashの実測と参考比較するが、異なるモデル・条件から優劣を断定しない。**Thinking OFF、別量子化、コンテキストの無断縮小で速度を作らない**。

### B3. Windows側の接続・停止・Flash復帰

Windowsから家庭内LANのDense test API `http://<EVO-X2のLANアドレス>:8732/v1`へ、認証なしHTTPで `/v1/models`等を少数確認してよい。**実際のIP・SSHユーザー・UUIDは公開Gitへ書かない**。OpenCode/Open WebUIの設定ファイルをCodexが勝手に変更しない。Denseが現在停止中のFlash APIとは別portかつ別model IDであることを確認する。

検証終了後、Denseがidleであることを確認し、`podman stop --time -1 halogen-dense`で正常停止。GTTが停止前の基準付近まで戻り、8732のlisten/コンテナが消えたことを確認する。

**最後に必ずFlash復帰を試みる:** `systemctl --user start halogen-active.service`（enable/Quadletは変更していない）を実行し、active/running、`/health`、`/v1/models`、APIポート8731へのLAN到達、Thinking ON簡易テスト（必要最小限）、GTT/メモリを確認。**Flash成功を最終報告の主要条件とする**。Denseロード失敗時も、未完了コンテナ・GTTが安全に解放できたならFlash復帰を優先する。GPU/ドライバ異常でGTTが残っていれば二重ロードを避けて停止し、勝手なforce kill/rebootをしない。

## 5. 許可範囲・禁止事項と停止条件

**今回許可:** Dense公式image pull（上記固定タグ）、約36GBのDense公式HGN＋tokenizer一式の初回取得、対象`/srv/llm`配下の新規ファイル、既存Flashのidle確認後のsystemd正常停止と復帰、Dense専用rootlessコンテナの起動/正常停止、必要最小限のLAN上HTTP疎通、指定Gitファイル2件のみのcommit/push。

**禁止:** 既存Flash版`deploy/`、Quadlet/drop-in、image、model、設定、port8731、systemd自動起動登録の変更。二つの大容量GPUモデルの並列起動、rootful/`--privileged`、reboot、kernel/firmware/UMA/BIOS・ROCmホスト・電力設定変更、apt upgrade、LAN外のAPI公開/ルーター・Firewall・SSH変更、Docker/GUIの追加、全体image/container prune、他repo/v3への書込・実購入、バックグラウンド自動再起動/独自watchdog、JIT/切替router実装。

**止める条件:** モデルや公式imageが不一致/入手不能、メモリ・領域不足、既存Flashがbusyで作業時間内にidleへ戻らない、Flash停止後のGPUメモリ未解放、Podman起動エラーが権限緩和を必要とする、ダウンロード予算超過、rootlessで制御不能、thinking未動作、Dense停止後のGTT未解放、Flash復帰ができない、作業用Gitに競合、指示範囲を超える変更が必要。失敗を隠すために別モデル/版へ切替しない。

**今回の完了判定:** Denseの指定モデル・image取得とハッシュ照合・起動/Thinking ON日本語API/正常停止に成功し、**Flashを既存の常駐状態へ復帰したこと**。未実施・WARN・部分成功は明示。今回の終点は**「Denseインストール済み・起動試験済み・停止中、Flash常駐中」**。この後、ユーザーと相談して再起動式モデル切替を別taskで実装する。

## 6. レポート・Git反映

正本レポート: `docs/investigation/2026-10/2026-10-15_halogen_dense_initial_deployment.md`

必須記載: instruction path/SHA、作業ホストと実施主体、Git開始/終了のHEAD/branch、競合確認、official source URLとtag/model revision、image digest/ID、実model/tokenizerのサイズ/ハッシュ、モデル精度/既定DFlash2/W4A4、実行したコマンドの環境区分、Flash停止とGTT基準/再始動、Denseのbootstrap/normalモデルROとダウンロードなし、API/Thinking ONのPASS/FAIL、品質・性能・TTFTの測定条件、未測定/未実施、現在のrunning/stopped/port/Linger、自動起動設定未変更、追加/削除した実機ファイルの一覧と安全な切戻し手順。

公開GitにはIP/ユーザー名/UID/秘密鍵/モデル本体/大量ログ/思考本文/認証情報を載せず、技術的要約のみ保存。`git diff --check`、対象2ファイルの明示的stage、差分・競合・秘密情報確認、`origin/main`へcommit/push、自commitの包含とcleanを確認。レポートURLとcommit SHA、Flash最終復帰、Dense測定、残課題を最終報告する。
