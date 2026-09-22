# ウィジェット導入手順（Xcode 側の数クリック）

時間割ウィジェットのコードは `CITWidget/` にすべて用意済みです．
Xcode で **Widget Extension ターゲット** を作って，下記のファイルを取り込めば完成します．

所要は5ステップ・5〜10分ほどです．

---

## 0. 前提

- 共有コア（`Lecture` ほか）と App Group ストア化はコード側で対応済みです．
- App Group の識別子は **`group.com.HR.CIT-Campus-3D`** を使います．

---

## 1. Widget Extension ターゲットを作る

1. Xcode で `File > New > Target…` を開く．
2. iOS の **Widget Extension** を選び `Next`．
3. **Product Name** を **`CITWidget`** にする．
   - `Include Live Activity` は **チェックを外す**．
   - 「Include Configuration App Intent」が出たら **チェックを外す**（設定不要の静的ウィジェットのため）．
4. `Finish`．スキームの有効化を聞かれたら `Activate`．

> すでに `CITWidget/` フォルダが存在するため，Xcode は同じフォルダにサンプルを生成します．次のステップで不要分を消します．

## 2. Xcode が生成したサンプルを削除する

`CITWidget` グループ内に Xcode が作った **`.swift` サンプル**（例: `CITWidget.swift`／`CITWidgetBundle.swift`／`CITWidgetControl.swift`／`CITWidgetLiveActivity.swift`／`AppIntent.swift` など，存在するもの）を選んで **Move to Trash** で削除します．

- 残すもの: `Info.plist`，`Assets.xcassets`（あれば）．
- 実装ファイル（`TT*.swift`）はこのフォルダに既にあります．削除した `@main` の代わりに **`TTWidgetBundle.swift`** が `@main` になります．
- `TT*.swift` がグループに見当たらない場合は，フォルダ同期で自動的に現れます（数秒待つ／プロジェクトを開き直す）．

## 3. 共有コアをウィジェットターゲットにも所属させる

下記 **8ファイル** を選択（⌘クリックで複数選択）し，右の File Inspector → **Target Membership** で **`CITWidget` にチェック**を入れます（`CIT-Campus-3D` のチェックは付けたまま）．

```
CIT-Campus-3D/Models/Lecture.swift
CIT-Campus-3D/Models/Semester.swift
CIT-Campus-3D/Models/Weekday.swift
CIT-Campus-3D/Models/Campus.swift
CIT-Campus-3D/Models/ClassPeriod.swift
CIT-Campus-3D/Models/AcademicCalendar.swift
CIT-Campus-3D/Services/NextLectureResolver.swift
CIT-Campus-3D/Services/SharedModelContainer.swift
```

> **重要**: `Models/Lecture+CampusBuilding.swift` は **チェックを入れない**でください．
> これはマップ用（CampusBuilding／GeoJSON 依存）でアプリ専用です．ウィジェットには不要です．

## 4. App Groups を両ターゲットに追加する

`CIT-Campus-3D` と `CITWidget` の **両方**で，`Signing & Capabilities` タブを開き：

1. `+ Capability` → **App Groups** を追加．
2. `+` で **`group.com.HR.CIT-Campus-3D`** を追加（両ターゲットで**同じ**グループを選ぶ）．

> これでアプリとウィジェットが同じ SwiftData ストアを共有します（自動署名がポータルにも登録します）．

## 5. ウィジェットターゲットのビルド設定を合わせる

`CITWidget` ターゲット → `Build Settings` で：

- **Default Actor Isolation** を **`nonisolated`** にする
  （ウィジェットのタイムライン処理をバックグラウンドで動かすため．アプリ本体は `MainActor` のままで OK）．
- **Swift Language Version** を **Swift 5** にする（アプリ本体と揃える）．

---

## 6. ビルドして配置する

1. スキームを `CITWidget` ではなく **`CIT-Campus-3D`**（アプリ本体）に戻してビルド・実行．
2. 一度アプリを起動すると，旧データが App Group ストアへ移行されます（時間割はそのまま見えます）．
3. ホーム画面長押し → `+` → 「CIT-Campus-3D」を検索し，**小・中・大** のいずれかを追加．
4. ロック画面（壁紙編集 → ウィジェット追加）で **「次の授業」** を配置（インライン／長方形／円形）．

---

## ウィジェットの内容

| サイズ | 表示 |
|---|---|
| 小（systemSmall） | 今日の進行中／次の授業（科目・時限・時間・場所） |
| 中（systemMedium） | 今日の時間割リスト（進行中をハイライト，終了済みは淡色） |
| 大（systemLarge） | 週間グリッド（曜日×時限，当日列をハイライト） |
| ロック画面（accessory） | 次の授業（インライン／長方形／円形） |

## データ更新

時間割をインポート／追加／削除すると，アプリが `WidgetCenter.reloadAllTimelines()` を呼ぶため，ウィジェットは自動更新されます．授業の進行に合わせて毎正時にも更新されます．

## トラブルシューティング

- **「Cannot find type 'Lecture'」等でビルド失敗** → ステップ3の Target Membership（8ファイル）が漏れていないか確認．
- **ウィジェットが空／"読み込めません"** → ステップ4の App Group が両ターゲットで同一か，アプリを一度起動したか確認．
- **`@main` が重複** → ステップ2で Xcode 生成の `*Bundle.swift` を消し忘れていないか確認（`TTWidgetBundle.swift` だけが `@main`）．
