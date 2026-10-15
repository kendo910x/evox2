# EVO-X2 初期環境調査・ChatGPT→Codexワークフロー疎通確認 指示書

作成日: 2026-10-15

## 1. 対象・受渡し情報

| 項目 | 指定 |
|---|---|
| repository | `kendo910x/evox2` |
| canonical branch | `main`（正本 `origin/main`） |
| 指示書作成基準commit | `ede6b5563c4a85b07c4fa951b534cb0feb613dcc` |
| Codex開始基準commit | **本指示書を含むChatGPTのcommit**。SHAはChatGPTからの受渡しメッセージを参照する |
| instruction publisher | ChatGPT |
| primary executor | **Windows開発PC上のCodex**（EVO-X2はSSH経由で読み取り専用調査） |
| controller | Windows開発PC上のCodex |
| 対象実機 | EVO-X2のUbuntu Server。Windows側SSH設定の接続別名 `evox2` |
| 補助環境 | Windows開発PC（Git作業・レポート作成のみ） |
| Git管理する変更範囲 | `docs/investigation/2026-10/2026-10-15_initial_environment_survey.md` **新規1ファイルのみ** |
| 調査に伴うEVO-X2上のファイル変更 | **禁止**（ログインに伴うOSの通常ログ等を除く） |
| 並行task | 不明。開始時にGitの既存変更を調べ、対象ファイル競合があれば停止 |
| 対象モデル／推論サーバ | 今回は起動・ダウンロード・検証しない |
| 性能目標・benchmark | not applicable（本タスクは初期状態確認） |

本書はユーザーが依頼した初回の小規模なタスクであり、環境構築ではない。**ChatGPTによる指示書commit → Codexによる読込 → SSH経由の実機調査 → レポートcommit/push → ChatGPTによるレビュー**までの受渡しが機能することを確認する。

## 2. 目的と完了判断

次の二点だけを判断する。

1. Windows開発PCから `ssh evox2` でEVO-X2のUbuntuへ接続し、非破壊のシステム情報取得が可能か。
2. Codexが本指示書を `origin/main` から受領し、調査レポート1ファイルを作成して `origin/main` へpushし、後からChatGPTがレビューできる状態にできるか。

副次的に、将来Gufo・Halogen・llama.cppを導入する前提として、OS・カーネル・GPUデバイス・メモリ・ディスク・SSH・コンテナ関連コマンドの現状を短く整理する。

**成功条件:** (a) SSH経由でread-only情報を取得、(b) 採取できない項目を未確認と明示、(c) 実施レポートをcommit/push、(d) commitがorigin/mainに含まれることを確認。未導入のツールや未作成のディレクトリは障害ではない。EVO-X2に変更を加えないことも成功条件。

## 3. 最初に読むファイルとGit開始確認

最初に `AGENTS.md` を読む。その後にこの指示書を読む。別リポジトリの契約やv3の実装は今回の入力としない。

- Windows開発PC上にevox2のcloneがあればそれを利用する。なければ既存workspaceと競合しない**新しいディレクトリ**に `kendo910x/evox2` をcloneしてよい。v3や他プロジェクトのcheckoutは利用・変更しない。
- clone先の絶対パスはCodexが実機で確認する。名称・ユーザー名・ドライブを決め打ちしない。
- `git remote`、現在branch、HEAD、`git status --short`、`origin/main`を確認する。既存の変更を破棄・stash・resetしない。
- `git fetch origin main` 後、ChatGPTが受渡しで示す指示書commitが `origin/main` のancestorであることを検証する。最新指示書を実際に読んでから調査を始める。
- 既存cloneがbehindなら、対象外の変更がないことを確認したうえで安全にfast-forwardする。並行作業と競合したら停止・報告する。
- GitHub認証が必要でも、秘密情報をコードやレポートに記載しない。新しい資格情報や認証方式を勝手に設定しない。既存の認証でpushできない場合は失敗として報告する。

Git関連操作（clone、fetch、commit、push）のネットワークアクセスと、Windows開発PC上で本レポートを作成することだけを許可する。EVO-X2上にGit cloneを作る必要はない。

## 4. 実機調査：SSH経由・読み取り専用

作業を始める前に、Windows開発PCのPowerShellで以下を確認する。

```powershell
# [Windows開発PC]
ssh evox2 "printf 'ssh-ok\n'; uname -s"
```

期待値は `ssh-ok` と `Linux`。接続先が意図したUbuntuホストであることを確認し、異なるホスト・意図しない権限なら停止する。IPアドレスや秘密鍵、認証情報をレポートに記載しない。

必要な情報は、Windows側から `ssh evox2 "<read-only command>"` で取得するか、`ssh evox2` でログインして以下を確認する。**後者の場合、以下のLinuxコマンドはEVO-X2上で実行する。**

### 4.1 OS・CPU・メモリ・GPU

```bash
# [EVO-X2 Ubuntu / read-only]
cat /etc/os-release
uname -r
uname -m
lscpu
free -h
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
```

```bash
# [EVO-X2 Ubuntu / read-only]
command -v lspci && lspci -nnk | grep -A 4 -Ei 'VGA|Display|3D'
ls -ld /dev/kfd /dev/dri /dev/dri/renderD* 2>&1
lsmod | grep -E '(^amdgpu |^amdkfd )' || true
test -r /sys/module/amdgpu/parameters/gttsize && cat /sys/module/amdgpu/parameters/gttsize
```

- `lspci` が未導入なら「未導入」と記載し、インストールしない。
- `/dev/kfd` とDRM render nodeの有無、amdgpuのロード状態、メモリ総量などを記録する。
- BIOSのUMAやGTT全体の設定を**確認できたことにしない**。Linuxの観測値と推測を分離する。
- `rocminfo`、`amd-smi`、`rocm-smi` が既に存在すれば、GPU識別に必要な範囲でread-onlyコマンドを使用してよい。存在しなければ追加導入しない。
- `CONFIG_HSA_AMD_SVM` 等はカーネルconfigが既存の読み取り可能な場所にあれば確認してよい。確認不能なら「未確認」でよい。

### 4.2 ストレージと起動領域

```bash
# [EVO-X2 Ubuntu / read-only]
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
findmnt -no SOURCE,FSTYPE,TARGET /
findmnt -no SOURCE,FSTYPE,TARGET /boot/efi
df -h /
```

- Linuxのルート領域とESPが**どのSSD系列に属するか**を確認できる範囲で整理する。
- Windows SSDをmount・操作・検査しない。既にmountされている場合はその事実だけを記録し、変更しない。
- シリアル番号、UUID、暗号化回復キー、ユーザー固有のマウントパスはレポートへ転載しない。
- EFIの独立性が確認できない場合は「未確認」で止める。UEFI/GRUB/BootOrderは変更しない。

### 4.3 SSH・サービス・導入済みツール

```bash
# [EVO-X2 Ubuntu / read-only]
systemctl is-active ssh
systemctl is-enabled ssh
systemctl get-default
for x in docker podman git python3 rocminfo amd-smi rocm-smi llama-server; do
  if command -v "$x" >/dev/null 2>&1; then
    echo "$x: present"
  else
    echo "$x: absent"
  fi
done
```

- systemdで推論関連のサービスが既に動いている場合は、名称と稼働有無だけを記録する。全サービス・環境変数・設定ファイルのダンプは不要。
- SSH接続成功、サービスの起動・自動起動、画面環境の有無などを要約する。
- NIC、LAN IP、MAC、公開鍵、SSH config内容、`env`、`printenv`、秘密情報を含むログをレポートに転記しない。
- UbuntuのGUIなしという想定は観測できる範囲で確認し、GUIを追加・削除しない。

### 4.4 調査の打切り

取得が権限不足・コマンド未導入で失敗しても、**sudoやapt導入でむやみに掘り下げない**。未確認・制限理由を記録する。データ収集は判断に必要な短時間のコマンドだけとし、全ファイル探索、全ログ採取、ストレス試験は行わない。

## 5. 実行を禁止する変更

EVO-X2に対して、以下の操作は禁止する。

- `apt update`、`apt upgrade`、`apt install`、ROCm/driver/カーネル導入、GUI導入、推論モデルのダウンロード。
- Docker/Podmanコンテナの起動・build/pull、サービスstart/stop/restart、systemctl enable/disable、cron設定。
- `/etc`、`/srv`、`~/.ssh` 等の設定変更、ユーザー追加、SSH鍵設定変更。
- BIOS/UEFI、EFI/GRUB、SSD/partition、GTT/UMA、電力制限の変更。
- shutdown/reboot、ポート開放、Firewall変更、外部APIアクセスや外部公開、性能benchmark。
- `v3` リポジトリまたは別ホストの操作。
- 調査のためのEVO-X2上のファイル生成・コピー・rawログ保存。

Git管理するレポートの作成・commit/pushはWindows開発PC上だけで行う。接続先の通常アクセスログ等のOS自動記録は「実機変更をした」とはみなさないが、意図的な設定変更はしない。

## 6. 成果物と書き方

**作成するtrackedファイルは1つだけ:**

```text
docs/investigation/2026-10/2026-10-15_initial_environment_survey.md
```

以下の構成で、要約中心の日本語レポートにする。

1. 目的、作業日、参照した指示書path・commit、実行主体、Git開始時HEAD・状態。
2. **ワークフロー疎通結果**: AGENTS読込、指示書commit包含確認、SSH疎通・read-onlyコマンド実行、レポート作成、Git commit/pushの各結果（PASS/FAIL/未実施）。
3. **環境サマリー表**: Ubuntu版、カーネル、CPU/GPU認識、RAM/swap、KFD/render node、GTT確認状況、Linux root/ESP、SSH状態、Docker/Podman/ROCmツールの有無。
4. 次工程に関係する未確認事項・技術的リスク（最大5点）。推奨は調査で裏付けられた範囲に限定する。
5. 実施操作・副作用: `EVO-X2の設定変更なし` を実際の事実に基づいて報告。例外があれば明記する。
6. Git変更ファイル、commit SHA、push結果、`origin/main` 包含確認、残課題。

本リポジトリは公開設定のため、**LANアドレス、ログインユーザー名、端末固有ID、鍵、トークン、個人情報、秘密を含み得る生ログをcommitしない**。コマンド出力の丸ごと貼り付けではなく要約する。レポート中のhostname・Windows側ローカルパスも不要。タスク確認にはSSH接続別名 `evox2` と対象リポジトリ名を使う。

## 7. レポート保存・commit/push・完了確認

- `git diff --check`、`git status --short`、対象レポートの内容を確認する。
- 自タスクの新規レポートだけを明示的にstageする（無条件の `git add -A` 禁止）。
- commit例: `docs: record initial evox2 environment survey`。
- `origin/main` を更新確認し、競合しない変更だけを安全に統合してpushする。force push、reset、他タスクの変更破棄は禁止。
- 自commitがpush後の `origin/main` に含まれることを確認する。レポート本文に自己のcommit SHAを事前埋込する必要はない（自己参照を避ける）。最終チャット報告で実際のcommit SHAを提示する。
- **レポートはcommit/pushする前に内容を完成させる。** 最終確認だけはCodexのチャット報告でcommit SHA、push結果、origin/main包含結果を伝える。レポートの該当欄は「最終チャットで報告」と明記してよい。
- ChatGPTがGitHub上のレポートを読み、内容レビューできることが最終的なワークフロー確認となる。

Google Drive upload、tgz、スクリーンショット、巨大rawログ、EVO-X2側の成果物、ベンチマークは不要。

## 8. 停止・未完了の扱い

対象ホスト相違、SSH認証失敗、指示書の未取得・commit不一致、実際のGit競合、未承認の操作が必要な場合は該当部分を停止し、原因と次の選択肢を報告する。取得可能なread-only情報だけをレポートに残してよいが、未完了をPASSとしない。

**このタスク終了後にGufo・Halogen・llama.cpp・ROCmを自動導入しない。** 次の設計と作業指示は、調査結果をChatGPTとユーザーがレビューしてから決める。
