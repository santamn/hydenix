# PR B: HyDE の shell/python スクリプトを NixOS で動かす

- ブランチ: `fix/hyde-scripts-on-nixos`（2 コミット）
- タイトル案: `fix(pkgs): make HyDE's shell and python entry points work on NixOS`
- 差分: <https://github.com/florianvazelle/hydenix/compare/main...santamn:hydenix:fix/hyde-scripts-on-nixos>

---

## Description

### 問題

HyDE のエントリポイントが NixOS 上で黙って死ぬ原因が 2 つあり、どちらも waybar のモジュールが空になる症状として現れる（時計の左の空ピル、blue light filter アイコンの欠落、レイアウト切り替え不能など）。失敗するプロセスが exit 0 で出力ゼロのため、ログには何も残らない。原因が独立している一方で症状が同じ領域に重なるため、2 コミットの 1 PR にまとめた。

### 原因と修正（コミット順）

**1. `fix(pkgs): keep hyde-shell sourceable instead of wrapping it`**

`hyde-shell` は実行されるだけでなく **source される**設計になっている（`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` でディスパッチをガードしている）。HyDE v26.7.4 では `hyprsunset.sh`, `hyprlock.sh`, `animations.sh`, `workflows.sh`, `wallpaper.mpvpaper.sh` の 5 スクリプトが冒頭で `source "$(which hyde-shell)"` する。

現状は `wrapProgram` が `hyde-shell` を `exec` で終わるラッパーに置き換えている。`exec` は**現在のプロセス**を置換するため、source された場合は source 元のスクリプト自身が 1 行目で消滅し、出力ゼロ・exit 0 で終わる。waybar の `custom/hyprsunset` は JSON を受け取れず、アイコンも `on-click` も死ぬ。

修正: wrap をやめ、ラッパーが設定していた PATH の export を `hyde-shell` 自体の shebang 直後に埋め込む。実行時の挙動は従来どおりで、source しても `exec` が無いので source 元が生き残る。

**2. `fix(pkgs): give HyDE's python scripts a real interpreter`**

HyDE は同梱の Python スクリプトを、実行時に uv で作る venv（`$XDG_STATE_HOME/hyde/python_env`）のインタプリタで動かす前提になっている。この venv を作るのは `hyde-shell pyinit` だが、この flake には実行する仕組みがない。にもかかわらず `hyde-shell` の `run_command`（`.py` 分岐）、`gpuinfo.sh`（AMD 分岐）、`gamelauncher.sh` の計 5 箇所が venv のインタプリタを絶対パスで直接 `exec` しており、存在しないパスの `exec` で呼び出し元が即死する。`custom/weather`（空ピルの正体）、waybar レイアウト切り替え、`sensorsinfo`、`mediaplayer`、`amdgpu`、game launcher がすべてこれで死んでいる。

修正: upstream の `pyproject.toml` の依存のうち nixpkgs にあるもの（`loguru`, `pulsectl`, `requests`, `inotify-simple`, `pywayland`, `pygobject3` + overlay の `pyamdgpuinfo` + `pyutils` が import する `xdg-base-dirs`）でインタプリタを組み立て、`buildPhase` の既存 sed 群の隣でハードコードされた venv パスを差し替える。インタプリタは `hydePython` 引数として公開してあるので、追加ライブラリが欲しいユーザーは override できる。

意図的に除外した依存: `hererocks`（nixpkgs に無く Lua 環境専用）、`pyprland`（このリポジトリでは無効化されている）、`PyQt6`（closure が重いわりに利用箇所が 1 ファイル）、`pysensors`（nixpkgs に無く最終リリース 2017 年、遅延 import なので無くても他経路は動く）。

`pyamdgpuinfo` がインタプリタに入ったことで 1 が埋め込んだ `PYTHONPATH` 行は不要になり削除、PATH に入れるのも `hydePython` に統一した。`hyde-shell pyinit` / `uv` / `luainit` は触っていない（従来から壊れており、waybar の経路にも乗っていない）。

### 検証

- 実機（この flake を使う NixOS マシン）で blue light filter のアイコンが描画され、トグルが動作することを確認: `hyde-shell hyprsunset -rq` が waybar 用 JSON を返す
- pin されている nixpkgs 上で `x86_64-linux` として `pkgs.hyde.drvPath` の eval 成功（追加した属性がすべて解決する）
- HyDE v26.7.4 の実ツリーに同じ置換を適用し、5 箇所すべてが置換されて `python_env/bin/python` への参照が 0 件になること、`hyde-shell` / `gpuinfo.sh` / `gamelauncher.sh` が `bash -n` を通ることを確認
- alejandra clean

補足: `custom/updates` が NixOS で空のままなのは upstream の仕様（`/etc/arch-release` が無いと即 exit 0）で、このPRの対象外。

## Type of change

- [x] Bug fix (non-breaking change which fixes an issue)

## Checklist

- [x] My commits follow conventional commit format
- [x] I have updated the documentation accordingly — n/a（ユーザー向けオプションの変更なし。`hydePython` は package 引数）
- [x] My changes generate no new warnings

---

## 提出時メモ（PR 本文には含めない）

- 旧 #7/#8 の統合。#8 は #7 が埋め込んだ PYTHONPATH 行を削除するため #7 に依存しており、分割すると単独では適用できない
- 2 コミット目は PR #8 と同一内容（コード中の長い説明コメントを 1 行に短縮した点のみ差分）
