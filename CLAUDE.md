# VSAV Training Tool — プロジェクト指示

VSAV (Vampire Savior / CPS2 / 970519 Japan) の FBNeo 用トレーニングツール。Lua。
**リポジトリはこのフォルダ。** `C:\fightcade\emulator\fbneo` は移行済みで触らない。

**最初に `handoff_v11.5_action_steps.md` を読むこと。** 経緯・落とし穴・残件はそこ。
Action Pattern Library の仕様は `design_action_pattern_library.md`。UI から設計し直す方針。
着地予測の調査結果と実装案は `design_landing_prediction.md`。
PB 採点の再設計 (保留) は `design_pb_score.md`。
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
GitHub へ出すときは commit-tree に -p fc2-v11 を付ける (「GitHub への公開手順」)
再テストを頼む前に reversal_logs を archive する (消さない)
training_settings.json は絶対に配布物へ入れない
リリース時は Analysis タブのトグルを全部 OFF にする (analysis/test_release_defaults.lua)
ビルドした zip はリポジトリに置かない (../../dist)
スクリーンショットは依頼の前に全行読む (測定値が既に写っていたことがある)
プローブを渡す前に test_probe_smoke.lua を通す (loadfile は nil 参照を通す)
テストは analysis/run_all_tests.py で回す。一覧を手で持たない
Lua の io.open の相対パスはその .lua 自身のフォルダ。require は package.path で基準が違う
registerexec / registerwrite のコールバックの中から io.open は書けない。数えてフレーム側で出す
Lua 5.1 の io.open は UTF-8 パスを開けない (ANSI API)。日本語パスは PowerShell 側でコピーさせる
gui.text は ASCII のみ。日本語は空白になる (2026-09-16 実測)。出すなら PNG にして gui.image
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

## テストを依頼するとき

**必ずコードブロックで出す。** アプリが Run ボタンを付けるので、利用者は 1 クリック
で走らせられる。**ファイルを選ぶ操作をさせない。**

**タグは ```bash、中身は PowerShell 構文。** この組み合わせでないと動かない
(2026-09-19 に両方間違えた)。

- **```powershell タグでは再生ボタンが付かない** - 利用者がコピーする羽目になる
- **```bash タグで bash 構文を書くと実行時に落ちる** - 実行は PowerShell なので
  `&&` が「有効なステートメント区切りではありません」になる

- 連結は `;`
- for ループは `foreach ($x in @("a","b")) { ... }`
- 終了コードは `$?`、捨てるなら `> $null`
- **bat はフルパスと `&` で呼ぶのが一番堅い** (cwd に依存しない。2026-09-19 に
  `cd ... ; .\path.bat` `& "フルパス"` `./path.bat` の 3 形式とも動作確認)
- **git は `--no-pager` を付けて出す** - 出力が長いとページャ (less) が開き、
  プロンプトが返らない。利用者が次に打ったコマンドはページャへの入力として
  食われ、**実行されないまま古い画面が残る。** 2026-09-19 に `git diff --stat`
  でこれが起き、push が済んだように見える画面のまま 2 往復した。パスの `/` が
  less の検索と解釈されて「Pattern not found」になるのも同じ原因。
  **迷ったらリモートを直接見る** - `git ls-remote origin refs/heads/fc2-v11` と
  `git rev-parse fc2-v11` を突き合わせれば、画面に何が出ていようと確実。

**実機での確認を頼むときも、起動コマンドを Run ボタンで出す。** プローブと
オフラインテストだけの話ではない。2026-09-19 に「完全再起動して試してください」
とだけ書いて指摘された。

```bash
cd C:/fightcaVSAV-Debug/emulator/fbneo; .\fcadefbneo.exe vsavj savestates\vsavj_fbneo.fs "$PWD\scripts\vsav_training_master_script.lua"
```

`analysis/run_*_probe.bat` は 9 本あり、**プローブ名以外は中身が同一**で取り違え
やすい (本人、2026-09-19)。どれを走らせるかは依頼する側が決めて、その 1 本だけを
Run ボタンで出す。

```bash
& "C:\fightcaVSAV-Debug\emulator\fbneo\analysis\run_select_probe.bat"
```

オフラインテストの一括実行も同じ形で出す。

```bash
cd C:/fightcaVSAV-Debug/emulator/fbneo; python analysis/run_all_tests.py
```

## 変更したら

**FBNeo は完全再起動が必要。** オフライン検証はこの 1 本で全部回る。

```bash
cd C:/fightcaVSAV-Debug/emulator/fbneo; python analysis/run_all_tests.py
```

**一覧を手で持たない。** 以前は PowerShell 版と bash 版の 2 か所にテスト名を並べていて、**2026-09-23 に 4 本取りこぼしていた**
(`test_after_ground_dash` / `test_landing_ground_recovery` / `test_wakeup_facing` / `test_position_row`)。
うち 3 本は**いちばん難しかった修正を守るテスト**で、通ってはいたが**誰も走らせていなかった**。

`run_all_tests.py` は `analysis/test_*.lua` と `scripts/tests/*_test.lua` を**探して**回すので、
新しいテストは置いた時点で対象になる。**走らせ方はテスト自身が宣言する** — ヘッダに
`cd scripts && lua5.1 ../analysis/<name>.lua` か `lua5.1 analysis/<name>.lua` のどちらかを書く。
**書いていないファイルは NG 扱いで止まる。** 推測で両方試すと、片方でたまたま通ったものを
「ok」と報告してしまう。

**`io.open` の相対パスは「その Lua スクリプト自身のフォルダ」に解決される。**
bat の `cd` 先ではない。`analysis/run_*_probe.bat` は `cd /d "%~dp0.."` で fbneo
直下へ移るが、プローブのログは **`analysis/` に出る**。`scripts/` のものは
`scripts/` に出る (`autoguard.lua` の `"reversal_logs/ag_prox.json"` が
`scripts/reversal_logs/` に落ちるのがその証拠)。

2026-09-16 にここを「bat の cd 先」と書いていたせいで、`dialogProbe.lua` から
`"analysis/dialog_probe.ps1"` を渡して解決できず、**PowerShell が対話モードで
起動して一瞬で消える**という分かりにくい形で失敗した。

**外部プロセスを起動するときは `2>&1` を付ける。** 上の件で PowerShell は
`-File の引数が存在しない` を **stderr** に出しており、`io.popen` が読む stdout
には**起動バナーしか来なかった**。バナーはエラーに見えないので、原因が
分からないまま「動かない」だけが残る。

`guardCancel.lua` には**入力列を配る歩進が 2 つある**。やることが似ているので
**2 行目まで字下げごと同じ文字列**で、片方を狙ったつもりでもう片方に当たる。

| 行(2026-09-19 時点) | 何を配るか |
|---|---|
| 4414 付近 | **プッシュブロックのタップ** (`pb_tick`) |
| 4579 付近 | **Action Steps** (`seq_tick`) |

```lua
			if _i <= #_s0.sequence then
				local _pl, _pb = entry_to_bits(_s0.sequence[_i])
```

seq_tick 側を狙うなら、その直後にしか無い
`-- THE PARKED REVERSE RIDES THE FIRST ENTRY THAT HAS ROOM.` まで錨に含める。

**同じ日に 2 回刺さっている。** 書き換えでは `assert s.count(old) == 1` が止めた
(素の replace なら**プッシュブロック側を書き換えて、構文エラーにもならず**に
紛れ込んでいた)。テストでは `find` が先にプッシュブロック側へ当たり、**照合が
常に成立して何も試していない**状態になっていた。**位置を照合するときは区間で
挟む。**

診断ログを足すときは**オフラインテストが同じファイルへ書かないこと**を確かめる。
`position.lua` のトレースを入れたまま `test_position_hotkey.lua` を回したため、
実機のログとテストの出力が同じファイルに混ざり、**2 回続けて自分のテスト出力を
実機の挙動として解析した**。テスト側で `io.open` を飲むこと。

`.gitattributes` が `* -text` なので git は改行を書き換えない。Edit 以外の手段で
書いたときは **改行が変わっていないか確認する**(Python の書き換えで `hud.lua` が
LF になり 1293 行のノイズ差分が出たことがある)。

**ファイルごとに違う。** `scripts/actionSequenceRunner.lua`、`guardCancel.lua`、
`analysis/` のテスト、ルートの `.md` は**元から LF**。`hud.lua` のように CRLF の
ものもある。**「CRLF であること」ではなく「変えていないこと」を見る。**

**`grep -c $'\r' file` で確認してはいけない。** Bash ツール経由では `$'\r'` が
展開されず**空パターンとして全行に一致**するため、**常に行数と同じ値が返り、
何を調べても「維持」に見える** (2026-09-19、数回にわたって無意味な確認を報告した)。
確認は Python で数える。

```bash
python -c "s=open('FILE',encoding='utf-8',newline='').read(); c=s.count(chr(13)+chr(10)); print('CRLF',c,'LF-only',s.count(chr(10))-c)"
```

## 公開物の書き方

個人名・ハンドル・X へのリンクを公開物に入れない (2026-09-14 の判断)。
以前入っていたクレジットは全部消してある。足し直さないこと。

**`scripts/` の中に絶対パスを書かない。** ここは丸ごと配布物に入る。テストの
ヘッダに開発機のパスを書いていたものが 2 本あり、v11.7.9 から配られていた
(`scripts/tests/actionRoute_test.lua` / `tickData_test.lua`、2026-09-23 に発見)。
走らせ方は `lua5.1 scripts/tests/<name>.lua` とだけ書けばよく、run_all_tests.py の
判定もそこしか見ていない。絶対パスの例を書いてよいのは配られない `analysis/` だけ。

## GitHub への公開手順

公開先は `origin` = `https://github.com/vampiresavior001/VSAV_Training.git`、
ブランチは **`fc2-v11`**。リポジトリの `user.name` / `user.email` は既にこの
アカウントなので、コミット時に `-c` で上書きする必要はない。

**`master` の履歴は公開しない。** 567 コミットあり、以前のクレジットもそこに
残っている。公開するのは `master` の**ツリー (中身) だけ**で、そのために
初版 `318d2ea` を**親なし (orphan)** で作ってある。ここで目的は達成済み。

### 版を足すとき

```bash
cd C:/fightcaVSAV-Debug/emulator/fbneo
git branch -f fc2-v11 $(git commit-tree 'master^{tree}' -p fc2-v11 -m "v11.7.3")
git push origin fc2-v11
```

**`-p fc2-v11` を必ず付ける。**これが「今の公開ブランチを親にする」指定で、
付け忘れると毎回親なしコミットになり、**GitHub 上で全 255 ファイルの更新日が
動く** (2026-09-15 に実際にやった。実際に変わっていたのは 16 ファイル)。

**`git push` に `-f` が要るなら何かがおかしい。** 正しく積めていれば早送りに
なる。`-f` が必要になったのは上記を作り直したときの 1 回だけ。

PowerShell では `master^{tree}` を**クオートする** (`'master^{tree}'`)。
しないと `{tree}` がスクリプトブロックとして解釈される。

公開前に `git diff --stat 318d2ea fc2-v11` で**変わるファイルが想定どおりの
本数か**見る。桁が違うなら親を付け忘れている。
