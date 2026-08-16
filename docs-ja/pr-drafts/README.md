# upstream への PR 文面ドラフト

florianvazelle/hydenix へ提出する 4 本の PR の文面案。各ファイルの Description 以下が PR 本文の元になる（提出時は英訳する想定）。ブランチは提出済みの push 済みトピックブランチで、いずれも `upstream/main` (6b549d0) 起点。

| PR | ブランチ | 内容 | コミット数 | 文面 |
| --- | --- | --- | --- | --- |
| A | `fix/theme-assets-from-nixpkgs` | カーソル/アイコンテーマを nixpkgs 由来にする（旧 #3/#4/#5） | 3 | [pr-a-theme-assets.md](pr-a-theme-assets.md) |
| B | `fix/hyde-scripts-on-nixos` | HyDE の shell/python スクリプトを NixOS で動かす（旧 #7/#8） | 2 | [pr-b-hyde-scripts.md](pr-b-hyde-scripts.md) |
| C | `fix/swaync-waybar-process-name` | waybar の swaync モジュール修正（旧 #9） | 1 | [pr-c-swaync.md](pr-c-swaync.md) |
| D | `fix/hyprsunset-missing-package` | hyprsunset をインストールする（旧 #6） | 1 | [pr-d-hyprsunset.md](pr-d-hyprsunset.md) |

## 提出順の推奨

D → C を先に出す（1〜3 行の独立した修正で、上流の反応速度とレビュースタイルの確認になる）。その後 B、最後に A（最大で、レビューに時間がかかる）。

## 差分の GUI 確認

各ブランチと upstream/main の差分は GitHub の compare ビューで PR と同じ見た目で確認できる:

- A: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/theme-assets-from-nixpkgs>
- B: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/hyde-scripts-on-nixos>
- C: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/swaync-waybar-process-name>
- D: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/hyprsunset-missing-package>

このリンクの「Create pull request」からそのまま PR を作成できる。

## 提出時の注意

- PR タイトルは各ファイル冒頭の「タイトル案」をそのまま使う（conventional commit 形式。upstream の commit-lint は PR 内の各コミットヘッダに対して走り、全コミット検証済み）。
- Type of change / Checklist は upstream の `.github/pull_request_template.md` の項目で、該当行のみ残す。
- 旧 PR からの変更点: コード中の長い説明コメントは削除し 1 行に短縮（説明は PR 本文へ移動）、`flake.nix` の `inherit` を 1 行に統合、weekly cron は削除、`sharedAssets` のデフォルト値 `? {}` を削除、`Co-Authored-By` trailer を全コミットで統一。
