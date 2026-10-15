# Halogen Flash-Next 初回導入・API疎通確認 指示書

作成日: 2026-10-15

## 1. 基本情報・対象

| 項目 | 指定 |
|---|---|
| Repository | `kendo910x/evox2` |
| 正本branch | `origin/main` |
| 指示書作成基準commit | `3dacbf5f4e1626e64b7f981165109cdd9857e0bd` |
| Codex開始基準commit | **本指示書を含むChatGPTのcommit**（SHAは受渡しチャットで通知） |
| instruction publisher | ChatGPT |
| primary executor / controller | **Windows開発PC上のCodex** |
| 実機操作 | Windows開発PCから `ssh evox2` でEVO-X2 Ubuntuへ接続 |
| 初期調査 | `docs/investigation/2026-10/2026-10-15_initial_environment_survey.md` |
| 対象エンジン | `peonist-ai/halogen-flash-server`、初回は公式コンテナ `ghcr.io/peonist-ai/halogen-flash-server:0.18.4` |
| 対象モデル | 公式 `peonist-ai/halogen-qwen3.8-flash-next`、標準v2チェックポイント |
| tracked write scope | `deploy/halogen-flash/run.sh`（新規、起動用）および `docs/investigation/2026-10/2026-10-15_halogen_flash_initial_deployment.md`（新規・中間報告があれば更新） |
| 並行task | 不明。開始時に確認。対象pathが競合すれば停止 |
| 対象外 | Halogen 27B Dense、Gufo、llama.cpp、NPU、Open WebUI、OpenCode、速度最適化、本格品質比較 |
| 許可されたGit作業 | 必要なfetch、対象限定のcommit、origin/mainへのpush |
| Google Drive / tgz | 不要 |

## 2. 目的・完了条件

**主目標:** EVO-X2上でHalogenのFlash-Next版を起動し、**Thinking ONの日本語リクエスト**をOpenAI互換 `/v1/chat/completions` へ送って、正常な応答を得る。

必要な準備として、既存OS/SSHを維持したまま、GPUアクセス権限、コンテナ環境、Linux用SSD内のモデル保存領域を整える。構築と疎通を行い、設定・イメージ・チェックポイントの再現可能性と削除方法を記録する。

**初回導入成功の判断:** ホスト前提を確認、モデルのロード、`/health` と `/v1/models` が正常、Thinking ONで日本語応答、短時間の再リクエストが正常、使用エンジン・モデル・設定・副作用が記録されていること。測定したtok/sは参考値とし、このtaskではWindows比1.5倍等の性能達成を成功条件にしない。

**重要な人手介在点:** 現在のLinux観測ではCPU側RAM約30.5 GiB、GPU VRAM表示96 GiBであり、Halogen Flashの公式要件と相性が悪い。**BIOS UMA frame bufferを最小の明示値へ変更する操作はユーザー自身が行う。CodexはBIOSを変更しない。** EVO-X2では公式資料に最小2GBの報告があるが、実BIOS画面で値を確認する。Autoではなく明示値を使用。変更前の値を控えておくこと。これはLinuxだけでなくWindows起動時のGPUメモリ配分にも影響し得る。

BIOS変更がまだの場合、Codexは**許可された準備作業だけ進めた後、`WAITING_FOR_USER_UMA`として実施レポートをcommit/pushして終了**してよい。ユーザーがBIOSを変更した後、**同じ指示書から再開**する（新しい指示書は不要）。未起動なのに完了と報告しない。

## 3. 必須読込・開始時確認

最初に本リポジトリの `AGENTS.md`、次に本指示書、初回調査レポートを読む。現行Git状態を確認する。

- Windows側evox2 checkoutの実在とroot、branch、HEAD、remote、`git status --short` を確認。
- `git fetch origin main`し、本指示書commitが`origin/main`に含まれることを確認。既存変更を破棄、stash、resetしない。競合しない場合のみ安全に同期。
- SSH alias `evox2` の接続先が想定のUbuntuホストか確認する。実IP・SSHユーザー・端末識別情報は公開レポートへ載せない。
- sudo無人実行 `ssh evox2 "sudo -n true"` を確認。パスワード要求があれば作業を止め、sudoersを勝手に変更しない。
- コマンドを **[Windows開発PC]** と **[EVO-X2 Ubuntu/SSH]** で区別する。以下のLinux例はEVO-X2上で実行する。

**公式導入ドキュメントを固定情報源として確認する:**
- https://github.com/peonist-ai/halogen-flash-server/blob/main/README.md
- https://github.com/peonist-ai/halogen-flash-server/blob/main/AGENTS.md
- https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/getting-started.md
- https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md
- https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/FLAGS.md
- https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/api.md
- https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/sampling.md

今回のイメージタグは**0.18.4固定**。READMEが変わっていても無断で`latest`へ変えない。公式がこの版を撤去した、重大な非互換が判明した場合は、版を捏造して代替せず報告する。

## 4. Phase A: OS・ストレージ・GPUの確認と準備

### A1. read-only preflight

```bash
# [EVO-X2 Ubuntu] まずread-only
uname -r
free -h
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
sudo -n pvs -o pv_name,vg_name,pv_size,pv_free
sudo -n vgs -o vg_name,vg_size,vg_free
sudo -n lvs -o lv_name,vg_name,lv_size,lv_path
findmnt / /boot/efi /srv/llm
id
ls -l /dev/kfd /dev/dri/renderD*
grep '^CONFIG_HSA_AMD_SVM=' "/boot/config-$(uname -r)"
```

`findmnt`等の未存在パスは未作成なら正常。必要に応じて既存のGPU sysfsと `/proc/meminfo` からUMA/GTTの観測値を更新。read-only段階でWindows SSDを操作しない。

- 初回調査: root LVは100GiBで空き約82GiB。LinuxのPVはKIOXIA製SSD、別SSDはWindowsと推定。**PV/VGは実際に再照合**する。
- rootとEFIを変更しない。Windowsのパーティションは一切変更しない。
- KFD・render nodeの所有group/permissions、`render`会員資格を確認する。
- BIOS後のFlash起動の目安: Linux側`MemTotal`が約100GiB以上（128GiB機、UMA最小なら通常これ以上）を確認。96GiB固定予約のままの約30GiBではモデルの取得・ロードへ進まない。
- 公式が要求するgfx1151対応とカーネルSVMは実測情報で判断し、バージョン名だけで動作保証しない。

### A2. モデル用データ領域（今回明示的に許可する範囲）

原則 **`/srv/llm` をモデル・エンジン用の独立したext4 LV** とし、既存root LVを無条件に拡張しない。ユーザーの「きれいに整理し、削除しやすく」という目的に合わせ、Linux用SSD以外を触らない。

新規構築を認める条件をすべて満たす場合に限り、以下を許可する。

1. `ubuntu-vg` 等の実在VGのPVが**対象Linux用KIOXIA SSDのLinux LVMパーティションだけ**であると確認できる。
2. 既存`/srv/llm`が未使用・未マウントで、モデルなどの既存データがない。
3. VGに**400GiB以上の未割当free extents**があり、新規LV作成後も他LVに影響しない。
4. 対象デバイス・VG・空き容量・コマンドの影響を確認できる。

この場合、**新規LV `llm_data` を400GiBだけ作成し、当該新規LVだけをext4で初期化**、`/srv/llm`へマウントして`/etc/fstab`へUUID参照の1行を追加することを、この指示書で許可する。マウント後に`findmnt /srv/llm`、`df -h /srv/llm`、`lsblk`で確認。OSのroot、boot、既存LV、VGの既存データやWindows SSDには手を加えない。既存LVのフォーマット・削除・縮小・移動・パーティション変更は禁止する。

上記の一つでも満たさなければ**LVMを変更せず停止して設計案を報告**する。独断でroot拡張、別SSD利用、既存データ消去、ディスク全体の再初期化へ変更しない。

新規領域へ必要最小限の `/srv/llm/models/halogen-flash`、`/srv/llm/engines/halogen-flash` を作成し、実行ユーザーが利用できるowner/permissionを付与。runtimeデータはGitへ入れない。`/srv/llm`以外の永続的ファイル生成（Podman/aptが管理する領域を除く）は必要最小限にする。

### A3. GPU権限とコンテナ

- `/dev/kfd`、render nodeが`root:render 0660`であり、ログインユーザーが`render`に属さない場合に限り、**当該ユーザーをrender groupへ追加する操作を許可**。追加後、再ログインした別SSHセッションで`id`・デバイスアクセスを検証する。既存SSH/sudo設定は変更しない。
- 公式コンテナの使用に必要な**Ubuntu公式apt repositoryからのPodmanと通常依存パッケージのみ**導入を許可する。`sudo -n apt update`および`sudo -n apt install -y podman`は可。`apt upgrade`、OSリリース更新、追加ROCmホスト一式、Docker併設、GUI、Pythonのグローバルpip導入はしない。
- rootless Podmanを第一選択にする。HALOGEN公式の `--device /dev/kfd --device /dev/dri --group-add keep-groups --ipc=host --ulimit memlock=-1:-1` を参考にする。**`--privileged`やrootful Docker/Podmanへ黙って切り替えない**。必要な権限が足りなければ症状と最小限の対策案を報告する。
- 既存GPUサービスが動作している場合は勝手に止めない。ポート8731、GPU使用中状態、空きディスク容量を調べる。

このPhase Aで得るべき結果: 独立したモデル保存先、Podman動作、KFD/render使用可能、SSH継続、リスクのないGit管理ができること。BIOSが未変更ならここで`WAITING_FOR_USER_UMA`を報告して終了する。

## 5. Phase B: BIOS変更確認後の初回Halogen Flash起動

**開始gate:** UbuntuでUMA最小化が観測上確認でき、KFD/render利用可能、`/srv/llm`が想定Linux SSD上のマウントで、モデル領域に**160GiB以上の空き**、root側にコンテナ用の十分な空きがあること。満たさなければモデルダウンロードはしない。

BIOS設定変更の操作はユーザー側のみ。設定済みでもCodexは勝手に再起動しない。設定を変えて再起動後のホストと確認できたときのみこのPhaseへ進む。

### B1. コンテナとモデル取得

- 配布元は公式 `ghcr.io/peonist-ai/halogen-flash-server:0.18.4` のみ。イメージdigest、サイズ、pull結果を確認する。
- `HALOGEN_DOWNLOAD=peonist-ai/halogen-qwen3.8-flash-next` を指定した**初回の1回だけ**、モデル保存領域をread-writeで渡す。公式v2とtokenizer等、約111GiB級の取得を許可するが、**合計130GiBを明確に超える取得が必要になったら中止・報告**する。Hugging Faceへ認証が必要で既存権限にない場合は秘密情報を取得・保存せず停止する。
- 公式推奨タグを固定し、`HALOGEN_CHECKPOINT=/models/qwen38-flash-next-v2.hgn`を指定。勝手に小さな量子化、旧w4b、GGUF等へ置き換えない。
- 最初は**シングルコンテナ**で動かし、`-p 127.0.0.1:8731:8731` のみ公開。LAN全体、`0.0.0.0`、WANに無認証APIを公開しない。
- NPUや別モデルを同時起動しない。rootless、公式の必要デバイスとIPC/ulimitに絞り、追加のprivileged権限を与えない。
- コンテナのdownloadログと起動ログを確認。モデル未取得やメモリ不足を放置してループ再試行しない。

**起動コマンドの基本形（Codexが現物・公式と照合して調整）:**

```bash
# [EVO-X2 Ubuntu] Phase Bの条件を満たしてから1回だけ
podman run -d --rm --name halogen-flash-bootstrap \
  -p 127.0.0.1:8731:8731 \
  --device /dev/kfd --device /dev/dri --group-add keep-groups \
  --ipc=host --ulimit memlock=-1:-1 \
  -e HALOGEN_DOWNLOAD=peonist-ai/halogen-qwen3.8-flash-next \
  -e HALOGEN_CHECKPOINT=/models/qwen38-flash-next-v2.hgn \
  -v /srv/llm/models/halogen-flash:/models \
  ghcr.io/peonist-ai/halogen-flash-server:0.18.4
```

初回取得後は **`HALOGEN_DOWNLOAD` を外し、モデルをread-only mountする通常起動方式**に切り替える。GPUメモリが正常に返らない・コンテナ停止が固まる等の異常があれば、強制killや勝手なrebootをせず状況を記録して停止する。

### B2. 再現可能な通常起動スクリプト

Windows側evox2 repoへ `deploy/halogen-flash/run.sh` を作成。通常起動だけを担当する**短いshell script**とする。

条件:
- 指定image `0.18.4` 固定、モデルは `/srv/llm/models/halogen-flash` のv2、読み取り専用mount。
- `HALOGEN_DOWNLOAD` **なし**。起動する度に自動ダウンロードしない。
- `--name halogen-flash`、`--rm`、`-d`、`-p 127.0.0.1:8731:8731`。デバイス・group・IPC/ulimitは公式要件を反映。
- 既存の同名コンテナやポート占有を確認し、勝手に停止・置換しない。
- 余計なバージョン検出/自動更新/daemon/watchdog/swap/router/管理フレームワークを実装しない。
- スクリプトの実行環境をUbuntuに限定し、必要なファイルがあるか検査する。

Windows側で作成したtracked `run.sh` をEVO-X2の `/srv/llm/engines/halogen-flash/run.sh` へ1ファイルのみ転送してよい（ハッシュまたは内容一致を確認）。コピー経路・実行方法をレポートへ記載する。OS起動時の自動実行・systemd service化は**今回はしない**。

### B3. API疎通と最低限の品質確認

EVO-X2から `http://127.0.0.1:8731` を確認し、必要ならWindowsからSSHポート転送で到達する。SSHの鍵設定やLAN firewallは変更しない。

1. `GET /health` が正常で、API/engine版、ロード済みcheckpoint、ready状態、Thinking機能等が確認できる。
2. `GET /v1/models` で `halogen-qwen3.8-flash-next` を確認。
3. `POST /v1/chat/completions` へ短い**日本語**プロンプトを送り、HTTP成功、`finish_reason`、非空の最終回答、`usage`、`timings`を確認する。初回は `"enable_thinking":true`、`"reasoning_effort":"low"`、`"temperature":0`、`"max_completion_tokens":4096`を明示し、Thinking OFFでごまかさない。
4. 余裕があれば `reasoning_effort:"xhigh"` とQwen thinking推奨サンプリング `temperature:1.0, top_p:0.95, top_k:20` で短い追加テストを1回だけ行う。推論が長引けばboundedに停止し、未完了扱いで理由を記録する。
5. 長いコンテキスト、品質の徹底比較、並列負荷、耐久試験、速度のピーク追跡は本タスクで行わない。

`finish_reason:"length"`、空回答、部分Thinkingだけ、GPU障害、コンテナ再起動をPASSにしない。診断は公式`docs/troubleshooting.md`に従い、合理的な少数のread-only確認だけ行う。許可のないUMA変更、KV contextの大幅縮小、量子化変更、再起動での回復、電力設定変更へ進まない。

初回成功後は通常起動スクリプトでread-onlyマウント・download無効のコンテナが起動していることを確認し、**一時検証サーバとして稼働**させてよい（再起動後の自動復旧・常時運用を意味しない）。API公開はloopback限定のままとし、ユーザーがSSHトンネルから利用できることも示す。

## 6. 明示的な許可範囲・禁止事項

**今回許可:** Ubuntu側でのPodmanと必要最小限のapt導入、対象SSHユーザーのrender group追加、新規400GiB Linux用LVの作成・新規LVのみのext4初期化・`/srv/llm`へのfstab登録、指定モデルの130GiB以内の一度限りのダウンロード、指定コンテナの起動/正常停止、必要な一時ログ閲覧、run.sh転送と限定的なAPIテスト。

**今回禁止:** Windows SSDやそのEFI/NTFSへの書込、既存partition/LVのformat/縮小/移動、BIOS/UMA/UEFI変更、カーネル/ファームウェア更新、全面OS更新、SSH/sudoers/firewallの変更、電力設定変更、rootful/privilegedへの無断fallback、GUI追加、NPU/27B Denseの導入、リモートAPI公開、systemd永続service登録、モデルの未承認変更、長時間高負荷試験、他repoやv3への操作。既存SSHアクセスを失う操作はしない。

ダウンロード先は `/srv/llm` に限定し、rootやHOMEのHugging Face cacheへ巨大なモデルを二重に落とさない。PodmanイメージはPodman管理領域に作られることを許容する。必要な処理がこの範囲を超えたら停止・報告する。

## 7. 実施レポート・Git反映

標準レポート:
`docs/investigation/2026-10/2026-10-15_halogen_flash_initial_deployment.md`

必須記載:
- 指示書path/commit、作業日時・実行主体、Windows側repoの開始HEAD、Git開始時状態、検証対象ホストを特定した根拠（秘密・LAN情報は除く）。
- `Phase A` のpreflight結果、LVM VG/PV/LV確認と実施した変更、GPU権限、Podman状態、SSH保持。
- BIOSが必要なら **`WAITING_FOR_USER_UMA`** として、ユーザーがすべき操作、観測値、Windowsへも影響し得ることを簡潔に報告。実機作業の未完了をPASSにしない。
- `Phase B`に進めたら実際のモデルファイルのサイズと版、イメージdigest、container名、bind範囲、API URL（loopbackのみ）、Thinking設定、検証結果、推論timings、ログ要約。
- `/srv/llm`、Podman image、ローカルscript、`/etc/fstab`、group変更など**残った永続状態とアンインストール/切戻し手順**。削除コマンドを実行したのではなく手順として記録する。
- 実施しなかったこと、失敗・保留、想定との差、追加の承認が必要な作業。
- tracked変更file一覧、commit SHA、push結果、`origin/main`包含確認（自己commit SHAのレポート内自己参照は不要。最終チャットで報告可）。

リポジトリはpublic。**SSH秘密鍵、sudoers内容、LAN IP、実ユーザー名、端末固有ID、JWT/APIキー、巨大ログ/モデル/キャッシュ/コンテナ内容をcommitしない。** レポートは要約のみ。十分な情報があれば巨大なログ収集は行わない。

作業前後に `git status`、`git diff --check`、意図した差分を確認し、上記2ファイルのみを明示的にstageしてcommit/push。別taskの変更を混ぜない。実際の競合があれば停止。commitが`origin/main`のancestorであることを確認して最終報告する。

**Phase Aで人手待ちになった場合も、その時点の事実をレポートとしてcommit/pushする。** BIOS変更後に同じ指示書で再開した際は、既存レポートに追補し、既実施の安全な手順は再実行しない。最後にChatGPTがレポートと変更差分をレビューするまで、恒久稼働への昇格や27B Dense導入はしない。
