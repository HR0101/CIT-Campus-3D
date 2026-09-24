import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// OCRの結果は必ず編集可能なプレビューを経てから登録する．
struct ScreenshotImportView: View {
  let onSave: ([LectureDraft], Bool) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var photo: PhotosPickerItem?
  @State private var isChoosingFile = false
  @State private var isReading = false
  @State private var errorMessage: String?
  @State private var imageData: Data?
  @State private var semester = Semester.current(on: Date())
  @State private var entries: [ScreenshotLectureEntry] = []
  @State private var replaceExisting = false
  @State private var readingTask: Task<Void, Never>?

  private var hasConflicts: Bool {
    Set(entries.map { "\($0.weekday.rawValue)-\($0.period)" }).count != entries.count
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          PhotosPicker(selection: $photo, matching: .images) {
            Text("写真からスクショを選ぶ")
          }
          Button("ファイルから画像を選ぶ") { isChoosingFile = true }
        } footer: {
          Text("ポータルの曜日見出しと1〜10限の表全体が写るスクショを選んでください。画像は端末内で読み取ります。")
        }
        .disabled(isReading)
        if isReading {
          Section { ProgressView("時間割を読み取り中…") }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(.red) }
        }
        if let imageData, let image = UIImage(data: imageData) {
          DisclosureGroup("元のスクショを確認") {
            Image(uiImage: image).resizable().scaledToFit()
          }
        }
        if !entries.isEmpty {
          Section {
            Picker("登録する学期", selection: $semester) {
              ForEach(Semester.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle("この学期の時間割を置き換える", isOn: $replaceExisting)
          } footer: {
            Text("読み取り漏れや誤認識がある場合があります。学期を確認し、各授業をタップして修正してください。置き換えがオフの場合は追加します。他の学期は変更しません。集中講義は自動取り込みの対象外です。")
          }
          Section("読み取った授業（\(entries.count)コマ）") {
            ForEach($entries) { $entry in
              NavigationLink {
                ScreenshotLectureEditor(entry: $entry)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text("\(entry.weekday.shortName)曜・\(entry.period)限　\(entry.subject.isEmpty ? "科目名を入力" : entry.subject)")
                  Text("\(entry.campus.displayName)・\(entry.room.isEmpty ? "教室未確認" : entry.room + "教室")　\(entry.teacher)")
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
            }
            .onDelete { entries.remove(atOffsets: $0) }
            Button("読み取り漏れの授業を追加") {
              entries.append(ScreenshotLectureEntry(cell: .init(weekday: 2, period: 1, lines: [])))
            }
          }
          if hasConflicts {
            Text("同じ曜日・時限が重複しています。授業を修正または削除してください。")
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("スクショから取り込む")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { readingTask?.cancel(); dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("登録") {
            onSave(entries.map { $0.draft(semester: semester) }, replaceExisting)
            dismiss()
          }
          .disabled(isReading || entries.isEmpty || hasConflicts || entries.contains { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
      }
      .onChange(of: photo) { _, item in
        guard let item else { return }
        startReading {
          guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ScreenshotTimetableParser.Failure.image
          }
          return data
        }
      }
      .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image]) { result in
        switch result {
        case .success(let url):
          startReading {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
          }
        case .failure(let error): errorMessage = error.localizedDescription
        }
      }
      .onDisappear { readingTask?.cancel() }
    }
  }

  private func startReading(load: @escaping () async throws -> Data) {
    readingTask?.cancel()
    isReading = true
    errorMessage = nil
    entries = []
    readingTask = Task {
      defer { isReading = false }
      do {
        let data = try await load()
        guard !Task.isCancelled else { return }
        imageData = data
        let worker = Task.detached(priority: .userInitiated) {
          try ScreenshotTimetableParser().parse(data: data)
        }
        let result = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        guard !Task.isCancelled else { return }
        semester = result.semester.flatMap(Semester.init(rawValue:)) ?? semester
        entries = result.cells.map { ScreenshotLectureEntry(cell: $0) }
      } catch {
        guard !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
      }
    }
  }
}

struct ScreenshotLectureEntry: Identifiable {
  let id = UUID()
  var weekday: Weekday
  var period: Int
  var subject: String
  var teacher: String
  var room: String
  var campus: Campus

  init(cell: ScreenshotTimetableParser.Cell) {
    weekday = Weekday(rawValue: cell.weekday) ?? .monday
    period = cell.period
    let lines = cell.lines.map {
      String($0.map { character in
        if let number = character.wholeNumberValue, (0...9).contains(number) {
          return Character(String(number))
        }
        return character
      })
    }.map {
      $0.replacingOccurrences(of: "(?<=\\d)\\s+(?=\\d|講義室)", with: "", options: .regularExpression)
    }
    let normalizedLines = lines.map {
      $0.replacingOccurrences(of: "情エ(?=\\s*[1-4]年)", with: "情工", options: .regularExpression)
    }
    let parsed = LectureCellParser.parse(lines: normalizedLines)
    subject = parsed?.subjectName ?? lines.first ?? ""
    teacher = parsed?.teacherName ?? ""
    room = parsed?.roomNumber ?? ""
    campus = parsed?.campus ?? .tsudanuma
  }

  func draft(semester: Semester) -> LectureDraft {
    let room = room.trimmingCharacters(in: .whitespacesAndNewlines)
    return LectureDraft(semester: semester, weekday: weekday, period: period,
      subjectName: subject.trimmingCharacters(in: .whitespacesAndNewlines),
      teacherName: teacher.trimmingCharacters(in: .whitespacesAndNewlines), campus: campus,
      buildingName: CampusBuilding.building(forRoomNumber: room, campus: campus)?.name ?? "",
      roomNumber: room)
  }
}

private struct ScreenshotLectureEditor: View {
  @Binding var entry: ScreenshotLectureEntry
  var body: some View {
    Form {
      TextField("科目名", text: $entry.subject)
      TextField("教員名", text: $entry.teacher)
      Picker("曜日", selection: $entry.weekday) {
        ForEach(Weekday.allCases.filter { $0 != .sunday }) { Text("\($0.shortName)曜日").tag($0) }
      }
      Picker("時限", selection: $entry.period) {
        ForEach(1...10, id: \.self) { Text("\($0)限").tag($0) }
      }
      Picker("キャンパス", selection: $entry.campus) {
        ForEach(Campus.allCases) { Text($0.displayName).tag($0) }
      }
      TextField("教室番号", text: $entry.room)
    }
    .navigationTitle("読み取り内容を修正")
    .navigationBarTitleDisplayMode(.inline)
  }
}
