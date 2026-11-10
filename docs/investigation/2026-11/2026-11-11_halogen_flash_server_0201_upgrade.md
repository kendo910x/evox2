# Halogen Flash Server 0.20.1 更新・実機受入

2026-11-11 JST、EVO-X2 の標準Flashを0.18.4から0.20.1へ更新した。選択は `flash` のまま、`halogen-active.service` がLANの8731で推論を提供している。旧版18件、新版22件のAPI試験が合格した。DenseとUncensoredは候補設定まで検証した。実機で起動したモデルは標準Flashだけである。

## 1. 作業の起点

- Windows開発PCのCodexが指定のSSH別名 `evox2` でUbuntuの既存rootlessユーザーに接続した。開始時のGitは `main`、HEAD `7389dffeaa8b0d6b3453dc2e53777980c690c31a`、clean。fetch後の差分は指示書1ファイルのみで、`origin/main` の改訂コミットへfast-forwardした。[実行した指示書 e09666f0](../../instructions/2026-11/2026-11-08_halogen_flash_server_0191_upgrade_instruction.md)
- 実機調査開始は07:28 JST。Ubuntu 26.04.1 LTS / x86_64 / kernel `7.0.0-42-generic`、Podman 5.7.0、systemd 259.5、`/srv/llm` はext4。rootless storageは `/srv/llm/containers/podman`、取得前空き578,997,354,496 B。Linger=yes、memlockのsoft/hardはunlimited。
- `llm-select --show`、実効Quadlet・drop-in、systemd、コンテナ実体、`/health` と `/v1/models` がすべて標準Flashを示した。開始時はactive/running、Result=success、NRestarts=0。8731のみlisten。selector、手動起動script、全候補6ファイル、active対について、所有者・mode・SHA-256を照合した。旧selectorの全preflightも合格した。
- 配置と停止契約の出典は、[3モデルと固定r2](../2026-10/2026-10-17_halogen_flash_uncensored_third_model.md)、[セレクターの停止・解放・復元試験](../2026-10/2026-10-15_halogen_interactive_model_selector.md)、[rootless Quadletと自動起動](../2026-10/2026-10-15_halogen_systemd_boot_service.md)。

## 2. 配布物とモデル互換性

イメージ名の接頭辞は `ghcr.io/peonist-ai/`。表のdigestはmanifest、IDはコンテナイメージのconfigのSHA-256。RepoDigestはそれぞれのリポジトリ名に `@` と表のdigestを付けた値である。

| タグ | 実image ID | manifest digest |
|---|---|---|
| `halogen-flash-server:0.18.4` | `556c3c8179d8a566cc0ec0a7f7f54f9f3cb8b77e7bc4a4175e7c23ae359ad80a` | `sha256:1a458cd6decdd3a2c27f96196cc3a0bc853cbb3905320c3461d29137072faa78` |
| `halogen-flash-server:0.20.1` | `b0973fd66e5aa886b54cfaf2e4ad976b8d56ad2a2640221beec8dc920ade6e37` | `sha256:66dac8dac25bf15f2b63a684bbe3953036045172d881525600ea41d45e5acc73` |
| `halogen:0.1.4` | `7f87d073e63491e65fcdce6fb52c2faf2ded22229638f4ed2438096b11cb66c6` | `sha256:dc0a39a0016d6cfc58a197978febaafdf8d28403f724ded6111d98b5fb7ac0ea` |

- WindowsからGHCRのタグが返すOCI manifestの生バイトをSHA-256で照合した。指定digestと一致し、単一のlinux/amd64 manifestのconfig digestが上記の新IDだった。圧縮layer計942,259,529 B。実機で専用tmpを使って0.20.1だけを `podman pull` し、`podman image inspect` のID・Digest・RepoDigests・platformを再照合した。展開後のimage sizeは3,725,784,755 B。旧FlashとDenseも実機に保持した。[公式パッケージ](https://github.com/peonist-ai/halogen-flash-server/pkgs/container/halogen-flash-server/versions)
- OCIラベルはversion `0.20.1`、build revision `9f38fe7ba960`。公開リリース資料は `d2f4286f`。起動したコンテナ内の `rocm`、`rocm-sdk-core`、`rocm-sdk-libraries`、`rocm-sdk-device-gfx1151` の各パッケージは10.1.0だった。エンジンのEULA v0.1 第4節はベンチマーク公表を許諾している。モデル重みには個別のライセンスが適用される。[公式リリース](https://github.com/peonist-ai/halogen-flash-server/commit/d2f4286fc97fd1f75cd765714dbc50524004356f)・[EULA](https://github.com/peonist-ai/halogen-flash-server/blob/d2f4286fc97fd1f75cd765714dbc50524004356f/LICENSE.md)
- 公式v2 HGN 66,687,678,432 B、既存ngram 51,200,246,144 B、同一tokenizerを読み取り専用で使用した。固定Uncensored r2は88,737,777,792 B、専用HGN・公式companionのRO mount、model ID、起動時サイズ検査を維持した。モデルの取得・書換えは0件。公式のv2フォーマット、checkpoint指定、ROCm/GEMM/router変更とcache仕様を確認した。[公式更新履歴](https://github.com/peonist-ai/halogen-flash-server/blob/d2f4286fc97fd1f75cd765714dbc50524004356f/CHANGELOG.md)・[公式FLAGS](https://github.com/peonist-ai/halogen-flash-server/blob/d2f4286fc97fd1f75cd765714dbc50524004356f/docs/FLAGS.md)

## 3. 配備物と隔離検証

Gitの実装は、標準FlashとUncensoredの `halogen-active.container`、`deploy/halogen-flash/run.sh`、`deploy/model-selector/llm-select.sh` の4ファイル。Flash系タグ、r2の起動前image ID、セレクターのimage ID・候補hash・health期待版を更新した。手動runは同じローカルimage IDを検査し、既存モデルコンテナまたは8731/8732/8733のlistenを検出すると起動前に終了する。手動runの公開先は従来のloopbackである。[実装コミット cc22ab6](https://github.com/kendo910x/evox2/commit/cc22ab679b9962ae792d0e3a958a18a9db4dd043)

| 実機配置 | 最終SHA-256 | mode |
|---|---|---|
| Flash Quadlet、active Quadlet | `6e710807f64056d9d3fdbe128dc71279dda8ae039ed9e00f3c42f5ea60519ed4` | 0644 |
| Dense Quadlet | `52a90d1a9ed70c95c84f42fd8edefa3cd293ef874ef7d048ed7d9166b67b9466` | 0644 |
| Uncensored Quadlet | `7ec48f18e5de5fcba03f0e6b6f0e7f0e5fbef00295c420ea1b47fbd16806e607` | 0644 |
| Flash stop、active stop | `790f8cc28a2c035c32a9436745bd946f00dc2ea9c088d5c5851cbface958605e` | 0644 |
| Dense stop | `6586664d17de8b7a888002fcd382012974219c1eb2a1d4517436e22fbfaf35f2` | 0644 |
| Uncensored stop | `c28e8a2b5b7063a2a7862822ad6e673ab0f6200cc90692df13fafea23a23b313` | 0644 |
| `/srv/llm/engines/model-selector/llm-select.sh` | `1b90b6a0d9774d5dc6a9014fb0c4aa2d94087c70ab38cba20c443b33b7ce3763` | 0755 |
| `/srv/llm/engines/halogen-flash/run.sh` | `e1b0591f7ed17f0617429b69104c83e4d4fdcbf33515303d83ecaaf4b7b1c8ea` | 0755 |

候補の配置先は `/srv/llm/engines/model-selector/templates/{flash,dense,uncensored}/`。activeは `~/.config/containers/systemd/halogen-active.container` と `~/.config/systemd/user/halogen-active.service.d/90-safe-stop.conf`。変更した実機ファイルはFlash系候補2個、同じモデルのactive Quadlet、selector、手動run。元の所有者・modeを照合し、3つのstop drop-inとDense候補を比較した。`/usr/local/bin/llm-select` は元のsymlinkである。

| 検証 | 結果 |
|---|---|
| Bash構文、Git差分 | selector・runの `bash -n`、`git diff --check`、Git blobと配置バイト列・LF・modeの照合に合格 |
| 3候補の生成設定 | 各候補に実Podman generator `--user --dryrun` と隔離先への生成を実行。専用drop-inを合成した `systemd-analyze --user verify` の実効コマンドにより、image、port、RO mount、checkpoint、GPU、非強制stop/post、default.targetリンクを3/3で確認 |
| selectorの隔離fixture | 停止前38/38、最終版44/44。各モデルのshow・非TTY・Cancel・Esc・同一選択・Noが計18件、6方向のYes遷移が6件、異常・復元が14件。最終版では各候補の稼働GTT許容域の上下1 B超過を拒否する6件も追加 |
| 異常・復元の内訳 | source hash、image ID、busy、health版、余分なport、stop・post失敗、終了イベント欠落、GTT未解放、container・port残留、生成unit不良、reboot要求失敗、Uncensoredの143を検査。後者は拒否、Denseの143は他の正常停止条件成立時に受理。unit不良と模擬reboot失敗では旧対復元と旧モデルの模擬起動1回を確認 |
| 手動runの隔離fixture | 7/7。image ID不一致、既存コンテナ4種、使用中portを拒否。空の状態でのみ `--pull=never` とloopbackを含む模擬起動引数を通した。初回はfixtureの環境変数がUbuntuの `ID` と衝突したため修正し、全件再実行した |

fixtureのUIは擬似TTYで操作し、systemctl・Podmanの起動停止・rebootは模擬した。実機のOS再起動回数は0回。OpenCode/OpenWebUIの設定、OS・ドライバ、Denseの実装、NPU・Agent Guard・fork関連の設定は変更していない。

## 4. 実際の停止・起動

1. 旧版で第5節の18件を完了した後、`/health` はidle、APIの確立済み接続は0。作業用テスト終了から停止直前までcache hits/missesは148/37のままだった。WindowsとUbuntuで対象クライアントプロセスと実機の処理状況を確認した。
2. 既存selectorディレクトリのinodeを `flock` し、旧selector・run・3候補の設定対・active対・旧image識別子を退避。退避11ファイルを `sha256sum --check --strict` で照合した。
3. 07:41:43.930 JST に `systemctl --user stop halogen-active.service`、07:41:46.100に停止完了。実効 `podman stop --ignore --time=-1 halogen-flash` と所有ラベル・完全一致名を限定した非強制stop-postは、どちらも実行済み、exited/0。systemd inactive/success、ExecMainCode=1、ExecMainStatus=0。旧コンテナ `3e074bcac523…` の `died` イベントも0だった。
4. 停止直前のGTTは29,096,030,208 B。停止後18,661,376 Bに戻り、busyは最初の1%から10秒の観測枠内で0%へ推移した。全container不在、3 portすべて閉鎖、GTT/busyの再照合後に配置を開始した。
5. 配置先と同じfilesystemの一時ファイルでSHA・所有者・modeを確認してatomic renameし、`systemctl --user daemon-reload`。同じ標準Flashのinactive状態で、全候補のimage・テンプレートと実効unit、`systemd-analyze --user --generators=true verify`、空runtimeを検査した。`llm-select --show` 自身も同じinodeをロックするため、配置が整合している時点でのみ一度解錠して実行し、再取得後に起動前検査を繰り返した。
6. 07:41:49.412に同じunitを1回start、07:41:49.778にsystemdがactive、07:41:58.855にAPI listenのログ、07:41:59.169にwarm startのログを確認した。新コンテナ `0e8feffdc340…` の実imageは0.20.1のIDと一致。今回のサービス操作は通常stop 1回、start 1回。検証後のselectorのGTT中心値更新ではPIDとコンテナIDが同一だった。

## 5. APIの機能・品質・速度

WindowsからLAN 8731へ直接送信した。モデルID `halogen-qwen3.8-flash-next`、v2 HGN、template SHA-256 `c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041`、MTP、context 262144、4 slots、KV pool 524288、prompt cache mode 2は新旧同一。各リクエストはtemperature 0、Thinking ON、effort low、max_tokens 2048。seed・top_p・top_kは未指定。強制strict toolではAPI仕様によりthinking出力は0。サーバの既定設定は変更していない。

日本語の算術・時刻、Python関数の演算子修正、strict toolの名前・ID・型付き引数、合成日本語とPythonを混ぜた長文の前方・中央・後方3箇所の値と合計を機械採点した。Pythonは構文木を確認したうえで、通常・ゼロ・負値の3入力を検証した。全テキスト応答で非空のreasoningと最終回答、`finish_reason=stop`、不正な終端・偽のuser turnの不在を確認した。tool呼出しは `finish_reason=tool_calls` と有効なJSONを確認した。特殊終了経路を示す `reasoning_closed_by` は観測されなかった。実機で評価した長文は日本語の2入力であり、独語PPLや全長262kでの評価は実施していない。[上流の独語長文調査 #251](https://github.com/peonist-ai/halogen-flash-server/issues/251)

### 固定課題の初回・再送

各値は旧0.18.4 → 新0.20.1。入力はchat template込み、出力の括弧内はreasoning tokens。pp/tgはAPI timingsのprompt processing/生成 tok/s、wallとTTFTはWindowsで測った秒。TTFTは最初の非空reasoningまたはcontentまで。初回は実測 `cache_n=0`、再送は入力全量cache hit。稼働中サーバのcacheは人為的にflushしていない。完全hit時は新規prefillが0なのでppを記載しない。固定課題のmessagesは新旧でSHA-256が一致した。長文8k・32kの識別値は順に `591009c900235dbd`、`9211e7ef106fda8a`（キー順を揃えたUTF-8 JSONのSHA-256先頭16桁）。

| 課題・条件 | 入力 | 出力（reasoning） | pp tok/s | tg tok/s | TTFT秒 | wall秒 |
|---|---:|---|---|---|---|---|
| 日本語・算術 初回 | 71 | 89(85) → 91(87) | 333.8 → 361.1 | 65.9 → 78.6 | 非stream | 1.572 → 1.384 |
| 同 再送 | 71 | 89(85) → 91(87) | — | 66.6 → 79.5 | 非stream | 1.344 → 1.162 |
| 日本語・時刻 初回 | 78 | 81(74) → 124(117) | 406.0 → 405.6 | 75.4 → 90.9 | 0.208 → 0.214 | 1.282 → 1.580 |
| 同 再送 | 78 | 81(74) → 124(117) | — | 76.2 → 91.6 | 0.005 → 0.010 | 1.068 → 1.365 |
| Python 初回 | 85 | 135(116) → 92(73) | 414.4 → 416.3 | 79.3 → 77.8 | 非stream | 1.914 → 1.394 |
| 同 再送 | 85 | 135(116) → 92(73) | — | 80.2 → 78.8 | 非stream | 1.691 → 1.194 |
| strict tool 初回 | 330 | 31(0) → 31(0) | 854.9 → 910.1 | 71.0 → 94.3 | 非stream | 0.839 → 0.716 |
| 同 再送 | 330 | 31(0) → 31(0) | — | 71.5 → 94.7 | 非stream | 0.440 → 0.339 |
| 長文8k 初回 | 8,190 | 147(133) → 147(133) | 1,924.9 → 2,140.9 | 75.1 → 94.8 | 4.273 → 3.854 | 6.232 → 5.405 |
| 同 再送 | 8,190 | 147(133) → 147(133) | — | 75.7 → 95.2 | 0.024 → 0.017 | 1.967 → 1.563 |
| 長文32k 初回 | 32,776 | 144(130) → 144(130) | 1,911.2 → 2,087.1 | 67.7 → 87.3 | 17.220 → 15.791 | 19.347 → 17.441 |
| 同 再送 | 32,776 | 144(130) → 144(130) | — | 68.1 → 87.9 | 0.016 → 0.027 | 2.131 → 1.666 |

この12件は両版とも正答。32k初回はcache・生成量・reasoning量が揃い、wallは1.906秒短かった。一方、時刻問題は両回ともwallが23～28%延びた。正答と最終回答のtoken数は同じで、reasoningが74から117 tokensへ増え、tg自体は上がった。Pythonは生成量が減った影響が大きい。比較条件が揃う長文や直列toolで一貫した20%以上の速度低下は観測せず、切戻しを要する品質後退も認めなかった。個々の実測値は上表の入力・試行回数に限定される。

### Thinking ONの履歴と応答末尾cache

独立した2会話で3ターンずつ、同じ種類の数値問題をstreamで実行した。`preserve_thinking=true`。完全履歴では受信したassistantのcontent・reasoningを原形で返し、対照ではcontentだけを返した。入力・キャッシュ量はテンプレート適用後のtokens。6件とも両版で正答した。

| 履歴・ターン | 入力 | cache_n 旧 → 新 | 出力（reasoning）旧 → 新 | TTFT秒 旧 → 新 | wall秒 旧 → 新 | pp/tg tok/s 旧 → 新 |
|---|---:|---|---|---|---|---|
| 完全 1 | 65 | 0 → 0 | 74(70) → 74(70) | 0.188 → 0.182 | 1.337 → 1.158 | 353.6/64.4 → 371.0/75.9 |
| 完全 2 | 170 | 65 → 139 | 51(47) → 51(47) | 0.215 → 0.122 | 0.923 → 0.771 | 507.7/72.0 → 278.8/78.5 |
| 完全 3 | 251 | 170 → 221 | 39(35) → 39(35) | 0.198 → 0.122 | 0.696 → 0.539 | 422.5/78.4 → 268.8/93.7 |
| reasoning省略 1 | 65 | 0 → 0 | 77(73) → 77(73) | 0.180 → 0.194 | 1.307 → 1.155 | 371.2/68.4 → 370.6/80.2 |
| reasoning省略 2 | 101 | 0 → 0 | 43(39) → 43(39) | 0.216 → 0.216 | 0.866 → 0.741 | 482.6/66.2 → 484.6/81.9 |
| reasoning省略 3 | 136 | 64 → 64 | 56(52) → 58(54) | 0.168 → 0.176 | 0.950 → 0.947 | 450.6/71.6 → 444.7/75.2 |

完全履歴の2・3ターン目で、新版の再利用量139と221は、直前ターンの入力＋生成量と一致した。対照では再利用量が旧版と同じだった。運用クライアントがreasoningを実際に返すかは今回の直接API試験の対象外。

### 新版だけの追加4件

- 同じstrict schemaで2リクエストを同期させ、最大2並列の1組だけを実施。両方とも入力330、cache_n=256、生成31 tokens。wallは1.232秒と1.315秒。正しいtool名、call ID、文字列・整数の引数、終端を確認し、`busy=false`、`in_flight=queued=0`、pool busy_regions=0へ復帰した。旧版ではstrict toolを直列でのみ実行した。
- SSEのstrict tool 1件では、引数7断片を組み立て、単一のcall ID、有効JSON、`tool_calls`、`[DONE]` まで確認した。最初のtool deltaは0.282秒、wall 0.577秒。副作用のない模擬tool結果を同じIDで返した後続1件も、指定値に正答し `stop` で完了した（入力156、生成40、wall 0.794秒）。最終のstrict requestカウンタ5、unenforced 0。
- 新版は共通18件＋並列2件＋SSE/後続2件の計22/22。旧版は共通18/18。検証用の全文prompt、思考本文、回答本文、LAN接続先、資格情報は掲載していない。

## 6. RAM・GTT・ログ

RAMはホストの `/proc/meminfo`、GTT/busyは同一GPUのsysfs、cache占有量は `/cache` から取得した。GiBは2の30乗B。旧版は数日稼働後、新版は同じbootでの計画起動直後から測定した。

| 観測点 | MemAvailable | ホスト使用RAM（free -b） | GTT B | busy | cache占有B / 使用entry |
|---|---:|---:|---:|---:|---|
| 旧・試験前 | 87.96 GiB | 35,707,920,384 B | 29,085,544,448 | 0% | 2,793,351,648 / 24 |
| 旧・共通18件後 | 88.00 GiB | 35,669,090,304 B | 29,096,030,208 | 0% | 2,793,351,648 / 24 |
| 新・起動直後のidle | 89.22 GiB | 34,355,286,016 B | 29,658,824,704 | 0% | 232,779,304 / 2 |
| 新・共通18件と並列2件後 | 86.64 GiB | 37,124,149,248 B | 29,669,548,032 | 0% | 2,909,741,300 / 25 |
| 新・追加SSE/後続後 | — | — | 29,669,548,032 | 0% | 3,142,520,604 / 27 |

- 起動ログのprompt cache RAM見積りは2.7 → 3.1 GiB、`/cache` の `max_entries` は24 → 28。両版とも `/health` の `prompt_cache.cap_mb` は110で、`/cache` の `last_entry_bytes` は116,389,652 B。新版の主試験でhit/miss差分は11/9、evictedは0 → 8、refused=0。追加SSE/後続後はevicted=9、refused=0、room_clamped=0。実際にreply-end entryの追い出しログがあった。ホストRAM全体にはファイルキャッシュや稼働履歴の差も含まれる。
- エンジン起動ログのweightは62.1 GiB、KV poolは14.4 GiBで同じ。working memoryの表示は12.5 → 12.8 GiB。swap使用は0 Bのままでpswpin/pswpoutとも0。新コンテナはOOMKilled=false。対象時間のkernel journalにOOM、GPU fault・reset・ring timeoutは0件。主試験のサービスログで通常の `cannot grow` と実打切りを示す `was shortened by the room` はともに0件。ログ出力先の違いを発生させる負荷試験は行っていない。
- セレクターは当初、旧Flash系中心29,085,544,448 B、幅±536,870,912 Bのままで投入した。新版Flashの起動後idleで1秒間隔4回すべて29,658,824,704 B、主試験後も4回すべて29,669,548,032 B。すべてbusy=0。旧上限29,622,415,360 Bをそれぞれ34.7 MiB、44.9 MiB上回った。GPUのGTTはsysfsの実測であり、上記のホスト側cache予算から換算していない。
- 標準Flashだけ中心を試験後実測29,669,548,032 Bへ変更し、幅±512 MiBと停止時の解放条件を維持した。最終候補で全preflightに合格してから、同じinodeのロック下でselectorのみatomic renameし、配置後も全preflightに合格した。07:46:13 JSTに実行中PID・コンテナIDの継続を確認。Denseの中心は21,176,967,168 B、未起動のUncensoredは29,085,544,448 B。r2が新版Flashと同程度に増えた場合は、そのモデルの稼働中preflightが旧上限で停止し得る。次回の実起動でr2自身のGTTを確認する必要がある。

## 7. 切戻しと最終状態

旧版の退避先は実機の `/srv/llm/engines/model-selector/backup-0201-20261110T224141Z-KPzZ78H7/`（所有ユーザーのみアクセス可）。`SHA256SUMS` は旧selector・run・3候補のQuadlet/stop・active対・`images.txt` の11件をカバーし、更新後も11/11一致した。旧selectorのSHA-256は `91755562bf7882c6c4dcb8f1960ea2f74319d006a8b5ae5692d77b4eb180ac75`、旧手動runは `5cb53066f338a15cb9c621d0b330998e1ed8da9dcd830d67e07971a9df15d0a9`。旧イメージ・重みとこの退避を保持している。

今回の切戻し回数は0回。以下は標準Flash稼働中に今回の配備を戻す場合の手順である。

1. `llm-select --show` で標準Flashを確認し、既存selectorディレクトリのinodeを `flock` する。退避側で `sha256sum --check --strict SHA256SUMS`、`images.txt` と実image ID/digestを照合する。クライアント終了、idle、実効stop/post、対象コンテナID、port、GTTを確認する。
2. 停止開始時刻とコンテナIDを記録して、`systemctl --user stop halogen-active.service` を1回だけ実行する。`Result=success`、両stopコマンド実行済み・exit 0、対象IDのdied=0、ExecMainCode=1/Status=0、全container・3 port消失、GPU busy=0と停止時GTT範囲をすべて確認する。ここで条件を満たせなければ設定復元と起動を中止する。
3. 同じロック下で旧 `llm-select.sh`・`run.sh` を0755、`templates/` 配下の3候補・`active.container` と `90-safe-stop.conf` を0644で元のパスに揃える。同一ハッシュのファイルは照合で足りる。差し替えるものは個々の配置先に隣接した一時ファイルへ展開し、所有者・mode・SHA-256確認後にrenameする。selectorディレクトリ本体は保持する。
4. `systemctl --user daemon-reload`、旧Flashの生成unit・stop/post・default.target・image・テンプレートとactive対を再確認する。整合した状態で `llm-select --show` を確認し、再度排他して停止状態とGPU解放を確認後、`systemctl --user start halogen-active.service` を1回実行する。`/health` のapi/engine 0.18.4、`/v1/models`、8731のみのlisten、実コンテナの旧image ID、GTT、全preflight、Windowsからの応答を確認する。

07:51:40 JSTの最終実機確認で標準Flashのみactive/running、Result=success、Restart=no、NRestarts=0、Linger=yes。LAN 8731の `/health` は0.20.1/0.20.1、busy=false、in_flight=queued=0、MTP・4 slots。Dense 8732、Uncensored 8733は閉鎖。自動起動はgenerated unitと `default.target.wants` のリンクで確認した。今回の実機ではOS再起動後の自動起動、Dense・Uncensoredへの切替、固定r2の0.20.1上での推論・停止を未検証とする。

実機の隔離fixture・転送・作業用スクリプト計9.2 MiBを専用一時ディレクトリから削除し、上記の退避11件を再照合した。再比較に使った合成入力、採点用クライアント、本文を含まない旧・新の計測JSONLは、Windows開発PCの作業用 `%TEMP%/halogen-0201-1794349714121/` に置いている。

## 8. Git反映

4つの実装ファイルだけを明示stageし、LF・実行属性・ステージ済みblobのSHA-256が実機最終版と一致した。実装コミットをpush後、`git ls-remote` で `origin/main` が `cc22ab679b9962ae792d0e3a958a18a9db4dd043` になったことを確認した。本レポートは別コミットとし、レポートのSHA・最終のremote包含と作業ツリー状態は納品時のチャットに記載する。
