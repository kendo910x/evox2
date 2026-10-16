# Halogen Flash-Next Uncensored r2 第3モデル追加 実施レポート

実施日: 2026-10-17（JST）

**状態: PASS / 標準Flashへ復帰済み。** 固定r2の取得・全量hash、3択selector、Uncensoredのログイン前自動起動・Thinking ON・cache・正常停止とGTT解放を確認した。承認された2回の再起動で往復し、終了時は標準Flashのみactive/running、LAN8731でAPI応答。Dense/Uncensoredは停止、8732/8733は閉鎖。品質評価は以下の小規模サンプルに限定する。

## 1. 指示・開始状態

- 指示書: `docs/instructions/2026-10/2026-10-17_halogen_flash_uncensored_third_model_instruction.md`、commit `b270a3e2a26cd9e4b09aebdb5a4dd135eb840829`。
- Windows開発PC上のCodexがGit操作、`ssh evox2`経由でUbuntuの既存rootless Podmanユーザーとして実機操作。実アカウント・UID・LANアドレス・UUID・認証情報は本書に記載しない。
- `AGENTS.md`を先に読み、指定指示書、Flash初回導入第9節、常駐化第9～12節、Dense停止143、selector第11～13節、既存実装を確認。
- 開始branch=`main`、HEAD=`8a7585b1be82d4694c7d3484408c4f02c11f7620`、clean。他タスク変更なし。fetch後に指定commitの包含を確認し、origin/mainへfast-forward。作業基準HEADは上記指示書commit。
- Ubuntu 26.04.1 LTS、kernel `7.0.0-38-generic`、Podman 5.7.0 rootless/cgroup v2、systemd 259.5。Linux用`/srv/llm` ext4はrw mount済み。開始時空き667,787,259,904 bytes。UMA・OS・GPU・ディスクを変更していない。
- 07:34 JSTの開始確認でFlashのみactive/running、Result=success、NRestarts=0、health idle、Linger=yes、SSH/managerのmemlock unlimited。GPUアクセス、Ubuntu起動先、既存selectorの全preflightがPASS。GTT=29,085,544,448 bytes、busy=0%。
- 開始時selector SHA-256=`5e90a54121ac4c543a964948314a1dc2067281d07271e4c28fd1414cd4b8a0f3`。既存Flash/Denseテンプレート、active対のhashはGit正本と一致。

## 2. 固定する配布物・ライセンス

| 項目 | 採用値 |
|---|---|
| HF repository | `Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated` |
| revision | `e7783c5822dfda2785a0f5b435abf54df89fe8ee` |
| filename | `qwen38-flash-next-v2-abliterated.hgn` |
| 指示書・固定rev metadataのbytes | 88,737,777,792 |
| 指示書・固定rev LFS SHA-256 | `7bbac319851b500639462133085156b4f998dec562f511e65ca1c14d7af5163e` |
| 保存先 | `/srv/llm/models/halogen-flash-uncensored/r2/` |
| image | `ghcr.io/peonist-ai/halogen-flash-server:0.18.4`、既存imageを再利用 |
| image ID | `556c3c8179d8a566cc0ec0a7f7f54f9f3cb8b77e7bc4a4175e7c23ae359ad80a` |
| digest | `sha256:1a458cd6decdd3a2c27f96196cc3a0bc853cbb3905320c3461d29137072faa78` |

[固定r2モデルカード](https://huggingface.co/Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated/blob/e7783c5822dfda2785a0f5b435abf54df89fe8ee/README.md)は公式v2と同伴ngram/tokenizerでの検証を記載する。著者の旧engine 0.15.0によるWikiText-2等の限定評価であり、本機0.18.4・日本語・長文の品質保証ではない。r2は元payloadを未参照のまま残すためファイルが大きく、参照weightsは約62.1 GiBとされる。本機の実測と混同しない。

[現行mainの説明](https://huggingface.co/Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated/blob/main/README.md)にある66,687,678,432 bytes、SHA `b5bd925fa2b44343be4a2cd328cae6b57ce7ffa2fe2cc56281717377e5a1ce8a`のネイティブ変換版は、旧公式companionとの提供者によるserving検証が未了のため今回選択していない。r1、HT43、Swift、GGUFも取得対象外。

取得前に以下の原文を確認した。

- [固定r2 LICENSE](https://huggingface.co/Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated/blob/e7783c5822dfda2785a0f5b435abf54df89fe8ee/LICENSE)はApache-2.0。
- donor=`orcarouter/Qwen3.8-Flash-Next-Uncensored`、revision `8336e613ea508b13c2159bd0f68965d97a606b95`の実LICENSEはQwen Community License 1.0。donorのraw取得はgatedのためHTTP 401だったが、公開[LICENSE-QWEN](https://huggingface.co/Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated/blob/main/LICENSE-QWEN)を読み、3,235 bytesのGit blob SHA-1 `9557a8961782792814714b7488346732c043793d`がdonor固定revのAPI metadataと一致した。単にモデルカードのライセンス名を信用したものではない。
- Qwen原文にはnotice保持、大規模商用サービスの表示、特定の商用MaaS/AI Work Assistant事業の別許諾条件がある。今回の自宅内利用・モデル非再配布の範囲に抵触する条件は確認されなかった。Apache表記だけを根拠に無条件の商用再配布が可能とは扱わない。
- [Halogen EULA](https://github.com/peonist-ai/halogen-flash-server/blob/main/LICENSE.md) v0.1（2026-08-25）はエンジンとweightsの条件を分離し、実行・benchmark公開を許諾している。imageのmetadata revisionをGitHub raw URLへ指定した取得は404だったため、公式公開原文を確認した。今回image更新・再配布はない。

認証情報の取得やgated donor weightsの取得は実施していない。コミュニティtooling/converterは取得・実行していない。

## 3. 公式補助ファイルの現物照合

**PASS。既存ファイルを再取得・複製せずRO共有できる内容一致を確認。** 固定r2指定のngram revision `5cc17cea1a10b502b4a5db41d8d2b1a0f22dba26`、tokenizer revision `e053f488b120b99ed2525e6ac99f68c51b3b6179`のHF metadataと照合した。

既存ファイルは初回導入時に公式revision `cf41ff9fc97b6dd9887d82e21269522de6208055`から取得されたもの。今回全量SHA-256/sizeを一度再計算し、LFSはSHA-256、通常GitファイルはsizeとGit blob SHA-1を配布metadataと比較した。後者も実SHA-256を以下に記録した。所要79.97秒。

| `/srv/llm/models/halogen-flash/`以下 | bytes | 実SHA-256 |
|---|---:|---|
| qwen38-flash-next-ngram.hgn | 51,200,246,144 | `3450acada94e19aabad88bd49b45eb70304820949c2240fc178067b20ae5dffe` |
| tokenizer/chat_template.jinja | 8,952 | `c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041` |
| tokenizer/generation_config.json | 202 | `e70c136c1b78ddc1fb0905bac8e733a4dc448d4f852a5dd75143fffc70be550e` |
| tokenizer/merges.txt | 3,353,259 | `a9d356d7bdf1ef4949e3e748e95b8e10ad9d4e2e838eddc38a0a7b6b94d1db8d` |
| tokenizer/tokenizer.json | 12,809,320 | `0997f410c57a1f4e53b09e4be8f4a172d90edd9564368fb0847030937229b9f3` |
| tokenizer/tokenizer_config.json | 17,928 | `b11349aafa7cdc6a320767cf7ceb29ed82f7eda5d65e8e0819e76f0ce947bf27` |
| tokenizer/vocab.json | 6,722,759 | `ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003` |

## 4. 専用ダウンロード環境・取得

既存`hf`がなかったため、許可された専用venvを`/srv/llm/engines/halogen-flash-uncensored/download-venv`に作成。通常の`python3 -m venv`はensurepip不在で失敗した。ホストapt/global pipを変更せず、同じ専用venvを`--without-pip`で作成し、PyPI公式metadataのSHA-256と照合したpip wheelを使ってvenvへ導入した。

主な導入版はpip 26.2.1、huggingface_hub 2.2.0、hf-xet 1.7.0。依存はanyio 4.15.1、click 8.5.0、filelock 4.2.0、fsspec 2026.9.0、h11 0.16.0、httpcore2/httpx2 2.13.1、idna 3.20、packaging 26.3、PyYAML 6.0.3、tqdm 4.70.1、truststore 0.10.5、typing_extensions 4.16.0。すべて専用venv内であり、エンジンimageとは独立する。

HF_HOME、HF_XET_CACHE、TMPDIRを今回専用`/srv/llm/engines/halogen-flash-uncensored/`内へ指定。pip cacheなし、Xet chunk cache上限0、Hub telemetryと暗黙token利用を無効化。`hf download --dry-run`が指定1ファイル88.7GBのみを示すことを確認した。

**[Windows→Ubuntu/SSH]** 07:39:35 JST開始:

```sh
hf download Quat3rnion/halogen-qwen3.8-flash-next-v2-abliterated \
  qwen38-flash-next-v2-abliterated.hgn \
  --revision e7783c5822dfda2785a0f5b435abf54df89fe8ee \
  --local-dir /srv/llm/models/halogen-flash-uncensored/r2
```

08:03:30 JSTに取得完了、所要1,435秒（23分55秒）。CLIの実取得は1回、終了コード0。完成ファイルは88,737,777,792 bytes。**08:05:16 JST、実SHA-256が`7bbac319851b500639462133085156b4f998dec562f511e65ca1c14d7af5163e`で指示書・固定rev metadataの双方と一致してPASS**。全量hash計算104.83秒。通常ファイルでsymlinkではなく、`.incomplete`残骸は0件。

固定r2のApache LICENSEとdonorと同一内容のLICENSE-QWENをモデルの隣へ保存し、noticeを保持した。これらのテキストとモデル本体は公開Gitへ含めない。取得後のモデル領域は88,737,837,056 allocated bytes、今回専用engine/venv/cache/tmp全体は58,077,184 bytesで、追加100 GiB以内。

モデル側`.cache`は24,576 bytes、専用HF/Xet cacheは3,342,336 bytes、venvは48,697,344 bytes、tmp（fixture・pip wheel等）は6,033,408 bytes。取得後の`/srv/llm`空きは578,991,345,664 bytes。Xetログのlevel集計はINFOのみでWARN/ERRORなし。取得中にホストOOM/GPU fault/resetを示すkernelログは認めなかった。

## 5. 実装と隔離検証

変更対象は指示書指定の4ファイルのみ。新規Uncensored Quadlet/停止drop-in、selector拡張、本レポート。既存Flash/Dense Quadlet・停止drop-in・run.sh・model・imageは不変。

新規定義は既存Flash image ID、専用checkpointのRO mount、公式companionのRO共有、model ID `halogen-qwen3.8-flash-next-uncensored`、LAN `0.0.0.0:8733:8731`。HALOGEN_DOWNLOAD/MTP_HEAD/VISION_TOWERを指定しない。context 262144、4 slots、KV pool 524288、prompt cache mode 2、MTP/Thinkingは既存image既定を維持する。

起動前に固定r2のsize/可読性、補助ファイル、GPUアクセス、rootless・memlock、image ID、全container不在、8731/8732/8733空きを検査する。毎起動で巨大HGNをhashしない。停止は無期限の非強制stopとlabel＋完全一致名による非強制rm、Restart=no、TimeoutStopSec=infinity、KillMode=mixed、SendSIGKILL=no。Denseの143許容をUncensoredへ移さない。

selectorはcontainer/model ID/companion pathを明示mappingへ変更し、3候補のhash・実効unit・health・mount・port・GTTを照合する。停止イベント/GTTの最大10秒観測、Result・ExecStop/ExecStopPost・終了コード・空runtimeの全条件、Yes後だけjournal記録、対の配備とrollbackを維持。Uncensoredの実測GTTは起動後29,054,521,344、推論後29,085,544,448 bytesで、既存Flashと同じ中心29,085,544,448±536,870,912 bytesの範囲に入った。この実測を根拠に同じ狭い範囲を採用し、許容幅を広げていない。

**隔離試験はPASS。実機モデル起動のPASSではない。** 作業用fixtureは専用tmp下に置き、実serviceのstop/start/reload/rebootをmock化した。

| 試験 | 結果 |
|---|---|
| 3モデルの6方向切替・対の一致 | PASS。停止→配備→模擬reboot。Denseのみ143 |
| 各初期選択のCancel/Esc/No/same、Yes前HUP | PASS。設定・サービス操作・journal変更なし |
| 前提失敗、Uncensored143、Result/stop/post失敗、イベント欠落/重複、GTT残留、container/8733残留 | PASS。配備・rebootを拒否 |
| 新unit不一致 | PASS。旧対へ復元し旧モデル起動を1回だけ模擬実行 |
| 上記UI/切替/停止系 | 30ケースPASS |
| 3モデルのruntime、別port・複数container・image/ID/context/GTT逸脱、専用mount/env/KV/cache/drafter不一致 | 43ケースPASS |
| 実Podman 5.7 generator・systemd-analyze verify | 3候補すべてPASS。隔離出力先、default.targetリンク、image/port/mount/env、専用stop/143範囲を確認 |
| Bash構文、実非TTY拒否、read-only `--show` | PASS |
| 実SSH TTYの3択表示、Uncensored選択後の初期No、No、Cancel、同一Flash選択 | PASS。稼働設定への書込みなし |
| 新Quadletの9個のExecStartPre相当の読み取り検査 | PASS。未取得の完成HGN、稼働中Flash container、使用中8731をそれぞれ拒否。残りの環境条件は成立 |

最初のfixtureは転送ファイルのmode 0664を厳格検査で拒否した。試験対象を所定0644へ整えて再実行した。さらにYes後の前提失敗でもjournalが空だとするfixture自身の誤期待を修正した。これらを実サービス障害とは扱わず、最終の上記成功結果と区別する。

07:47 JSTの確認で標準FlashのMainPID、active Quadlet/stop hash、配置済み旧selector hashは開始時と一致。active/running、Result=success、NRestarts=0、health idle。候補scriptによる実Flash unit照合もPASS。download・試験でモデル停止やdaemon-reloadを行っていない。

08:06:04 JST、配置前後の全preflightがPASSし、既存selectorディレクトリのflockを保持して専用templatesを追加、scriptを同一filesystem上のrenameで更新した。active対・稼働PIDは維持し、この配置時にdaemon-reloadやservice操作はない。新scriptは0755、templatesは0644。旧scriptは今回専用tmpへ一時退避した。

| 配置対象 | SHA-256 |
|---|---|
| selector | `91755562bf7882c6c4dcb8f1960ea2f74319d006a8b5ae5692d77b4eb180ac75` |
| Uncensored Quadlet | `6d77e2191301343ccb0b417c662e370f7c91dc9cb1152ef9b5a678261a02288a` |
| Uncensored停止drop-in | `c28e8a2b5b7063a2a7862822ad6e673ab0f6200cc90692df13fafea23a23b313` |

配置前の読み取りpreflightの1回は非0を返した。そこで操作を進めずtrace付きで再確認し全条件成立を確認した。最初の失敗条件は採取できず確定していない。正式配置の前後と実切替時に別々の全条件検査を行い、条件を省略・緩和していない。

## 6. 実機受入

指示書の「ユーザーがTTY画面でYes」条件に対し、配置・検証完了後にユーザーから**2回のYes操作のCodexによる代行を明示承認**され、クライアント停止済みとの回答を得た。SSH TTYの実whiptail画面でUncensoredを選択し、初期NoをYesへ操作した。

08:06:56 JSTにFlashの正常停止を開始。Result=success、inactive、ExecMainCode=1/Status=0、対象containerイベントexit=0。GTTは29,085,544,448から18,661,376 bytesへ戻った。最初のGPU busy=1%は通過させず、既存10秒観測内でbusy=0%を確認してから継続した。stop/post成功、全container/3port消失、対の配備、生成unit、再起動直前の空runtimeを確認後、08:06:59 JSTに**1回目のrebootを要求**した。

### 6.1 Uncensoredの起動・API・メモリ

**08:08:15 JST、再起動後のSSH接続より前にWindowsからLAN8733へ直接GETし、health/modelsが専用IDを返した。** API/engine=0.18.4、context=262144、slots=4、KV pool=524288、prompt cache mode=2、MTP、chat template thinking_control=true/probe passed、vision=false。手動start/run.shは実行していない。

bootからのservice開始6.128秒、active 6.606秒、model ready 56.038秒、API listen 60.059秒。最初のSSH sessionは96.929秒（08:08:46 JST）で、APIはそれより約36.870秒早く起動した。

88.7GB HGNと51.2GB ngramをmapし、r2の参照payload **62.11 GiBを149 rangeに分けて43.0秒でpin**した。エンジンの実メモリ内訳はweights 62.1 GiB + KV 14.4 GiB + work 12.5 GiB = 89.0 GiB。ファイル全体88.7GBを同量の常駐weightsと誤認しない。ngram 47.7 GiBは必要時にfile cacheから読む。

container PID 1と実flash_serveのmemlockはsoft/hard unlimited。Uncensored containerのみactive、Result=success、NRestarts=0、Restart=no、SuccessExitStatusは空。候補ID・実効unit・RO mount・model env・全port・GTT・healthを含む配置済みselectorの全preflightがPASSした。kernelの限定OOM/GPU fault/reset検索は該当なし。

### 6.2 Thinking ONとfollow-up/cache

WindowsからLANへ直接POST。全件`enable_thinking=true`、`reasoning_effort=low`、`temperature=0`、`max_completion_tokens=4096`、`stream=false`。top_p/top_k/seed未指定。model/量子化/context/MTPは変更しない。サーバの既定effort=xhighを変更したのではなく、今回の各要求にlowを指定した。

| Uncensoredの短い要求 | input / completion（reasoning）tokens | pp / tg tok/s | prompt / generation ms | Windows wall秒 | 結果 |
|---|---:|---:|---:|---:|---|
| りんご17個を5人へ配る計算 | 74 / 78（62） | 168.297 / **64.489** | 439.7 / 1209.5 | 1.704 | HTTP200、stop、正答 |
| 余りに3個追加し同じ5人へ配るfollow-up | 197 / 101（76） | 541.612 / **67.208** | 227.1 / 1502.8 | 1.746 | HTTP200、stop、正答、cache再利用 |
| 架空の無人駅の不穏な独白、約100字 | 91 / 634（577） | 342.492 / **64.027** | 265.7 / 9902.1 | 10.202 | HTTP200、stop、日本語創作が完結 |

全件に非空reasoning_content（196/240/1628文字）と最終回答があった。モデル本文・思考本文はGitへ保存しない。follow-upには前応答のassistant content/reasoning_contentを含めた会話履歴を渡した。実処理prompt_n=123、cached_tokens/cache_n=74、prefix_n=152。`/cache`はhits 0→1、misses 0→1、prompt_tokens_saved 0→74、entries 0→3。ディスクcacheはoffで、既存mode2のメモリ上cacheが動作した。

MTP draft/acceptedは計算68/48、follow-up92/65、創作583/388。tgはThinking込みの生成全体のserver値、wallは要求開始から全応答受信まで。非streamのためTTFT未測定。follow-upのppは残りの123トークンに対する値で、cold prompt全体との単純比較はしない。長文品質、native最大contextの実入力、持続速度の検証ではない。

### 6.3 Uncensored停止・Flash復帰

推論完了・idleを確認し、実TTYの初期ラジオがUncensoredであることを確認後、Flashを選んでYesを操作した。08:09:56 JSTに正常停止を開始し、08:09:57 JSTに**Result=success、inactive、ExecMainCode=1/Status=0、対象container exit=0**を確認した。ExecStop/ExecStopPost実行結果、全container/3port消失を照合し、GTT=29,085,544,448→18,661,376 bytes。こちらも最初のbusy=1%を拒否して0%まで観測し、既存の安全条件を全部満たしてからFlashの既存正本対へ復元した。

Flash実効ExecStart/Stop/Post・default.target・空runtimeを確認し、08:09:58 JSTに**2回目のrebootを要求**。再起動は合計2回で終了した。

**08:13:32 JST、再起動後のSSHログインより前にWindowsからLAN8731のhealth/models応答を確認。** 標準model ID、API/engine 0.18.4、context 262144、slots 4、KV pool 524288、MTP、prompt cache mode 2、Thinking対応を維持。boot後のservice開始6.129秒、active 6.601秒、model ready 54.768秒、API listen 57.880秒、最初のSSH session 215.673秒で、ログイン前起動をjournalでも確認した。最初のLAN監視55秒窓ではready未観測だったが、次の監視で応答し、間にSSHログインや手動startは行っていない。観測時刻をAPI起動所要時間と取り違えない。

標準HGNは66.7GB map、62.11 GiBを1 range、41.9秒でpin。復帰後の全preflightはPASS。08:14:19 JSTにも同じMainPIDでactive/running、Result=success、NRestarts=0、Restart=no、GTT=29,085,544,448 bytes、busy=0%。SSHを切断・再接続しても稼働を継続した。containerは標準Flashのみ、8731のみlisten、Dense/Uncensoredのcontainerと8732/8733 listenerはない。

実manager、container PID 1、flash_serveのmemlockはunlimited。親user managerの設定表示は従来どおりLimitMEMLOCK=8388608、停止期限5秒・KillMode=mixed・SendSIGKILL=yes、vendor drop-inのみで、実プロセスの無制限値とは区別した。Halogen serviceはLimitMEMLOCK=infinity、TimeoutStopSec=infinity、SendSIGKILL=no、SuccessExitStatus空。親managerやmemlock設定は変更していない。両bootのkernel限定検索でOOM/GPU fault/resetの該当なし。

既存Flash active対とFlash/Dense template hashの不変を再照合した。

| 既存ファイル | 最終SHA-256 |
|---|---|
| Flash Quadlet（activeも一致） | `cb6c6357066d68a0a7a8a035c8b61de8950ffa8847665b4bae23689c8ec03446` |
| Flash停止drop-in（activeも一致） | `790f8cc28a2c035c32a9436745bd946f00dc2ea9c088d5c5851cbface958605e` |
| Dense Quadlet | `52a90d1a9ed70c95c84f42fd8edefa3cd293ef874ef7d048ed7d9166b67b9466` |
| Dense停止drop-in | `6586664d17de8b7a888002fcd382012974219c1eb2a1d4517436e22fbfaf35f2` |

### 6.4 標準Flashとの小規模比較・判定範囲

復帰後に同じ計算・創作prompt、同じ要求パラメータを使った。双方とも日本語で完結し、反復ループや拒否は認めなかった。創作はどちらも無人駅・廃止列車という設定に沿う短い不穏な独白で、出力本文や思考本文は保存しない。

| 標準Flashの短い要求 | input / completion（reasoning）tokens | pp / tg tok/s | prompt / generation ms | Windows wall秒 | 結果 |
|---|---:|---:|---:|---:|---|
| 同じりんごの計算 | 74 / 76（60） | 167.648 / **67.616** | 441.4 / 1124.0 | 1.647 | HTTP200、stop、正答、Thinking ON |
| 同じ無人駅の創作 | 91 / 1318（1253） | 345.613 / **72.809** | 263.3 / 18102.1 | 18.401 | HTTP200、stop、日本語創作が完結、Thinking ON |

標準Flashの非空reasoning_contentは190/2696文字。MTP draft/acceptedは67/49、1133/893。Uncensored創作のwallが短かったのは、この1サンプルでThinkingを含む生成量が634対1318 tokensと少なかった影響が大きい。tg自体は64.027対72.809 tok/sであり、Uncensoredの速度・品質向上を一般化しない。拒否低減の再現率、長文理解・真実性・長文創作、最大262144 contextの実入力、長時間安定性、streaming TTFTは**未実施**。Denseの実起動・再起動を今回は繰り返しておらず、3モデル間の6方向回帰は隔離fixtureでの確認。

| 受入項目 | 判定 |
|---|---|
| 指定r2の取得・実hash、公式companionの内容一致 | PASS |
| 3択UI・No/Cancel無変更・停止安全条件の維持 | PASS |
| Uncensored選択のboot維持・ログイン前自動起動・LAN8733 | PASS |
| Uncensored Thinking ON・日本語短問・follow-up/cache | PASS |
| 両モデルの通常停止・全runtime消失・GTT基準値復帰 | PASS |
| 標準Flashへ復帰・ログイン前起動・LAN8731/Thinking ON | PASS |
| Dense/Uncensored停止、既存設定不変、SSH切断後の稼働 | PASS |
| 長文品質・拒否低減率・最大context負荷・耐久試験 | 未実施（今回の受入範囲外） |

通常切替に関する未解決の阻害要因はない。第5節の単発preflight非0の原因は未確定。既存の制約として、idle判定と新規HTTP到着の競合を完全には排除できないため切替前にクライアントを停止すること、突然のOS shutdownでは親managerの5秒期限が残ること、Restart=noで異常時の自動復旧を行わないことを維持する。

### 6.5 作業用ファイルの整理

実機の新規永続配置は第4節のモデル・license・専用venv/cacheと、`/srv/llm/engines/model-selector/templates/uncensored/`の2ファイル。既存selector scriptだけを更新した。active対は往復後に既存Flashと完全一致する。追加の独立service、監視、選択状態ファイルは作っていない。

専用tmp配下の`acceptance/`（fixture・隔離generator出力）、旧selectorの一時backup、pip bootstrap wheelは、実pathが専用ディレクトリ内でsymlinkでないことを確認して削除した。Windowsの一時検証script3件もGit管理外の`.git/`から削除した。モデル本体・既存モデル・image・実機journalは削除していない。

整理後のallocated bytesはモデル領域88,737,832,960（うち`.cache`24,576）、専用engine領域52,047,872、venv48,697,344、HF/Xet cache3,342,336、空tmp4,096。`/srv/llm`空き578,997,354,496 bytes。`.incomplete`残骸なし。追加容量は約82.69 GiBで許可された100 GiB未満。

## 7. 利用・切戻し・Git

受入完了後のクライアント接続先は`http://<EVO-X2 LAN address>:8733/v1`、モデルIDは`halogen-qwen3.8-flash-next-uncensored`。`llm-select`で選択し再起動したモデルだけが利用可能。標準Flashは8731、Denseは8732。OpenCode/Open WebUI設定を変更していない。HTTP・認証追加なしの自宅LAN用途であり、ルーター/NAT/Firewall/WAN公開を操作しない。

切戻しはidle確認→systemd正常停止→Result・stop/post・container/port消失・GTT解放を確認した後、既存Flash正本のQuadlet/停止drop-inを対で戻して実効unitを照合する。停止失敗時に強制kill/rebootやGPU重ね起動を行わない。モデル・imageは削除しない。

Windowsで最終差分・秘密情報・LF（CR/BOMなし）・実行権・`git diff --check`を確認済み。実装3ファイルのhashは実機配置と一致する。再fetch時点でorigin/mainは指示書commitのままで競合なし。以下4pathだけを明示stageして、本レポートと実装を同一commitに含めorigin/mainへpushする。自己commit SHA、push結果、origin/mainへの自commit包含と最終cleanは最終チャットで報告する。

- `deploy/halogen-flash-uncensored/halogen-active.container`
- `deploy/halogen-flash-uncensored/halogen-active.service.d/90-safe-stop.conf`
- `deploy/model-selector/llm-select.sh`（実行権100755維持）
- `docs/investigation/2026-10/2026-10-17_halogen_flash_uncensored_third_model.md`
