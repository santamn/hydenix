# 09. フォークの運用 — 上流追従と PR

日本語コメントを持ちながら、上流（florianvazelle/hydenix）へ英語の PR を送るための運用方法です。

## 結論

**ブランチを分けます。**

| ブランチ | 中身 | 用途 |
|---|---|---|
| `main` | 上流と同じ。**日本語は一切入れない** | 上流追従、PR の分岐元、dotnix が参照する先 |
| `ja` | `main` + 日本語コメント + `docs-ja/` | 自分がコードを読むとき |

日本語コメントは `ja` ブランチにしか存在しないので、
`main` から分岐した PR には**構造的に混入しません**。
「うっかり入れてしまう」事故が起きない、というのがこの方式の要点です。

```
upstream/main ──●──●──●──────────────▶  florianvazelle/hydenix
                 ╲
   origin/main ───●──●──●─────────────▶  santamn/hydenix (main)
                   ╲       ╲
        ja ─────────●───────●─────────▶  日本語コメント + docs-ja/
                            ▲
                            └ main が進むたび rebase する
```

### なぜ「コミットしないで作業ツリーに置いておく」ではダメか

`hydenix-original` ではその方式でしたが、恒久運用には向きません。

- `git switch` / `git stash` / `git merge` のたびに巻き込まれる
- 誤って `git commit -a` すると混入する
- バックアップされないので、消したら終わり

ブランチにしておけば、履歴として残り、いつでも `main` に追随できます。

### なぜ「コメントを英語で書く」ではダメか

それでも構いませんが、目的が変わります。
この日本語コメントは「自分が読んで理解するため」のもので、
上流に必要な粒度（利用者向けの API 説明）とは別物です。
混ぜると両方が中途半端になるので、分けたほうが健全です。

---

## 初期セットアップ

一度だけ実行します（**このリポジトリでは設定済み**）。

```bash
cd ~/Documents/hydenix

# 上流を remote に登録
git remote add upstream https://github.com/florianvazelle/hydenix.git
git fetch upstream

# ja ブランチを作る
git switch -c ja
```

remote の状態は次のようになります。

```
origin    → github.com/santamn/hydenix       （自分のフォーク）
upstream  → github.com/florianvazelle/hydenix（上流）
```

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

### 1. 上流に追従する

```bash
git switch main
git fetch upstream
git merge upstream/main       # 競合はまず起きない（main には自分の変更が無い）
git push origin main
```

### 2. `ja` ブランチを追随させる

```bash
git switch ja
git rebase main
```

日本語コメントは**行の追加**が中心なので、
上流が同じ行を触らない限り競合しません。競合したら、
その部分は上流の変更を優先し、コメントを付け直します。

```bash
# 競合したら
git status                    # 競合ファイルを確認
# 編集して解決
git add <file>
git rebase --continue
```

`ja` は rebase で履歴が書き換わるので、push は force が要ります。

```bash
git push --force-with-lease origin ja
```

> [!TIP]
> `--force-with-lease` は「リモートが自分の知っている状態のときだけ上書きする」オプションです。
> `--force` より安全なので、こちらを使ってください。

### 3. 上流へ PR を送る

**必ず `main` から分岐します。**

```bash
git switch main
git switch -c fix/mutable-generation-dag-name

# 修正する（英語のコメントのみ。日本語は書かない）

nix fmt                       # ← 実機または nix のある環境で
git commit -am "fix: correct activation dependency name to mutableFileGeneration"
git push -u origin fix/mutable-generation-dag-name
```

GitHub の Web UI で PR を作成します。

```
base:    florianvazelle/hydenix  main
compare: santamn/hydenix         fix/mutable-generation-dag-name
```

### 4. 自分の修正を `ja` にも取り込む

PR が `main` にマージされたら、`ja` を rebase するだけです。

```bash
git switch main && git pull
git switch ja && git rebase main
```

---

## PR を出すときの決まりごと

このリポジトリでは PR に対して次のようなチェックが働きます。整形以外は CI（GitHub Actions）が強制し、整形はレビューで担保する運用です。各ワークフローの詳細は [10-ci.md](./10-ci.md) を参照してください。

| 項目 | ツール | CI で強制 | 内容 |
|---|---|---|---|
| 整形 | treefmt（alejandra / deadnix / statix） | されない | `nix fmt` を通すこと |
| コミットメッセージ | commitlint | される | **Conventional Commits 必須**。72 文字以内、末尾のピリオド禁止 |
| スペル | typos | される | リポジトリ全体を検査 |
| Actions | zizmor | される | ワークフローの静的解析 |
| 依存の重複 | flint | される | `flake.lock` 内の依存バージョン重複を検査 |
| ビルド | flake-check | される | `nix flake check` |

コミットメッセージの型は次のどれかです。

```
build / chore / ci / docs / feat / fix / perf / refactor / revert / style / test
```

例:

```
fix: correct activation dependency name to mutableFileGeneration
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

英語で、次の 5 点を含めます。

- **What**: 何が問題か
- **Why it matters**: なぜ直すべきか（放置するとどうなるか）
- **Evidence**: 根拠となるコード箇所
- **Risk**: 変更のリスク
- **Testing**: どう確認したか（**実際に確認してから書くこと**）

例（[08-improvements.md](./08-improvements.md) の A-1）:

> **What**: Three activation entries depend on `mutableGeneration`, which does not exist.
> `modules/hm/mutable.nix` defines the entry as `mutableFileGeneration`.
>
> **Why it matters**: home-manager silently ignores unknown dependency names in its
> activation DAG, so the intended ordering ("run after mutable files are copied") is
> not enforced. The actual execution position depends on the toposort implementation
> and may change when home-manager is updated.
>
> **Evidence**: `grep -rn 'entryAfter \["mutableGeneration"\]' modules/`
>
> **Risk**: None. `mutable.nix`'s `config` is unconditional, so the entry always exists.
>
> **Testing**: Rebuilt on my NixOS machine; theme applies correctly on a clean profile.

### PR は小さく保つ

1 つの PR に 1 つの修正。関連していても、性質が違うものは分けます。

例: [08](./08-improvements.md) の A-1（文字列 3 か所・リスクゼロ）と
A-2（`$DRY_RUN_CMD` の追加・挙動が変わる）は**別々の PR にします**。

---

## dotnix 側からの参照

`dotnix` の `flake.nix` は `main` を見ます。

```nix
inputs.hydenix.url = "github:santamn/hydenix";        # = main ブランチ
```

修正を実機で検証したいときは、一時的にブランチを指定します。

```nix
inputs.hydenix.url = "github:santamn/hydenix/fix/mutable-generation-dag-name";
```

```bash
nix flake update hydenix
sudo nixos-rebuild switch --flake .#<ホスト名>
```

問題なければ `main` にマージし、URL を元に戻します。

> [!TIP]
> `ja` ブランチを参照しても動作は同じですが（コメントは挙動に影響しません）、
> Nix ストアのハッシュが変わって再ビルドが走るので、
> **dotnix からは `main` を参照してください。**

---

## チェックリスト

上流に PR を送る前に確認します。

- [ ] `main` から分岐している（`git merge-base --is-ancestor main HEAD` で確認できる）
- [ ] 日本語が含まれていない（`git diff main... | grep -P '[\x{3000}-\x{9fff}]'` が空）
- [ ] `docs-ja/` が含まれていない
- [ ] `nix fmt` が通る
- [ ] コミットメッセージが Conventional Commits に従っている
- [ ] 実機で動作確認した
- [ ] 1 PR = 1 修正になっている
