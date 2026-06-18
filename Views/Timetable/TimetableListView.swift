//
//  TimetableListView.swift
//  CIT-Campus-3D
//
//  登録済みの時間割を学期・曜日ごとに一覧表示する画面．
//  ポータルのファイル（.xlsx/.pdf）からの一括インポート，
//  手動追加（＋ボタン），スワイプ削除に対応する．
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// 時間割の表示形式
private enum TimetableLayout: String {
  /// 曜日ごとのリスト表示（科目・時限・場所・教員を縦に並べる）
  case list
  /// 曜日×時限の表（グリッド）表示
  case grid
}

/// 時間割一覧画面
struct TimetableListView: View {

  /// インポートセッション（シート表示用のラッパ）
  private struct ImportSession: Identifiable {
    let id = UUID()
    let drafts: [LectureDraft]
  }

  /// 一括削除の対象範囲
  private enum DeleteScope {
    /// 表示中の学期のみ
    case currentSemester
    /// すべての学期
    case all
  }

  @Environment(\.modelContext) private var modelContext

  /// 全授業（曜日→時限の順でソート）
  @Query(sort: [
    SortDescriptor(\Lecture.weekdayRawValue),
    SortDescriptor(\Lecture.period),
  ])
  private var lectures: [Lecture]

  /// 全課題（締切の早い順）
  @Query(sort: \Assignment.dueDate)
  private var assignments: [Assignment]

  /// 表示中の学期（初期値は現在の学期）
  @State private var selectedSemester: Semester = .current(on: Date())

  /// 時間割の表示形式（リスト／表．端末に記憶する）
  @AppStorage("timetableLayout") private var layout: TimetableLayout = .grid

  /// ファイル選択ダイアログの表示フラグ
  @State private var isShowingFileImporter = false

  /// ポータル取り込み画面の表示フラグ
  @State private var isShowingPortalImport = false

  /// ポータル画面を閉じた後にファイル選択を開くか（ポータル画面でファイル取込が選ばれた時）
  @State private var shouldOpenFileImporterAfterPortal = false

  /// 一括削除の確認対象（非nilで確認ダイアログを表示）
  @State private var deleteScope: DeleteScope?

  /// 解析済みのインポートセッション（非nilでプレビューを表示）
  @State private var importSession: ImportSession?

  /// 追加フォームの表示フラグ
  @State private var isShowingAddSheet = false

  /// エラーアラートの表示フラグ
  @State private var isShowingErrorAlert = false

  /// エラーアラートのタイトル
  @State private var errorTitle = ""

  /// エラーアラートのメッセージ
  @State private var errorMessage = ""

  /// 選択中の学期の授業
  private var filteredLectures: [Lecture] {
    lectures.filter { $0.semester == selectedSemester }
  }

  /// 未完了の課題
  private var activeAssignments: [Assignment] {
    assignments.filter { !$0.isDone }
  }

  /// 締切が未来の未完了課題（締切の早い順）
  private var upcomingAssignments: [Assignment] {
    activeAssignments
      .filter { assignment in
        guard let due = assignment.dueDate else { return false }
        return due >= Date()
      }
      .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
  }

  /// 曜日ごとにグループ化した時間割（授業がない曜日は除外）
  private var lecturesByWeekday: [(weekday: Weekday, lectures: [Lecture])] {
    Weekday.lectureDays.compactMap { day in
      let dayLectures = filteredLectures.filter { $0.weekday == day }
      return dayLectures.isEmpty ? nil : (day, dayLectures)
    }
  }

  /// インポートで受け付けるファイル形式（.xlsxと.pdf）
  private var allowedContentTypes: [UTType] {
    var types: [UTType] = [.pdf]
    if let xlsxType = UTType(filenameExtension: "xlsx") {
      types.append(xlsxType)
    }
    return types
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        semesterPicker
        if !activeAssignments.isEmpty {
          assignmentSummary
        }
        Group {
          if filteredLectures.isEmpty {
            emptyStateView
          } else {
            switch layout {
            case .list:
              timetableList
            case .grid:
              timetableGrid
            }
          }
        }
      }
      .navigationTitle("時間割")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloudSyncIndicator()
        }
        ToolbarItem(placement: .topBarLeading) {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              layout = (layout == .list) ? .grid : .list
            }
          } label: {
            // 切り替え先の形式を表すアイコンを出す
            Image(systemName: layout == .list ? "tablecells" : "list.bullet")
          }
          .accessibilityLabel(layout == .list ? "表形式で表示" : "リスト形式で表示")
        }
        if !lectures.isEmpty {
          ToolbarItem(placement: .topBarLeading) {
            Menu {
              Button(role: .destructive) {
                deleteScope = .currentSemester
              } label: {
                Label("\(selectedSemester.displayName)を削除", systemImage: "trash")
              }
              Button(role: .destructive) {
                deleteScope = .all
              } label: {
                Label("すべて削除", systemImage: "trash")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("一括削除")
          }
        }
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink {
            AssignmentListView()
          } label: {
            Image(systemName: "list.clipboard")
          }
          .accessibilityLabel("課題")
        }
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink {
            ClassChangeListView()
          } label: {
            Image(systemName: "calendar.badge.exclamationmark")
          }
          .accessibilityLabel("休講・補講")
        }
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              isShowingPortalImport = true
            } label: {
              Label("ポータルから取り込む", systemImage: "globe")
            }
            Button {
              isShowingFileImporter = true
            } label: {
              Label("ファイルから取り込む（Excel / PDF）", systemImage: "doc")
            }
          } label: {
            Image(systemName: "square.and.arrow.down")
          }
          .accessibilityLabel("時間割を取り込む")
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            isShowingAddSheet = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("授業を追加")
        }
      }
      .fileImporter(
        isPresented: $isShowingFileImporter,
        allowedContentTypes: allowedContentTypes,
        allowsMultipleSelection: false
      ) { result in
        handleFileImport(result)
      }
      .sheet(item: $importSession) { session in
        ImportPreviewView(drafts: session.drafts) { drafts, replaceExisting in
          saveImportedDrafts(drafts, replaceExisting: replaceExisting)
        }
      }
      .sheet(isPresented: $isShowingAddSheet) {
        AddLectureView()
      }
      .fullScreenCover(isPresented: $isShowingPortalImport, onDismiss: {
        // ポータル画面で「ファイルから取り込む」が選ばれていたら，閉じた後にファイル選択を開く
        if shouldOpenFileImporterAfterPortal {
          shouldOpenFileImporterAfterPortal = false
          isShowingFileImporter = true
        }
      }) {
        PortalImportView(
          onSave: { drafts, replaceExisting in
            saveImportedDrafts(drafts, replaceExisting: replaceExisting)
          },
          onUseFileImport: {
            shouldOpenFileImporterAfterPortal = true
          }
        )
      }
      .alert(errorTitle, isPresented: $isShowingErrorAlert) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage)
      }
      .confirmationDialog(
        "時間割を削除",
        isPresented: Binding(
          get: { deleteScope != nil },
          set: { if !$0 { deleteScope = nil } }
        ),
        titleVisibility: .visible,
        presenting: deleteScope
      ) { scope in
        Button(deleteButtonLabel(for: scope), role: .destructive) {
          performBulkDelete(scope)
        }
        Button("キャンセル", role: .cancel) { deleteScope = nil }
      } message: { scope in
        Text(deleteMessage(for: scope))
      }
    }
  }

  // MARK: - 課題サマリ（時間割画面に統合）

  /// 締切表示用フォーマッタ
  private static let assignmentDueFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d HH:mm"
    return formatter
  }()

  /// 課題の件数と最短締切を示し，課題一覧へ遷移するカード
  private var assignmentSummary: some View {
    NavigationLink {
      AssignmentListView()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "list.clipboard")
          .font(.title3)
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text("未提出の課題 \(activeAssignments.count)件")
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
          if let next = upcomingAssignments.first, let due = next.dueDate {
            Text("最短締切 \(Self.assignmentDueFormatter.string(from: due))・\(next.title)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          } else {
            Text("締切が近い課題はありません")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.accentColor.opacity(0.12))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal)
    .padding(.bottom, 8)
  }

  // MARK: - 学期切り替え

  private var semesterPicker: some View {
    Picker("学期", selection: $selectedSemester) {
      ForEach(Semester.allCases) { semester in
        Text(semester.displayName).tag(semester)
      }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal)
    .padding(.bottom, 8)
  }

  // MARK: - 空状態（インポートへの導線）

  private var emptyStateView: some View {
    ContentUnavailableView {
      Label("\(selectedSemester.displayName)の時間割が未登録です", systemImage: "calendar.badge.plus")
    } description: {
      Text("右上の取り込みボタンから，大学ポータルに直接ログインして取り込むか，ポータルでダウンロードした学生時間割表（.xlsx / .pdf）を読み込めます．＋ボタンで1件ずつの手動追加もできます．")
    }
  }

  // MARK: - 一覧本体

  private var timetableList: some View {
    List {
      ForEach(lecturesByWeekday, id: \.weekday) { group in
        Section("\(group.weekday.shortName)曜日") {
          ForEach(group.lectures) { lecture in
            LectureRow(lecture: lecture)
          }
          .onDelete { offsets in
            deleteLectures(group.lectures, at: offsets)
          }
        }
      }
    }
  }

  // MARK: - 表形式（曜日×時限のグリッド）

  private var timetableGrid: some View {
    TimetableGrid(lectures: filteredLectures) { lecture in
      deleteLecture(lecture)
    }
  }

  // MARK: - Private

  /// ファイル選択の結果を受け取り，解析してプレビューへ進む
  private func handleFileImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      do {
        let drafts = try TimetableImporter().importTimetable(from: url)
        importSession = ImportSession(drafts: drafts)
      } catch {
        showError(title: "インポートに失敗しました", message: error.localizedDescription)
      }
    case .failure(let error):
      showError(title: "ファイルを選択できませんでした", message: error.localizedDescription)
    }
  }

  /// プレビューで確認済みのドラフトをSwiftDataへ保存する
  private func saveImportedDrafts(_ drafts: [LectureDraft], replaceExisting: Bool) {
    if replaceExisting {
      for lecture in lectures {
        modelContext.delete(lecture)
      }
    }
    for draft in drafts {
      modelContext.insert(draft.makeLecture())
    }
    do {
      try modelContext.save()
      // 時間割が変わったのでホーム／ロック画面のウィジェットを更新する
      WidgetCenter.shared.reloadAllTimelines()
      // インポートした学期を表示する（前期があれば前期を優先）
      if let firstSemester = drafts.map(\.semester).min(by: { $0.rawValue < $1.rawValue }) {
        selectedSemester = firstSemester
      }
    } catch {
      showError(title: "保存に失敗しました", message: error.localizedDescription)
    }
  }

  /// 指定された授業を削除し，保存失敗時はアラートを表示する
  private func deleteLectures(_ groupLectures: [Lecture], at offsets: IndexSet) {
    for index in offsets {
      modelContext.delete(groupLectures[index])
    }
    do {
      try modelContext.save()
      // 時間割が変わったのでホーム／ロック画面のウィジェットを更新する
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      showError(title: "削除に失敗しました", message: error.localizedDescription)
    }
  }

  /// 授業を1件削除し，保存失敗時はアラートを表示する（表形式のセルから呼ばれる）
  private func deleteLecture(_ lecture: Lecture) {
    modelContext.delete(lecture)
    do {
      try modelContext.save()
      // 時間割が変わったのでホーム／ロック画面のウィジェットを更新する
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      showError(title: "削除に失敗しました", message: error.localizedDescription)
    }
  }

  /// 指定範囲の授業を一括削除する
  private func performBulkDelete(_ scope: DeleteScope) {
    let targets: [Lecture]
    switch scope {
    case .currentSemester:
      targets = filteredLectures
    case .all:
      targets = lectures
    }
    for lecture in targets {
      modelContext.delete(lecture)
    }
    do {
      try modelContext.save()
      // 時間割が変わったのでホーム／ロック画面のウィジェットを更新する
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      showError(title: "削除に失敗しました", message: error.localizedDescription)
    }
    deleteScope = nil
  }

  /// 一括削除の確認ボタンの文言（対象コマ数つき）
  private func deleteButtonLabel(for scope: DeleteScope) -> String {
    switch scope {
    case .currentSemester:
      return "\(selectedSemester.displayName)を削除（\(filteredLectures.count)コマ）"
    case .all:
      return "すべて削除（\(lectures.count)コマ）"
    }
  }

  /// 一括削除の確認メッセージ
  private func deleteMessage(for scope: DeleteScope) -> String {
    switch scope {
    case .currentSemester:
      return "\(selectedSemester.displayName)の\(filteredLectures.count)コマを削除します．この操作は取り消せません．"
    case .all:
      return "登録されている全\(lectures.count)コマを削除します．この操作は取り消せません．"
    }
  }

  /// エラーアラートを表示する
  private func showError(title: String, message: String) {
    errorTitle = title
    errorMessage = message
    isShowingErrorAlert = true
  }
}

/// 時間割一覧の1行（科目名・時限・場所・教員）
struct LectureRow: View {

  let lecture: Lecture

  /// 時限の表示文字列（例: 2限 10:00〜11:00）
  private var periodText: String {
    guard let classPeriod = lecture.classPeriod else {
      return "\(lecture.period)限"
    }
    return "\(classPeriod.displayName) \(classPeriod.timeRangeText)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(lecture.subjectName)
        .font(.headline)

      HStack(spacing: 12) {
        Label(periodText, systemImage: "clock")
        Label(lecture.placeText, systemImage: "building.2")
        if !lecture.teacherName.isEmpty {
          Label(lecture.teacherName, systemImage: "person")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

/// 時間割を「曜日×時限」の表（グリッド）で表示するビュー
struct TimetableGrid: View {

  /// 表示する授業（学期で絞り込み済み）
  let lectures: [Lecture]
  /// セルから授業を削除するときのコールバック
  let onDelete: (Lecture) -> Void

  /// 表のレイアウトに関する定数
  private enum GridConstants {
    /// 時限ラベル列の幅
    static let periodColumnWidth: CGFloat = 40
    /// 各セルの最小の高さ
    static let cellMinHeight: CGFloat = 56
    /// セルの角丸半径
    static let cornerRadius: CGFloat = 8
    /// 実際のコマ数が少なくても最低限表示する時限数（一般的な時間割の見た目に合わせる）
    static let minimumVisiblePeriods = 5
  }

  /// 削除確認の対象（非nilでダイアログを表示）
  @State private var lectureToDelete: Lecture?

  /// 表に並べる曜日（月〜金）
  private let days = Weekday.lectureDays

  /// 表に並べる時限（1限〜実際に使われている最大時限．最低 minimumVisiblePeriods 行は出す）
  private var periods: [ClassPeriod] {
    let maxUsed = lectures.map(\.period).max() ?? 0
    let upperBound = max(GridConstants.minimumVisiblePeriods, maxUsed)
    return ClassPeriod.allPeriods.filter { $0.number <= upperBound }
  }

  var body: some View {
    ScrollView {
      Grid(horizontalSpacing: 4, verticalSpacing: 4) {
        headerRow
        ForEach(periods) { period in
          GridRow {
            periodLabel(period)
            ForEach(days) { day in
              cell(day: day, period: period.number)
            }
          }
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 12)
    }
    .confirmationDialog(
      lectureToDelete?.subjectName ?? "",
      isPresented: Binding(
        get: { lectureToDelete != nil },
        set: { if !$0 { lectureToDelete = nil } }
      ),
      titleVisibility: .visible,
      presenting: lectureToDelete
    ) { lecture in
      Button("この授業を削除", role: .destructive) {
        onDelete(lecture)
      }
      Button("キャンセル", role: .cancel) {}
    } message: { lecture in
      Text(lecture.placeText)
    }
  }

  // MARK: - 部品

  /// ヘッダ行（左上の空セル＋曜日名）
  private var headerRow: some View {
    GridRow {
      Color.clear
        .frame(width: GridConstants.periodColumnWidth, height: 1)
      ForEach(days) { day in
        Text(day.shortName)
          .font(.subheadline.bold())
          .frame(maxWidth: .infinity)
      }
    }
  }

  /// 時限ラベル（番号＋開始時刻）
  private func periodLabel(_ period: ClassPeriod) -> some View {
    VStack(spacing: 2) {
      Text("\(period.number)")
        .font(.subheadline.bold())
      Text(String(format: "%d:%02d", period.startHour, period.startMinute))
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
    .frame(width: GridConstants.periodColumnWidth)
    .frame(minHeight: GridConstants.cellMinHeight)
  }

  /// 1セル（該当する授業があればカード，なければ空欄）
  @ViewBuilder
  private func cell(day: Weekday, period: Int) -> some View {
    let cellLectures = lectures.filter { $0.weekday == day && $0.period == period }
    if let lecture = cellLectures.first {
      Button {
        lectureToDelete = lecture
      } label: {
        VStack(spacing: 2) {
          Text(lecture.subjectName)
            .font(.caption2.bold())
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
          if !lecture.roomNumber.isEmpty {
            Text(lecture.roomNumber)
              .font(.system(size: 9))
              .foregroundStyle(.secondary)
          }
          // 同じコマに複数登録がある場合の件数表示
          if cellLectures.count > 1 {
            Text("他\(cellLectures.count - 1)件")
              .font(.system(size: 8))
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, minHeight: GridConstants.cellMinHeight)
        .padding(4)
        .background(
          RoundedRectangle(cornerRadius: GridConstants.cornerRadius)
            .fill(Color.accentColor.opacity(0.18))
        )
      }
      .buttonStyle(.plain)
    } else {
      RoundedRectangle(cornerRadius: GridConstants.cornerRadius)
        .fill(Color.gray.opacity(0.1))
        .frame(maxWidth: .infinity, minHeight: GridConstants.cellMinHeight)
    }
  }
}

#Preview {
  TimetableListView()
    .modelContainer(for: [Lecture.self, Assignment.self], inMemory: true)
    .preferredColorScheme(.dark)
}
