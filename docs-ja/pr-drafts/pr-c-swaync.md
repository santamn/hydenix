# PR C: waybar の swaync モジュールをラップ後のプロセス名に対応させる

- ブランチ: `fix/swaync-waybar-process-name`（1 コミット、diff は 3 行）
- タイトル案: `fix(pkgs): match swaync's wrapped process name in the waybar module`
- 差分: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/swaync-waybar-process-name>

---

## Description

### 問題

通知デーモンを swaync に切り替えても、waybar の通知モジュール（ベルと未読カウント）が一切表示されない。`custom/swaync` を含むレイアウト（`hyprdots/16`, `hyprdots/17`, `khing`）すべてで再現する。

### 原因

`custom-swaync.jsonc` の常駐チェック `"exec": "pgrep -x swaync && swaync-client -swb"`。nixpkgs の `swaynotificationcenter` は `wrapGAppsHook3` でビルドされるため `$out/bin/swaync` はラッパースクリプトで、実際に走るプロセスの `comm` は `.swaync-wrapped` になる。`pgrep -x` は `comm` との完全一致なので常に失敗し、`exec` が何も出力しないため waybar はモジュールを描画しない。

このリポジトリが既に `killall waybar` → `killall .waybar-wrapped` などの sed で潰しているのと同種の問題なので、修正も同じ `buildPhase` の sed 群の隣に置いた。

### 修正

```nix
# update swaync
find . -type f -print0 | xargs -0 sed -i 's/pgrep -x swaync/pgrep -x .swaync-wrapped/g'
```

### 検証

- HyDE v26.7.4 のツリーに同じ sed を適用し、`custom-swaync.jsonc` の 1 箇所だけが書き換わり、ツリー全体から `pgrep -x swaync` が消えることを確認
- `.swaync-wrapped` は 15 文字で `comm` の上限（`TASK_COMM_LEN` = 16、NUL 込み）に収まるため切り詰められない
- nixpkgs の `swaynotificationcenter` に `dontWrapGApps` の指定が無く、`wrapGAppsHook3` が実際に `$out/bin` をラップすることを確認

## Type of change

- [x] Bug fix (non-breaking change which fixes an issue)

## Checklist

- [x] My commits follow conventional commit format
- [x] I have updated the documentation accordingly — n/a
- [x] My changes generate no new warnings

---

## 提出時メモ（PR 本文には含めない）

- 旧 #9 と同一内容。upstream/main 上ではコンテキスト衝突するため cherry-pick を手動解決済み（中身は同じ 3 行）
- 意図的に含めていないもの: `exec-if` の `1>2` は upstream のタイポ（NixOS 固有でない）、`workflows.sh` の `pgrep -x waybar` など同種の疑いがある箇所（対象パッケージが実際にラップされるか個別確認が要る）、sed が no-op になったときの検知（既存 sed 群共通の課題）。聞かれたら PR コメントで説明する
