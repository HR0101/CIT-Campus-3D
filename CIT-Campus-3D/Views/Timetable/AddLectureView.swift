//
//  AddLectureView.swift
//  CIT-Campus-3D
//
//  授業を手動で1件ずつ追加するフォーム．
//  ファイルインポート失敗時の最終フォールバックとしても機能する．
//

import SwiftData
import SwiftUI
import WidgetKit

/// 授業の手動追加フォーム
struct AddLectureView: View {

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  /// 選択中の学期（初期値は現在の学期）
  @State private var semester: Semester = .current(on: Date())

  /// 選択中の曜日
  @State private var weekday: Weekday = .monday

  /// 選択中の時限番号
  @State private var periodNumber = 1

  /// 科目名の入力値
  @State private var subjectName = ""

  /// 教員名の入力値
  @State private var teacherName = ""

  /// 選択中のキャンパス
  @State private var campus: Campus = .tsudanuma

  /// 選択中の講義棟名（空文字は未定）
  @State private var buildingName = CampusBuilding.tsudanumaBuildings.first?.name ?? ""

  /// 選択中のキャンパスの建物一覧
  private var campusBuildings: [CampusBuilding] {
    CampusBuilding.allBuildings.filter { $0.campus == campus }
  }

  /// 教室番号の入力値
  @State private var roomNumber = ""

  /// 保存失敗アラートの表示フラグ
  @State private var isShowingSaveError = false

  /// 保存失敗時のエラーメッセージ
  @State private var saveErrorMessage = ""

  /// 前後の空白を除いた科目名
  private var trimmedSubjectName: String {
    subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 入力が有効かどうか（科目名は必須）
  private var isInputValid: Bool {
    !trimmedSubjectName.isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("学期・曜日・時限") {
          Picker("学期", selection: $semester) {
            ForEach(Semester.allCases) { semester in
              Text(semester.displayName).tag(semester)
            }
          }
          Picker("曜日", selection: $weekday) {
            ForEach(Weekday.lectureDays) { day in
              Text("\(day.shortName)曜").tag(day)
            }
          }
          Picker("時限", selection: $periodNumber) {
            ForEach(ClassPeriod.allPeriods) { classPeriod in
              Text("\(classPeriod.displayName)（\(classPeriod.timeRangeText)）")
                .tag(classPeriod.number)
            }
          }
        }

        Section("授業情報") {
          TextField("科目名（必須）", text: $subjectName)
          TextField("教員名", text: $teacherName)
          Picker("キャンパス", selection: $campus) {
            ForEach(Campus.allCases) { campus in
              Text(campus.displayName).tag(campus)
            }
          }
          Picker("講義棟", selection: $buildingName) {
            Text("未定").tag("")
            ForEach(campusBuildings) { building in
              Text(building.name).tag(building.name)
            }
          }
          TextField("教室番号（例: 731）", text: $roomNumber)
            .keyboardType(.numbersAndPunctuation)
        }
      }
      .navigationTitle("授業を追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            saveLecture()
          }
          .disabled(!isInputValid)
        }
      }
      .alert("保存に失敗しました", isPresented: $isShowingSaveError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(saveErrorMessage)
      }
      .onChange(of: campus) { _, newCampus in
        // キャンパスを切り替えたら講義棟の選択をそのキャンパスの先頭に戻す
        buildingName = CampusBuilding.allBuildings
          .first { $0.campus == newCampus }?.name ?? ""
      }
    }
  }

  // MARK: - Private

  /// 入力内容からLectureを生成して保存する
  private func saveLecture() {
    let lecture = Lecture(
      semester: semester,
      weekday: weekday,
      period: periodNumber,
      subjectName: trimmedSubjectName,
      teacherName: teacherName.trimmingCharacters(in: .whitespacesAndNewlines),
      campus: campus,
      buildingName: buildingName,
      roomNumber: roomNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    modelContext.insert(lecture)
    do {
      try modelContext.save()
      // 時間割が変わったのでホーム／ロック画面のウィジェットを更新する
      WidgetCenter.shared.reloadAllTimelines()
      dismiss()
    } catch {
      saveErrorMessage = error.localizedDescription
      isShowingSaveError = true
    }
  }
}

#Preview {
  AddLectureView()
    .modelContainer(for: Lecture.self, inMemory: true)
}
