# VSAV_Training - The Warlord's Secret

See what the Warlord sees, and practice what the Warlord practices, in VSAV training mode for Fightcade 2.

[English](README.md) | 日本語

**内部フレーム（Tick）単位で相手の動きを再現し、攻めの検証と守りの練習に使える、Fightcade 2／FBNeo用トレーニングモードです。** 入力や攻防のタイミングを可視化し、成功・失敗の理由を確認しながら練習できます。

[VSAV_Trainingのfc2ブランチ](https://github.com/NBeing/VSAV_Training/tree/fc2)を基に拡張したフォークです。本書の対象は **v11.7.22.1** です。

**[ダウンロード（最新版）](https://github.com/vampiresavior001/VSAV_Training/releases/latest)** · [導入](#windowsでの導入) · [最初のAG・GC練習](#first-ag-drill) · [日本語マニュアル](docs/PLAYER_MANUAL.ja.md)

![左はAG、右はGCを練習中の画面。番号は表示の種類](docs/images/screen_map.png)

左：AGの練習画面。右：GCの練習画面。各表示の読み方は[画面の見方](docs/PLAYER_MANUAL.ja.md#screen-map)へ。

## Tick単位で、再現・練習・改善する

Tickはゲームの内部フレームです。本フォークは、この内部フレームに合わせてダミーの入力を制御します。

| ゲーム速度 | 表示フレームと内部フレームの関係 |
|---|---|
| ノーマル | 表示1フレーム＝1 Tick |
| ターボ3 | 表示3フレーム＝4 Tick |

1. **相手を再現する。** 自分では難しい操作も、Action Stepsで動作とタイミングを指定するだけで再現できます。「最速ダッシュからの最速攻撃」「中足払いキャンセル天雷破」など、達人の動きを練習相手にできます。起き上がり・ガード後・着地後には、必殺技のリバーサルだけでなく、**小技・投げによる暴れ、ジャンプ、ダッシュ**も指定できます。
2. **練習する。** 同じ攻めを繰り返させて、AG・GC・空中ガード後の割り込みを試します。
3. **結果を見て直す。** 入力が受付のどこに入ったか、どこで遅れたかを画面で確かめ、次の入力を直します。PB StatsとGC Statsで、成功率と入力時間の変化も追えます。

行動ごとの最速入力の条件は[Action Steps](docs/PLAYER_MANUAL.ja.md#06-steps)を参照してください。

## 何を調べ、練習できるか

| 目的 | 使い方 |
|---|---|
| **攻めが通る条件を調べる** | ダミーに小技・投げ・ジャンプ・ダッシュで対応させ、連係や起き攻めがそれらに勝つか検証する |
| **タイミングを変えた攻めに対応する** | 同じ攻めの始動や途中の攻撃をばらつかせ、決まったリズムに頼らずAG・GCする練習へ進む。[設定の使い分け](docs/PLAYER_MANUAL.ja.md#dummy-button-timing) |
| **セットプレイの時間を調べる** | Tick DataのAction Timelineで、起き攻めのフレーム消費や、15表示フレーム（ターボ3では20 Tick）以内に歩き投げを仕掛けられる開始距離を検証する |
| **空中ガード後の攻防を調べる** | 空中チェーンの割り込める隙間、実際の割り込みタイミング、空中ガードした時点、着地後の有利不利を確認する |

**Tick Data**は、従来の表示フレーム単位の測定で生じていたターボによる数値の揺れを抑え、発生・持続・戻り・有利不利の数え方・考え方を攻略サイトのフレームデータに合わせています。測定条件とAction Timelineの読み方は[マニュアル11章](docs/PLAYER_MANUAL.ja.md#10-data)で説明しています。

### 入力が「どうなったか」を見る

![AGの入力回数・タイミング・同時押しと練習結果を示すPB Counter／PB Stats](docs/images/pb_counter_stats.png)

この例では、受付の5～13 Tick目に6回入力してAGが成立しています。**6回入力が安定したら、入力開始を少し遅らせても6回を保てるか試します。** 足りないときは、同時押しや受付終了後の入力を確認できます。英語UIのPush Block／PBはAGを指します。詳しい読み方は[AG練習](docs/PLAYER_MANUAL.ja.md#08-pb)へ。

**技の性質をグラフィカルに見る：** [Frame Meter](docs/PLAYER_MANUAL.ja.md#frame-meter)は、通常技や必殺技の発生・攻撃判定・戻り・無敵などを色分けされた帯で表示します。数値とあわせて、色や長さで技の流れをつかみたい方に向いています。

### 手軽な記録と、精密な動作指定を使い分ける

自分で操作できる動きは、**[Recording Wizard](docs/PLAYER_MANUAL.ja.md#05-recording)**で手軽に記録できます。操作の開始から終了までを自動で記録し、確認して保存できます。

**記録・再生は表示フレーム単位です。** 自分では難しい操作や、Tick単位の正確なタイミングはAction Stepsで定義してください。

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

配置先は、空白や日本語を含まない短いパスを使用してください。既存環境を更新する場合は、先に[バックアップ](#更新とバックアップ)を行います。

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

## マニュアル

**[日本語プレイヤーマニュアル](docs/PLAYER_MANUAL.ja.md)** に、操作・設定・表示の読み方をまとめています。

- **相手を作る：** [ダミーのガード・受け身・反撃](docs/PLAYER_MANUAL.ja.md#04-dummy)、[記録とループ再生](docs/PLAYER_MANUAL.ja.md#05-recording)、[Action Steps](docs/PLAYER_MANUAL.ja.md#06-steps)、[Action Patterns](docs/PLAYER_MANUAL.ja.md#07-patterns)
- **練習する：** [AG練習](docs/PLAYER_MANUAL.ja.md#08-pb)、[GC練習](docs/PLAYER_MANUAL.ja.md#09-gc)、[目的別の練習レシピ](docs/PLAYER_MANUAL.ja.md#11-drills)
- **調べる：** [Tick Data・空中ガードの分析](docs/PLAYER_MANUAL.ja.md#10-data)、[困ったとき](docs/PLAYER_MANUAL.ja.md#14-troubleshooting)

### 対応範囲

このREADMEの導入手順はWindows向けです。Linux用の起動スクリプトも同梱していますが、本フォークの全機能についてLinux／macOSで動作することは、このREADMEの作成時には確認していません。Action Patternsの名前入力・ファイル選択はWindows向けの実装です。

時間表示には、内部フレームを使うものと表示フレームを使うものがあります。ダッシュ系の既存トレーナーなども含め、すべての表示がTickに統一されているわけではありません。単位は[マニュアル](docs/PLAYER_MANUAL.ja.md#10-data)を確認してください。

## 更新とバックアップ

FBNeoを終了する前に編集内容を保存し、次のファイルをバックアップしてください。

| 内容 | 保存先 |
|---|---|
| 設定・Action Steps・Action Patterns | `scripts/training_settings.json` |
| 記録 | `scripts/macro`フォルダー全体 |

更新はトレーニング専用の複製先へ行います。配布物に記録ファイルが含まれる場合があるため、自分の記録を不用意に上書きしないでください。更新後はFBNeoを完全に再起動し、`Video > Runahead`で`Disabled`が選ばれていることを確認します。

## 変更履歴・不具合報告

- [日本語リリースノート](docs/RELEASE_NOTES.ja.md)
- [Release notes (English)](docs/RELEASE_NOTES.md)
- [このフォークのIssues](https://github.com/vampiresavior001/VSAV_Training/issues)

不具合を報告する際は、バージョン、P1／P2キャラクター、左右配置、設定画面、再現手順を添えてください。`Video > Runahead`で`Disabled`を確認し、赤いRunaheadの警告が出た場合はその旨も添えてください。

## フォーク元・クレジット

本プロジェクトは、[VSAV_Trainingのfc2ブランチ](https://github.com/NBeing/VSAV_Training/tree/fc2)を基にしています。フォーク元にも記録・反撃設定・AGカウンター・GC受付表示があります。本フォークはそれらを土台に、動作再現の精度と振り返りの詳しさを拡張しています。[機能比較](docs/PLAYER_MANUAL.ja.md)も参照してください。基盤となるトレーニングモードと、各スクリプトを作成・改善してきた貢献者、VSAVコミュニティに感謝します。

Frame Meterは、tirsod氏の[VSAV_FrameMeter](https://github.com/tirsod/VSAV_FrameMeter)から取り込みました。

<details>
<summary>フォーク元READMEのクレジット</summary>

Shoutouts to: Dammit and Jed for their wizardry, Grouflon (Stole their 3s training mode menu, and settings workflow!) and the VSAV Community.

BIGGEST SHOUTOUT to KyleW! This definitely would not have happened or continued without you.

`N-Bee`

</details>
