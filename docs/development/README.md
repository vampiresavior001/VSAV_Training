# Development documents / 開発資料

Design notes, investigation results and handoffs are collected here. File names are unchanged. Paths used in commands and investigation records are relative to the repository root unless stated otherwise.

設計書・調査メモ・引継ぎ資料をまとめています。ファイル名は維持しています。文中のコマンドや調査記録のパスは、特記のない限りリポジトリのルートを基準とします。過去の経緯を含むため、現在の操作方法はプレイヤーマニュアルを参照してください。

| Document / 資料 | Contents / 内容 |
|---|---|
| [Project instructions](CLAUDE.md) | 開発の規約・テストの回し方・公開手順。開発再開時の入口。Claude Code がルートの `CLAUDE.md` から読み込む |
| [VSAV investigation handoff](handoff_VSAV_investigation.md) | ゲーム調査の引継ぎ |
| [Memory notes](VSAV_MEMORY_NOTES.md) | ゲーム側の解析・測定結果 |
| [Action Pattern Library](design_action_pattern_library.md) | アクションパターンの設計 |
| [Landing prediction](design_landing_prediction.md) | 着地予測の調査と設計 |
| [PB scoring](design_pb_score.md) | AG採点の再設計案（保留） |
| [Frame Meter](design_frame_meter.md) | Frame Meterの記録と表示の作り、リバーサルフレームの根拠 |
| [v11.3.2 changes](VSAV_TRAINING_v11.3.2_CHANGES.md) | 旧版の変更記録 |
| [v11.3.2 wake-up reversal behavior](wakeup_reversal_behavior_v11.3.2.md) | 旧版の起き上がり・リバーサル仕様 |

This folder is not part of the release zip: the zip is for players, and development documents live on GitHub only. / このフォルダは配布zipに含めません。zipは配布用で、開発資料はGitHub上だけに置きます。

Analysis tools and their accompanying investigation documents remain in [analysis/](../../analysis/). / 解析ツールと付属の調査資料は引き続き`analysis/`にあります。

[English player manual](../PLAYER_MANUAL.en.md) · [日本語プレイヤーマニュアル](../PLAYER_MANUAL.ja.md) · [Project instructions](CLAUDE.md)
