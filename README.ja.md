# VSAV_Training - The Warlord's Secret

See what the Warlord sees, and practice what the Warlord practices, in VSAV training mode for Fightcade 2.

[English](README.md) | 日本語

**達人の精密な動きを、練習相手に。** 内部フレーム（Tick）単位でダミーの動きを指定し、守りの練習と攻めの検証ができる、Fightcade 2／FBNeo用のトレーニングモードです。入力がどこで受け付けられたか、攻撃がいつ当たったかを画面で確かめながら、自分の対処を直せます。

[VSAV_Trainingのfc2ブランチ](https://github.com/NBeing/VSAV_Training/tree/fc2)を基に拡張したフォークです。本書の対象は **v11.7.24.2** です。

**[ダウンロード（最新版）](https://github.com/vampiresavior001/VSAV_Training/releases/latest)** · [導入](#windowsでの導入) · [守りを練習する](#first-ag-drill) · [起き攻めを調べる](docs/PLAYER_MANUAL.ja.md#wakeup-pressure-drill) · [日本語マニュアル](docs/PLAYER_MANUAL.ja.md)

**同梱のサスカッチ用パターンで、動きを自分で作らずにAG・GC練習を始められます。** [画像付きチュートリアル](docs/PLAYER_MANUAL.ja.md#sasquatch-ag-tutorial)に沿って進めてください。

![左はAG、右はGCを練習中の画面。番号は表示の種類](docs/images/screen_map.png)

左：遅らせAGでも6回入力できたかを確認。右：GCの方向入力やボタンが、どこまで受け付けられたかを確認。各表示の読み方は[画面の見方](docs/PLAYER_MANUAL.ja.md#screen-map)へ。

## 再現して、練習して、直す

1. **相手を再現する。** Action Stepsで動作とタイミングを指定し、最速ダッシュからの攻撃や中足払いキャンセル天雷破など、精密な操作を要する動きを繰り返し再現します。起き上がり・ガード後・着地後には、必殺技のリバーサルだけでなく、**小技・投げによる暴れ、ジャンプ、ダッシュ**も出させられます。
2. **練習する・試す。** 同じ攻めを繰り返させてAG・GC・空中ガード後の割り込みを練習したり、自分の起き攻めや連係を、決まった反撃に当てて試したりします。
3. **結果を見て直す。** 入力が受付のどこに入ったか、攻撃が何Tick目に当たったかを画面で確かめ、次の一手を直します。PB Stats（英語UIのPBはAGのこと）とGC Statsで、成功率と入力時間の変化も追えます。

AGの成立判定やGCの入力受付には乱数が関わるため、成功・失敗だけでなく、実際に受け付けられた入力から改善点を探せます。

## 何を調べ、練習できるか

### 守りを練習する

| 目的 | 使い方 |
|---|---|
| **AGの押し方を直す** | [PB Counter](docs/PLAYER_MANUAL.ja.md#08-pb)で、受付のどこで何回押したかを見る。PB Statsで成功率と平均も追える |
| **GCの失敗原因を見つける** | [GC Command Trace](docs/PLAYER_MANUAL.ja.md#09-gc)で、どの方向・ボタンが受け付けられ、どこで切れたかを見る。[GC Stats](docs/PLAYER_MANUAL.ja.md#gc-stats)で左右の成功率を比べる |
| **実戦に近い守りを練習する** | 複数の攻めや入力タイミングをランダムにし、固定のリズムに頼らずAG・GCする。[設定の使い分け](docs/PLAYER_MANUAL.ja.md#dummy-button-timing) |
| **空中ガード後の攻防を調べる** | [Air Guard Gaps](docs/PLAYER_MANUAL.ja.md#air-guard-gaps)で、空中チェーンの隙間、割り込みタイミング、着地後の有利不利を確認する |

### 攻めを調べる

| 目的 | 使い方 |
|---|---|
| **起き攻め・連係を検証する** | 相手の反撃を固定し、[Meaty Timing](docs/PLAYER_MANUAL.ja.md#meaty-timing)で当たったタイミングと実際の結果を比べる |
| **セットプレイを組み立てる** | [Action Timeline](docs/PLAYER_MANUAL.ja.md#action-timeline)で、起き攻めのフレーム消費や歩き投げまでの所要時間を調べる |
| **めくりのオプションセレクトを調べる** | [Auto-Flip Inputs on Side Switch](docs/PLAYER_MANUAL.ja.md#side-switch-os)を`no`にし、めくられた後も同じ入力を送り続けて、何が出るかを確かめる |

![デミトリの強デモンクレイドルの後、前ジャンプからのジャンプ小Pがモリガンの起き上がりに重なった画面。Meaty TimingはWake-up Reversal +0t Active 2t](docs/images/meaty_safe_jump.png)

デミトリの強デモンクレイドルの後、前ジャンプからのジャンプ小Pが、モリガンの起き上がりに `Reversal +0t`（リバーサルTickちょうど）で重なった例です。すぐ着地するので、リバーサルのシャドウブレイドも地上でガードできる詐欺飛びになります。画像は重なった瞬間です。リバーサルを着地してガードした画面と確かめ方は、[起き攻めの練習レシピ](docs/PLAYER_MANUAL.ja.md#safe-jump-example)へ。

### 技の性能を見る

| 目的 | 使い方 |
|---|---|
| **数値で見る** | [Tick Data](docs/PLAYER_MANUAL.ja.md#tick-data)で、発生・持続・戻り・有利不利を内部フレーム単位で測る。数え方・考え方は[技表](http://darkstalkers.web.fc2.com/savior/savior.html)に合わせている |
| **色の帯で見る** | [Frame Meter](docs/PLAYER_MANUAL.ja.md#frame-meter)で、発生・攻撃判定・戻り・無敵などを、両プレイヤーとも1 Tickごとのマスで並べて見る |

### 練習相手を作る

ダミーは、ガードした後・攻撃を受けた後・起き上がりなどのきっかけで、ここで作った行動を出します（[ダミーが動くしくみ](docs/PLAYER_MANUAL.ja.md#dummy-model)）。記録は、きっかけを待たずに再生することもできます。

| 目的 | 使い方 |
|---|---|
| **自分で操作できる動きを使う** | [Recording Wizard](docs/PLAYER_MANUAL.ja.md#05-recording)で、操作の開始から終了までを自動で記録し、確認して保存する。記録・再生は表示フレーム単位 |
| **精密な動きを再現する** | [Action Steps](docs/PLAYER_MANUAL.ja.md#06-steps)で、動作とタイミングをTick単位で指定する |
| **複数の動きをランダムに出す** | [Action Patterns](docs/PLAYER_MANUAL.ja.md#07-patterns)で、作った動きを名前付きで保存し、使う候補からランダムに実行する |

## Windowsでの導入

対象ゲームは **Vampire Savior - the lord of vampire（970519 Japan／`vsavj`）** です。

**ROMは含まれません。各自で用意し、先にFBNeoでゲームが起動できる状態にしてください。**

**FBNeoの`Video > Runahead`は`Disabled`にしてください。** 有効なままでは、反撃などのタイミングが正しく再現されません。Fightcadeで対戦もする場合は、FBNeoフォルダーを丸ごと複製して練習専用にすると、設定を切り替えずに済みます。対戦は通常のFightcadeから、練習は複製先のバッチから起動します。

1. FightcadeとFBNeoを終了します。
2. Fightcadeの`emulator/fbneo`フォルダー全体を、別の場所へコピーします。例：`C:/VSAV_Training/fbneo`。
3. [最新版のzip](https://github.com/vampiresavior001/VSAV_Training/releases/latest)をダウンロードして展開し、`run_vsav_training.bat`と`scripts`フォルダー全体を、**複製先のfbneoフォルダー**へ配置します。バッチファイルは`fcadefbneo.exe`と同じ階層に置きます。
4. 複製先の`run_vsav_training.bat`を起動し、FBNeo本体の **`Video > Runahead > Disabled`** を選びます。元の設定もコピーされるため、複製するだけでは無効になりません。
5. FBNeoを完全終了して同じバッチから再起動します。`Video > Runahead`で`Disabled`が選ばれていることを確認します。試合中に`RUN-AHEAD DETECTED`の警告が出たら、設定と起動先を再確認してください。
6. `Input > Map Game Inputs`でゲーム操作と下表の機能を割り当てます。P2側のゲーム入力も設定してください。

全画面で遊ぶときは、先に`Video > Blitter options > Windowed Fullscreen`にチェックを入れてください。古い形式の全画面では、パターンの名前入力やExport・Importのウィンドウを表示できません。

配置先は、日本語を含まない短いパスを使用してください（空白は含んでも構いません）。既存環境を更新する場合は、先に[バックアップ](#更新とバックアップ)を行います。

### 基本操作

**`Lua Hotkey 1`と`P1 Coin`はメニューで代用できないため、必ず割り当ててください。** ほかの項目は、下表のメニュー操作で代用できます。

<details>
<summary>ボタン一覧とメニューでの代用操作を開く</summary>

| FBNeoの入力項目 | 機能 | メニューでの代用操作 |
|---|---|---|
| `Lua Hotkey 1` | トレーニングメニューを開閉 | 代用不可・**必須** |
| `Lua Hotkey 2` | レバーとの組み合わせで位置を戻す | `Dummy > Position`で左右を押して配置を選ぶ。LPで同じ配置に戻す。HPなら戻してメニューも閉じる |
| `Lua Hotkey 3` | 記録のループ再生を切り替える | `Recording > Looped Playback`を左右で`yes`／`no`に切り替える |
| `Lua Hotkey 4` | キャラクター選択へ戻る | `Game > Return to Character Select`で右またはLP |
| `Volume Up` | 入力記録の開始・終了（手動） | `Recording > Recording Wizard`で右またはLP。スロットを選び、自動記録で代用する（下記参照） |
| `Volume Down` | 記録の再生・停止 | `Recording > Play Recording`で右またはLP。もう一度実行すると停止 |
| `P1 Coin` | 試合中は操作側を切り替え。キャラ選択中はステージ選択 | 代用不可・**必須** |

メニューは`Lua Hotkey 1`で開き、上端のタブ名で左右を押してタブを切り替え、上下で項目を選びます。LPは弱Pです。`>`は「タブ > 項目」の順を表します。

**記録をメニューで代用する場合：** ウィザードでスロットを選び、いったん入力を離してから操作すると記録が始まります。操作を終えて入力を離し、ダミーが動ける状態で約2秒待つと自動終了します。確認画面で保存を選び、LPで決定してください。手動で開始・終了を指定したい場合は`Volume Up`を使います。

記録の`Looped Playback`と、Action Stepsの`Loop Steps`は別の設定です。[記録の詳しい手順](docs/PLAYER_MANUAL.ja.md#05-recording)も参照してください。

`Volume Up / Down`はFBNeoの入力項目名です。アーケードコントローラーなどのボタンにも割り当てられます。

</details>

<a id="first-ag-drill"></a>

## 最初の練習：サスカッチを相手にAG・GCを練習する

サスカッチにショートダッシュ小Pをさせて、AG（アドバンシングガード）とGC（ガードキャンセル）を練習します。同梱パターンを使えば、動きを自分で作る前に練習を始められます。

最初はAGかGCのどちらかを試せれば十分です。連発や自分で動きを作る操作は、慣れてから進めてください。以下は流れです。実際の設定は[画像付きチュートリアル](docs/PLAYER_MANUAL.ja.md#sasquatch-ag-tutorial)に沿って進めてください。

1. **取り込む。** ダミーをサスカッチにし、`Reversal - Action Patterns`の`Import from a File`で、配布物の`scripts/patterns/Sasquatch_Short_LP.json`を取り込みます。`Short LP`だけを使用する設定にします。
2. **AGする。** こちらの技をガードさせてショートダッシュ小Pを出させ、これにAGします。PB Counter／PB Statsで、例えば遅らせAGで受付内に6回入力できたか確認します。
3. **GCも試す。** 同じ小Pに自キャラのGCを入力し、成功表示と、受け付けられた方向・ボタン・入力間隔を確認します。[GC Stats](docs/PLAYER_MANUAL.ja.md#gc-stats)で左右それぞれの成功率も確認できます。
4. **連続で練習する。** `Loop Steps = yes`、`Loop Wait = Auto (Landing)`にして、着地からショートダッシュ小Pを繰り返させます。
5. **自分の練習へ広げる。** 取り込んだパターンは次回も使えます。慣れたらAction Stepsで別の攻めを作り、Action Patternsに保存して、複数候補のランダム練習へ発展させられます。

入力表示の読み方と、結果に応じた調整方法は、[AG練習](docs/PLAYER_MANUAL.ja.md#08-pb)と[GC練習](docs/PLAYER_MANUAL.ja.md#09-gc)を参照してください。

## なぜTick単位なのか

Tickはゲームの内部フレームです。ターボ3では表示3フレームの間に4 Tick進むので、表示フレームで数えると、入力のタイミングも技の測定値もずれることがあります。本フォークは、この内部フレームに合わせてダミーの入力を制御します。

| ゲーム速度 | 表示フレームと内部フレームの関係 |
|---|---|
| ノーマル | 表示1フレーム＝1 Tick |
| ターボ3 | 表示3フレーム＝4 Tick |

行動ごとの最速入力の条件は[Action Steps](docs/PLAYER_MANUAL.ja.md#06-steps)を参照してください。

**記録・再生は表示フレーム単位です。** Tick単位の正確なタイミングが必要な動きは、Action Stepsで定義してください。一方、**Tick Data**などの測定はTick単位で、従来の表示フレーム単位の測定で生じていたターボによる数値の揺れを抑えています。測定条件と読み方は[マニュアル11章](docs/PLAYER_MANUAL.ja.md#10-data)で説明しています。

ただし、ダッシュ系の既存トレーナーなど、表示フレームで数える表示も残っています。どの表示がどちらの単位かは、[マニュアル11.1](docs/PLAYER_MANUAL.ja.md#ticks-and-frames)の一覧を確認してください。

## マニュアル

**[日本語プレイヤーマニュアル](docs/PLAYER_MANUAL.ja.md)** に、操作・設定・表示の読み方をまとめています。

- **相手を作る：** [ダミーのガード・受け身・反撃](docs/PLAYER_MANUAL.ja.md#04-dummy)、[記録とループ再生](docs/PLAYER_MANUAL.ja.md#05-recording)、[Action Steps](docs/PLAYER_MANUAL.ja.md#06-steps)、[Action Patterns](docs/PLAYER_MANUAL.ja.md#07-patterns)
- **練習する：** [AG練習](docs/PLAYER_MANUAL.ja.md#08-pb)、[GC練習](docs/PLAYER_MANUAL.ja.md#09-gc)、[目的別の練習レシピ](docs/PLAYER_MANUAL.ja.md#11-drills)
- **調べる：** [Tick Data](docs/PLAYER_MANUAL.ja.md#tick-data)、[Meaty Timing](docs/PLAYER_MANUAL.ja.md#meaty-timing)、[Frame Meter](docs/PLAYER_MANUAL.ja.md#frame-meter)、[空中ガードの分析](docs/PLAYER_MANUAL.ja.md#air-guard-gaps)、[困ったとき](docs/PLAYER_MANUAL.ja.md#14-troubleshooting)

### 対応範囲

このREADMEの導入手順はWindows向けです。Linux用の起動スクリプトも同梱していますが、本フォークの全機能についてLinux／macOSで動作することは、このREADMEの作成時には確認していません。Action Patternsの名前入力・ファイル選択はWindows向けの実装です。

## 更新とバックアップ

FBNeoを終了する前に編集内容を保存し、次のファイルをバックアップしてください。

| 内容 | 保存先 |
|---|---|
| 設定・Action Steps・Action Patterns | `training_data/training_settings.json` |
| 記録 | `scripts/macro`フォルダー全体 |

設定ファイルは、`scripts`の外にある`training_data`フォルダーに置かれます。`training_data`を使う版を最初に起動すると、既存の`scripts/training_settings.json`が自動でそこへコピーされます。元のファイルは控えとしてその場に残りますが、以後は更新されません。記録は引き続き`scripts/macro`にあるため、両方をバックアップしてください。

更新はトレーニング専用の複製先へ行います。配布物に記録ファイルが含まれる場合があるため、自分の記録を不用意に上書きしないでください。更新後はFBNeoを完全に再起動し、`Video > Runahead`で`Disabled`が選ばれていることを確認します。

## 変更履歴・不具合報告

- [日本語リリースノート](docs/RELEASE_NOTES.ja.md)
- [Release notes (English)](docs/RELEASE_NOTES.md)
- [このフォークのIssues](https://github.com/vampiresavior001/VSAV_Training/issues)

不具合を報告する際は、バージョン、P1／P2キャラクター、左右配置、設定画面、再現手順を添えてください。`Video > Runahead`で`Disabled`を確認し、赤いRunaheadの警告が出た場合はその旨も添えてください。

## フォーク元・クレジット

本プロジェクトは、[VSAV_Trainingのfc2ブランチ](https://github.com/NBeing/VSAV_Training/tree/fc2)を基にしています。フォーク元にも記録・反撃設定・AGカウンター・GC受付表示があります。本フォークはそれらを土台に、動作再現の精度と振り返りの詳しさを拡張しています。[機能比較](docs/PLAYER_MANUAL.ja.md#fork-comparison)も参照してください。基盤となるトレーニングモードと、各スクリプトを作成・改善してきた貢献者、VSAVコミュニティに感謝します。

Frame Meterは、tirsod氏の[VSAV_FrameMeter](https://github.com/tirsod/VSAV_FrameMeter)から取り込みました。

<details>
<summary>フォーク元READMEのクレジット</summary>

Shoutouts to: Dammit and Jed for their wizardry, Grouflon (Stole their 3s training mode menu, and settings workflow!) and the VSAV Community.

BIGGEST SHOUTOUT to KyleW! This definitely would not have happened or continued without you.

`N-Bee`

</details>
