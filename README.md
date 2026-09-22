# CIT-Campus-3D

千葉工業大学 津田沼／新習志野キャンパス向けの「3Dマップ＆時間割ナビゲーション」アプリです．
iOS版（`CIT-Campus-3D`）と Mac版（`CIT-Campus-3D-for-mac`）があり，時間割を iCloud で端末間同期できます．

---

## iCloud 同期について

時間割（授業データ）は **SwiftData × CloudKit のプライベートデータベース**で，同じ Apple ID の端末間に自動同期されます．
共有する CloudKit コンテナは iOS版・Mac版で共通の **`iCloud.com.HR.CIT-Campus-3D`** です．

### 同期が有効になる条件（すべて必要）

1. 各端末が **同じ Apple ID で iCloud にサインイン**していること
2. **iCloud Drive がオン**になっていること（後述の注意を参照）
3. アプリに **iCloud（CloudKit）capability ＋ 同一コンテナ**が設定されていること

上記が揃った端末だけで同期されます．揃っていない端末は **その端末内のみのローカル保存**で動作します（クラッシュはしません）．

### ⚠️ リリース時の注意（ユーザー向け案内に記載する内容）

> **iCloud 同期には「iCloud Drive」をオンにしてください．**
> 端末で iCloud Drive がオフになっていると，iCloud にサインインしていても時間割は同期されず，画面のインジケータは「ローカルのみ（☁️に斜線）」のままになります．
> 設定 → 自分の名前 → iCloud →「iCloud Drive」をオンにしてください．
>
> ※ この挙動は，アプリが iCloud の利用可否判定に `ubiquityIdentityToken` を用いているためです（この値は iCloud 未サインイン・iCloud Drive オフのいずれでも無効になります）．

### 同期インジケータの見方（時間割画面・左上）

| 表示 | 意味 |
|---|---|
| スピナー＋「iCloud同期中」 | 同期処理が進行中 |
| ☁️✓（`checkmark.icloud`） | 同期有効・待機中（ツールチップに最終同期時刻） |
| ⚠️☁️（`exclamationmark.icloud`，オレンジ） | 直近の同期でエラー |
| ☁️／（`icloud.slash`） | iCloud 利用不可（未サインイン・iCloud Drive オフ等）でローカルのみ |

### 既知の制約・補足

- 現在の同期可否判定は **iCloud Drive がオンであること**に依存します（CloudKit 自体は iCloud Drive を必須としませんが，同期可否の同期的判定に `ubiquityIdentityToken` を使っているため）．より厳密にしたい場合は CloudKit アカウント状態の非同期チェックへ変更できます．
- **iOS Simulator** は既定で iCloud 未サインインのため，同期確認は実機を推奨します．
- 開発中は CloudKit の **Development 環境**にスキーマが自動作成されます．**App Store 配信時には Production へスキーマをデプロイ**する必要があります（CloudKit Console から実行）．
- iCloud が使えない・オフラインでも，アプリはローカル保存で通常どおり動作します．

---

## ビルド・セットアップ時の注意（開発者向け）

- iOS版・Mac版の **両ターゲット**に iCloud（CloudKit）capability と同一コンテナ `iCloud.com.HR.CIT-Campus-3D` を追加すること（自動署名でコンテナがポータル登録される）．
- iOS は Background Modes →「Remote notifications」を有効化（プッシュ駆動の同期のため）．
- ウィジェット拡張（iOS）は，アプリが同期したローカル（App Group）ストアを参照するだけで，ウィジェット自体に iCloud 権限は不要です．
- `Lecture` モデルは CloudKit 要件（全プロパティに既定値・ユニーク制約なし・リレーションなし）を満たしているため，モデル変更は不要です．

## CI

GitHub Actions の `iOS CI` は `main` への push、Pull Request、手動実行に対応します。
macOS 26 / Xcode 26.5 上で、アプリとウィジェットを署名なしでビルドし、
iOS 26.5 以降のシミュレータで単体テスト（学期判定を含む）を実行します。
テスト結果とビルドログは Actions の成果物として7日間保存されます。
Apple の証明書や大学のログイン情報の登録は不要です。
UIテスト・実際の出席システムへのログイン・App Storeへの配信はCIの対象外です。

学年暦の追加・修正時は `CIT-Campus-3DTests/SemesterTests.swift` の境界日テストも更新してください。
個人の時間割PDF/XLSX、作業用画像、Xcodeの個人設定はGitの管理対象外です。
