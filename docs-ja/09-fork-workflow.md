# 09. フォークの運用 — ブランチ構成と PR

日本語コメントを持ちながら、英語で PR を出すための運用方法です。

## 結論

ブランチを分けます。

| ブランチ | 中身 | 用途 |
|---|---|---|
| `main` | 修正の本体。**日本語は一切入れない** | PR の分岐元、docs の公開元、dotnix が参照する先 |
| `ja` | `main` + 日本語コメント + `docs-ja/` | 自分がコードを読むとき |

分けておくのは、`main` に日本語が入ると typos の CI がリポジトリ全体を検査する都合で誤検出しますし、`docs/` を GitHub Pages へ出す先も `main` だからです。

日本語コメントは `ja` ブランチにしか存在しないので、
`main` から分岐した PR には**構造的に混入しません**。
「うっかり入れてしまう」事故が起きない、というのがこの方式の要点です。

```text
                          fix/... ──●
                                     ╲   ← PR 経由でマージ
   origin/main ──●──●──●──────────────●──▶  santamn/hydenix (main)
                  ╲                    ╲
          ja ──────●─────────────────────●──▶  日本語コメント + docs-ja/
                                          ▲
                                          └ main が進むたびマージする
```

### なぜ「コミットしないで作業ツリーに置いておく」ではダメか

`hydenix-original` ではその方式でしたが、恒久運用には向きません。

- `git switch` / `git stash` / `git merge` のたびに巻き込まれる
- 誤って `git commit -a` すると混入する
- バックアップされないので、消したら終わり

ブランチにしておけば、履歴として残り、いつでも `main` に追随できます。

## 初期セットアップ

一度だけ実行します（**このリポジトリでは設定済み**）。

```bash
cd ~/Documents/hydenix

# ja ブランチを作る
git switch -c ja
```

remote の状態は次のようになります。

```text
origin    → github.com/santamn/hydenix       （自分のフォーク）
upstream  → github.com/florianvazelle/hydenix（アーカイブ済み。履歴を見るときだけ使う）
```

`upstream` は残してありますが、もう新しいコミットは来ません。消してしまっても構いません。

### 2 つを同時に開いておきたい場合

`git worktree` を使うと、`main` と `ja` を別ディレクトリで同時にチェックアウトできます。

```bash
cd ~/Documents/hydenix
git worktree add ../hydenix-ja ja
```

- `~/Documents/hydenix`     … `main`。PR 作業用（日本語なし）
- `~/Documents/hydenix-ja`  … `ja`。コードを読む用（日本語あり）

`.gitignore` に `.wt` が入っているので、
worktree をリポジトリ内に置きたい場合は `.wt/` 以下が使えます。

---

## 日常の運用

### 1. 依存を更新する

依存の更新はどれも自動で PR が立ち、一部は自動でマージされます。

| 何が動くか | 何を上げるか | マージ |
|---|---|---|
| `renovate.yml`（週次）の lockFileMaintenance | `flake.lock`（nixpkgs、home-manager ほか） | チェックが通れば renovate が自動で |
| `renovate.yml`（週次） | `pkgs/` の `rev`（HyDE やツール類のタグ）、`flake.nix` の Hyprland のタグ | 手動 |
| `update-branch-pins.yml`（毎日） | テーマ 58 個と HyDE master（`hyde-diff-upstream` 用）の commit 固定 | ワークフローが直接 |
| Dependabot（毎日） | GitHub Actions のバージョン | 手動 |

手動でマージするものが普段の作業です。Hyprland は `flake.nix` で HyDE が対応する版に固定してあるので、renovate が上げてきても HyDE 側の対応版を確認してからマージします。詳細は [10-ci.md](./10-ci.md)。

`pkgs/` の `rev` を手で書き換えたときは、`nix run .#update-hashes` で `hash` を計算し直します。renovate も同じコマンドを使うので、手動の更新と bot の更新は同じ経路を通ります。`version` は `rev` から導かれるので触りません。

### 2. `ja` ブランチを追随させる

```bash
git switch ja
git merge main
git push origin ja
```

**rebase ではなく merge を使います。** `ja` には日本語コメントとドキュメントの履歴が積み上がっており、rebase で全部書き換えると force push が要るうえ、過去のコミットが指す行番号もずれていきます。merge なら履歴はそのまま残り、push も通常どおりです。

日本語コメントは**行の追加**が中心なので、`main` 側が同じ行を触らない限り競合しません。競合するのはたいてい「英語コメントを日本語に置き換えた行を、`main` 側で書き直した」ケースです。その場合は `main` 側の内容を正として、日本語で書き直します。

```bash
# 競合したら
git status                    # 競合ファイルを確認
# 編集して解決（main 側の内容を日本語で書き直す）
git add <file>
git commit
```

`main` に自分の修正が入ったときは、コードだけでなく `docs-ja/` の該当箇所も更新してください。マージしただけでは、日本語の説明が修正前の挙動を説明したまま残ります。

### 3. 修正の PR を出す

**必ず `main` から分岐します。**

```bash
git switch main
git switch -c fix/<修正内容>

# 修正する（英語のコメントのみ。日本語は書かない）

nix fmt                       # ← 実機または nix のある環境で
git commit -am "fix: <英語で要約>"
git push -u origin fix/<修正内容>
```

PR は `santamn/hydenix` の `main` へ出します。

```text
base:    santamn/hydenix  main
compare: santamn/hydenix  fix/<修正内容>
```

直接 `main` に push せず PR を挟むのは、このリポジトリの CI が PR に対してしか linux 向けのビルドを走らせないためです（[10-ci.md](./10-ci.md)）。手元が aarch64-darwin の場合、`nix flake check` を実際に走らせられる場所はここしかありません。

### 4. 自分の修正を `ja` にも取り込む

PR が `main` にマージされたら、`ja` へマージし、日本語コメントとドキュメントを追従させます。

```bash
git switch main && git pull
git switch ja && git merge main
```

---

## PR を出すときの決まりごと

このリポジトリでは PR に対して次のようなチェックが働きます。整形以外は CI（GitHub Actions）が検査し、整形はレビューで担保する運用です。ブランチ保護ではどのチェックも必須にしていないので、落ちていてもマージ自体はできてしまいます。各ワークフローの詳細は [10-ci.md](./10-ci.md) を参照してください。

| 項目 | ツール | CI で検査 | 内容 |
|---|---|---|---|
| 整形 | treefmt（alejandra / deadnix / statix） | されない | `nix fmt` を通すこと |
| コミットメッセージ | commitlint | される | **Conventional Commits 必須**。72 文字以内、末尾のピリオド禁止 |
| スペル | typos | される | リポジトリ全体を検査 |
| Actions | zizmor | される | ワークフローの静的解析 |
| 依存の重複 | flint | される | `flake.lock` 内の依存バージョン重複を検査 |
| ビルド | flake-check | される | `nix flake check` |

コミットメッセージの型は次のどれかです。

```text
build / chore / ci / docs / feat / fix / perf / refactor / revert / style / test
```

例:

```text
docs: add Japanese reading notes
refactor(hyprland): generate assertions from mkHyprConfig
```

> [!WARNING]
> **`typos` はリポジトリ全体を検査します。** `main` に日本語ファイルを置くと、
> 日本語中に混ざった英単語が誤検出される可能性があります。
> `docs-ja/` を `ja` ブランチに閉じ込めているのは、これを避ける意味もあります。
> （CI の push トリガーは `main` のみ、PR トリガーは PR 単位なので、
> `ja` ブランチを push しても CI は走りません。）

### PR 本文の書き方

英語で、[`.github/pull_request_template.md`](../.github/pull_request_template.md) の見出しをそのまま使います。見出しを足したり名前を変えたりはしません。

| 見出し | 書くこと |
|---|---|
| What does this PR do? | 変更の要約を 2〜3 文で |
| Why is this change needed? | 何が問題で、放置するとどうなるか。issue があればリンクする |
| How was this implemented? | コミットごとの意図。レビューに要る範囲でコードの細部にも触れる |
| Type of change | 当てはまらない選択肢は消す |
| Checklist | Conventional Commits、ドキュメントの更新、新しい警告が出ないこと |
| Additional context | 任意で、ふだんは節ごと消す。差分と上の節から読み取れないこと（あえて入れなかったものとその理由など）だけを書く |

どう確かめたかを書くなら How の中に、実際に確かめたことだけを書きます。

### PR は小さく保つ

1 つの PR に 1 つの修正。関連していても、性質が違うものは分けます。

---

## dotnix 側からの参照

`dotnix` の `flake.nix` は `main` を見ます。

```nix
inputs.hydenix.url = "github:santamn/hydenix";        # = main ブランチ
```

修正を実機で検証したいときは、一時的にブランチを指定します。

```nix
inputs.hydenix.url = "github:santamn/hydenix/fix/<修正内容>";
```

```bash
nix flake update hydenix
sudo nixos-rebuild switch --flake .#<ホスト名>
```

問題なければ `main` にマージし、URL を元に戻します。

> [!TIP]
> `ja` ブランチを参照しても動作は同じですが（コメントは挙動に影響しません）、
> Nix ストアのハッシュが変わって再ビルドが走るので、**dotnix からは `main` を参照してください。**

---

## チェックリスト

PR を出す前に確認します。

- [ ] `main` から分岐している（`git merge-base --is-ancestor main HEAD` で確認できる）
- [ ] 日本語が含まれていない（`git diff main... | grep -P '[\x{3000}-\x{9fff}]'` が空）
- [ ] `docs-ja/` が含まれていない
- [ ] `nix fmt` が通る
- [ ] コミットメッセージが Conventional Commits に従っている
- [ ] 実機で動作確認した
- [ ] 1 PR = 1 修正になっている

マージ後は `ja` を追随させます。

- [ ] `git switch ja && git merge main`
- [ ] 修正した箇所の日本語コメントを書き直した
- [ ] `docs-ja/` の該当する説明を更新した
