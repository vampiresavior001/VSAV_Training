# VSAV Training Tool — プロジェクト指示

VSAV (Vampire Savior / CPS2 / 970519 Japan) の FBNeo 用トレーニングツール。Lua。
**リポジトリはこのフォルダ。** `C:\fightcade\emulator\fbneo` は移行済みで触らない。

**最初に `handoff_v11.5_action_steps.md` を読むこと。** 経緯・落とし穴・残件はそこ。
ゲーム側の解析結果は `VSAV_MEMORY_NOTES.md`(事実だけ。推測を書かない)。

## 守ること

共通指示 (user 階層の CLAUDE.md) にあることは繰り返さない。ここはこのプロジェクト
固有の規約だけ。

```
コミットメッセージは日本語。ソースコメントだけ英語
推測で直さない。分からなければアセンブラ (ROM) に戻る
手を入れる前に既存スクリプトを洗う (車輪の再開発防止)
実装前にログや既存テストで検証し、予測を報告してからテストを依頼する
目視確認は最小限。判定はコードにさせ、ユーザには「1 回普通に使う」だけ頼む
正しさと簡単さなら簡単さ
120f のような固定フレーム数を入れない
版を渡すたびに git tag を打つ
再テストを頼む前に reversal_logs を archive する (消さない)
training_settings.json は絶対に配布物へ入れない
リリース時は Analysis タブのトグルを全部 OFF にする (analysis/test_release_defaults.lua)
ビルドした zip はリポジトリに置かない (../../dist)
スクリーンショットは依頼の前に全行読む (測定値が既に写っていたことがある)
プローブを渡す前に test_probe_smoke.lua を通す (loadfile は nil 参照を通す)
Lua が io.open で書く先はエミュレータの作業ディレクトリ (起動 bat の cd 先)
```

## ゲーム側の規約(破ると技が出ない)

- **必殺技コマンド以外はすべて free+0。** 押しが free+0 に乗らなければ
  「遅い」ではなく「出ない」。
- **tick と表示フレームは別。** turbo 3 で 3 フレーム : 4 tick。`0xFF8081` が
  tick カウンタ。
- **v158 の規則** — ボタンを伴わない入力は 2 tick、伴えば 1 tick。
- `memory.registerexec(0x02211A, ...)` は**積めない**。2 回目の登録が
  1 回目を黙って置き換える。
- **Lua ホットキーは押している間ずっと呼ばれる。** 1 回の押しが 1 回の
  コールバックではない (実測 38 回)。押下で作り直す処理は、走っている間は
  無視すること。
- **`match_begun` を「試合中か」に使わない。** 変身中 (デミトリのバットスピン
  など) に false へ落ちる。`globals.match_running()` を使う。

## 変更したら

**FBNeo は完全再起動が必要。** オフライン検証は必ず `scripts/` から走らせる
(相対パスで `controller.lua` と `guardCancel.lua` をソースごと読むため)。

```bash
cd C:/fightcaVSAV-Debug/emulator/fbneo/scripts && for t in test_editor_rows test_editor_ops test_runner_compile test_seq_hold test_gc_frequency test_gc_leftover test_random_sources test_menu_gate test_menu_children test_menu_layout test_menu_switches test_pb_counter test_input_releases test_input_tick_columns test_release_defaults test_throw_tech test_hs_countdown; do lua5.1 ../analysis/$t.lua > /dev/null && echo "$t ok" || echo "$t NG"; done
```

下記はパッケージのルートから走らせる (Tick Data は `scripts/tickData` を require
するため、配線テストは master script をソースごと読むため)。

```bash
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 scripts/tests/tickData_test.lua
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_framedata_gate.lua
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_tickdata_vsav.lua
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_state_load_wiring.lua
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_probe_smoke.lua
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_position_hotkey.lua
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_char_chosen.lua
cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 scripts/tests/actionRoute_test.lua
```

**ログの出る場所は起動した bat で変わる。** `io.open` の相対パスはエミュレータの
作業ディレクトリに解決されるので、`run_vsav_training.bat` (fbneo 直下から起動)
なら fbneo 直下、`analysis/run_*_probe.bat` も `cd /d "%~dp0.."` で fbneo 直下。
**探すときは fbneo 直下と scripts/ の両方を見る** (2026-09-13 に scripts/ だけ見て
「出ていない」と誤認しかけた)。

診断ログを足すときは**オフラインテストが同じファイルへ書かないこと**を確かめる。
`position.lua` のトレースを入れたまま `test_position_hotkey.lua` を回したため、
実機のログとテストの出力が同じファイルに混ざり、**2 回続けて自分のテスト出力を
実機の挙動として解析した**。テスト側で `io.open` を飲むこと。

`.gitattributes` が `* -text` なので git は改行を書き換えない。Edit 以外の手段で
書いたときは **CRLF が残っているか確認する**(Python の書き換えで `hud.lua` が
LF になり 1293 行のノイズ差分が出たことがある)。

## 公開物の書き方

個人名・ハンドル・X へのリンクを公開物に入れない (2026-09-14 の判断)。
以前入っていたクレジットは全部消してある。足し直さないこと。
