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

/// 時間割一覧画面
struct TimetableListView: View {

  /// インポートセッション（シート表示用のラッパ）
  private struct ImportSession: Identifiable {
    let id = UUID()
    let drafts: [LectureDraft]
  }

  @Environment(\.modelContext) private var modelContext

  /// 全授業（曜日→時限の順でソート）
  @Query(sort: [
    SortDescriptor(\Lecture.weekdayRawValue),
    SortDescriptor(\Lecture.period),
  ])
  private var lectures: [Lecture]

  /// 表示中の学期（初期値は現在の学期）
  @State private var selectedSemester: Semester = .current(on: Date())

  /// ファイル選択ダイアログの表示フラグ
  @State private var isShowingFileImporter = false

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
        Group {
          if filteredLectures.isEmpty {
            emptyStateView
          } else {
            timetableList
          }
        }
      }
      .navigationTitle("時間割")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isShowingFileImporter = true
          } label: {
            Image(systemName: "square.and.arrow.down")
          }
          .accessibilityLabel("ファイルからインポート")
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
      .alert(errorTitle, isPresented: $isShowingErrorAlert) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage)
      }
    }
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
      Text("右上の取り込みボタンから，ポータルでダウンロードした学生時間割表（.xlsx / .pdf）を読み込めます．＋ボタンで1件ずつの手動追加もできます．")
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
    } catch {
      showError(title: "削除に失敗しました", message: error.localizedDescription)
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

#Preview {
  TimetableListView()
    .modelContainer(for: Lecture.self, inMemory: true)
    .preferredColorScheme(.dark)
}
