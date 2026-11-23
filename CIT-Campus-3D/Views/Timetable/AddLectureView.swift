//
//  AddLectureView.swift
//  CIT-Campus-3D
//
//  授業を開始〜終了時限の範囲で追加するフォーム．
//  ファイルインポート失敗時の最終フォールバックとしても機能する．
//

import SwiftData
import SwiftUI
import WidgetKit

/// 作成途中の授業入力を保持する下書きデータ
struct AddLectureDraft: Codable, Equatable {
  var semesterRawValue: Int
  var weekdayRawValue: Int
  var startPeriod: Int
  var endPeriod: Int
  var subjectName: String
  var teacherName: String
  var campusRawValue: Int
  var buildingName: String
  var roomNumber: String
}

/// 授業追加フォームの下書き永続化ヘルパー
enum AddLectureDraftStore {
  static let defaultKey = "AddLectureView.savedDraft"

  static func load(from defaults: UserDefaults = .standard, key: String = defaultKey) -> AddLectureDraft? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(AddLectureDraft.self, from: data)
  }

  static func save(_ draft: AddLectureDraft, to defaults: UserDefaults = .standard, key: String = defaultKey) {
    guard let data = try? JSONEncoder().encode(draft) else { return }
    defaults.set(data, forKey: key)
  }

  static func clear(from defaults: UserDefaults = .standard, key: String = defaultKey) {
    defaults.removeObject(forKey: key)
  }
}

/// 授業の手動追加フォーム
struct AddLectureView: View {

  @Environment(\.dismiss) private var dismiss
  @Environment(\.elasticSheetDismiss) private var elasticSheetDismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// 選択中の学期（初期値は現在の学期）
  @State private var semester: Semester = .current(on: Date())

  /// 選択中の曜日
  @State private var weekday: Weekday = .monday

  /// 既定は2コマ．1コマや3コマ以上の授業も指定できる．
  @State private var startPeriod = 1
  @State private var endPeriod = 2

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

  /// 下書きを復元したかどうか
  @State private var hasRestoredDraft = false
  @State private var didAttemptDraftLoad = false

  /// 教室番号からの講義棟自動判定（Pattern 3）
  @State private var detectionAnimator = InoDetectionAnimator()
  @State private var autoBuildingApplyTask: Task<Void, Never>?

  /// リキッドキャンセル制御（Pattern 4）
  @State private var liquidCancel = InoLiquidCancelController()
  @State private var cancelOriginFrame: CGRect?

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
      && ClassPeriod.period(number: startPeriod) != nil
      && ClassPeriod.period(number: endPeriod) != nil
      && startPeriod <= endPeriod
  }

  /// 破棄確認（リキッドキャンセル）が必要となる入力内容があるか
  private var hasUnsavedInput: Bool {
    !trimmedSubjectName.isEmpty
      || !teacherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !roomNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// 教室番号から推定される講義棟（見つからない場合はnil）
  private var detectedBuilding: CampusBuilding? {
    CampusBuilding.building(forRoomNumber: roomNumber, campus: campus)
  }

  /// 教室番号から推定される階数
  private var detectedFloor: Int? {
    Lecture(
      semester: semester,
      weekday: weekday,
      period: startPeriod,
      subjectName: "",
      teacherName: "",
      campus: campus,
      buildingName: detectedBuilding?.name ?? "",
      roomNumber: roomNumber
    ).floor
  }

  /// 検出結果ピルのキー（教室番号＋キャンパスで識別）
  private var roomDetectionKey: String? {
    guard let building = detectedBuilding else { return nil }
    let trimmed = roomNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(campus.rawValue)|\(building.name)|\(trimmed)"
  }

  /// 検出結果ピルのラベル（例: "7号館・3階"）
  private var detectedPillLabel: String {
    guard let building = detectedBuilding else { return "教室番号から自動選択" }
    if let floor = detectedFloor {
      return "\(building.name)・\(floor)階"
    }
    return building.name
  }

  var body: some View {
    NavigationStack {
      Form {
        if hasRestoredDraft {
          Section {
            HStack(spacing: 10) {
              Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.cyan)
              Text("保存した下書きを復元しました")
                .font(.footnote)
                .foregroundStyle(.secondary)
              Spacer()
              Button("クリア") {
                resetDraftFields()
              }
              .font(.footnote.weight(.semibold))
            }
          }
        }

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
          Picker("開始時限", selection: $startPeriod) {
            ForEach(ClassPeriod.allPeriods) { classPeriod in
              Text("\(classPeriod.displayName)（\(classPeriod.timeRangeText)）")
                .tag(classPeriod.number)
            }
          }
          Picker("終了時限", selection: $endPeriod) {
            ForEach(ClassPeriod.allPeriods.filter { $0.number >= startPeriod }) { classPeriod in
              Text("\(classPeriod.displayName)（\(classPeriod.timeRangeText)）")
                .tag(classPeriod.number)
            }
          }
          Text("\(startPeriod)限〜\(endPeriod)限（\(endPeriod - startPeriod + 1)コマ）をまとめて登録します")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("授業情報") {
          TextField("科目名（必須）", text: $subjectName)
          TextField("教員名", text: $teacherName)
          Picker("キャンパス", selection: $campus) {
            ForEach(Campus.allCases) { campus in
              Text(campus.displayName).tag(campus)
            }
          }
          VStack(alignment: .leading, spacing: 8) {
            Picker("講義棟", selection: $buildingName) {
              Text("未定").tag("")
              ForEach(campusBuildings) { building in
                Text(building.name).tag(building.name)
              }
            }
            HStack {
              Spacer(minLength: 0)
              InoCausalDetectedPill(
                idleSymbol: "building.2",
                idleLabel: "教室番号から棟を判定",
                detectedSymbol: "building.2.fill",
                detectedLabel: detectedPillLabel,
                isExpanded: detectionAnimator.isPillExpanded
              )
            }
          }
          InoCausalTextFieldAnchor(text: roomNumber) {
            TextField("教室番号（例: 731）", text: $roomNumber)
              .keyboardType(.numbersAndPunctuation)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .inoCausalDetectionOverlay(animator: detectionAnimator)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            handleCancelTap()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .semibold))
              .frame(width: 28, height: 28)
          }
          .accessibilityLabel("キャンセル")
          .opacity(liquidCancel.isOverlayMounted ? 0 : 1)
          .allowsHitTesting(!liquidCancel.isOverlayMounted)
          .background {
            GeometryReader { geo in
              Color.clear.preference(
                key: InoCancelOriginAnchorKey.self,
                value: geo.frame(in: .global)
              )
            }
          }
        }
        ToolbarItem(placement: .principal) {
          Text("授業を追加")
            .font(.headline)
            .opacity(liquidCancel.showHeaderChrome ? 1 : 0)
            .blur(radius: liquidCancel.showHeaderChrome ? 0 : 4)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            saveLecture()
          }
          .disabled(!isInputValid)
          .tint(isInputValid ? .primary : InoMotion.inactiveControl)
          .animation(.easeInOut(duration: InoMotion.activationDuration), value: isInputValid)
          .opacity(liquidCancel.showHeaderChrome ? 1 : 0)
          .scaleEffect(liquidCancel.showHeaderChrome ? 1 : 0.85)
          .allowsHitTesting(liquidCancel.showHeaderChrome)
        }
      }
      .alert("保存に失敗しました", isPresented: $isShowingSaveError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(saveErrorMessage)
      }
      .onChange(of: startPeriod) { oldStart, newStart in
        // 開始を動かしても選んだコマ数を保ち，最終時限を超えないようにする．
        let duration = max(0, endPeriod - oldStart)
        endPeriod = min(ClassPeriod.allPeriods.last?.number ?? newStart, newStart + duration)
      }
      .onChange(of: campus) { _, newCampus in
        if let detected = CampusBuilding.building(forRoomNumber: roomNumber, campus: newCampus) {
          buildingName = detected.name
        } else {
          // キャンパスを切り替えたら講義棟の選択をそのキャンパスの先頭に戻す
          buildingName = CampusBuilding.allBuildings
            .first { $0.campus == newCampus }?.name ?? ""
        }
      }
      .onChange(of: roomDetectionKey) { _, newKey in
        triggerRoomBuildingDetection(key: newKey)
      }
      .sensoryFeedback(.impact(weight: .light, intensity: 0.65), trigger: detectionAnimator.isPillExpanded)
    }
    .onPreferenceChange(InoCancelOriginAnchorKey.self) { frame in
      if let frame, frame != .zero {
        cancelOriginFrame = frame
      }
    }
    .overlay {
      InoLiquidCancelOverlay(
        controller: liquidCancel,
        originGlobalFrame: cancelOriginFrame,
        onDiscard: { discardAndClose() },
        onSaveDraft: { saveDraftAndClose() }
      )
    }
    .onAppear {
      loadSavedDraftIfNeeded()
    }
    .onDisappear {
      detectionAnimator.cancel()
      autoBuildingApplyTask?.cancel()
      liquidCancel.cancelAll()
    }
  }

  // MARK: - Private

  private func handleCancelTap() {
    if hasUnsavedInput {
      liquidCancel.toggle(reduceMotion: reduceMotion)
    } else {
      closeSheet()
    }
  }

  private func discardAndClose() {
    AddLectureDraftStore.clear()
    closeSheet()
  }

  private func saveDraftAndClose() {
    let draft = AddLectureDraft(
      semesterRawValue: semester.rawValue,
      weekdayRawValue: weekday.rawValue,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      subjectName: subjectName,
      teacherName: teacherName,
      campusRawValue: campus.rawValue,
      buildingName: buildingName,
      roomNumber: roomNumber
    )
    AddLectureDraftStore.save(draft)
    closeSheet()
  }

  private func loadSavedDraftIfNeeded() {
    guard !didAttemptDraftLoad else { return }
    didAttemptDraftLoad = true
    guard let draft = AddLectureDraftStore.load() else { return }
    semester = Semester(rawValue: draft.semesterRawValue) ?? .current(on: Date())
    weekday = Weekday(rawValue: draft.weekdayRawValue) ?? .monday
    startPeriod = draft.startPeriod
    endPeriod = max(draft.startPeriod, draft.endPeriod)
    subjectName = draft.subjectName
    teacherName = draft.teacherName
    campus = Campus(rawValue: draft.campusRawValue) ?? .tsudanuma
    buildingName = draft.buildingName
    roomNumber = draft.roomNumber
    hasRestoredDraft = true
  }

  private func resetDraftFields() {
    AddLectureDraftStore.clear()
    withAnimation(InoMotion.closeAnimation(reduceMotion: reduceMotion)) {
      hasRestoredDraft = false
      subjectName = ""
      teacherName = ""
      roomNumber = ""
      buildingName = CampusBuilding.allBuildings.first { $0.campus == campus }?.name ?? ""
    }
  }

  private func triggerRoomBuildingDetection(key: String?) {
    autoBuildingApplyTask?.cancel()
    detectionAnimator.scheduleDetection(key: key, reduceMotion: reduceMotion)

    guard let detected = detectedBuilding else { return }
    let delayMs = reduceMotion ? 520 : 1_240
    autoBuildingApplyTask = Task {
      try? await Task.sleep(for: .milliseconds(delayMs))
      guard !Task.isCancelled else { return }
      // オーブ着弾・ピル展開と同期して講義棟を反映する
      if buildingName != detected.name {
        withAnimation(InoMotion.pillSpring) {
          buildingName = detected.name
        }
      }
    }
  }

  private func closeSheet() {
    detectionAnimator.cancel()
    autoBuildingApplyTask?.cancel()
    liquidCancel.cancelAll()
    if let elasticSheetDismiss {
      elasticSheetDismiss()
    } else {
      dismiss()
    }
  }

  /// 範囲内の各コマを一度に保存し，既存の時間割・次の授業判定と共有する．
  private func saveLecture() {
    guard isInputValid else { return }
    let lectures = (startPeriod...endPeriod).map { period in
      Lecture(
        semester: semester,
        weekday: weekday,
        period: period,
        subjectName: trimmedSubjectName,
        teacherName: teacherName.trimmingCharacters(in: .whitespacesAndNewlines),
        campus: campus,
        buildingName: buildingName,
        roomNumber: roomNumber.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    for lecture in lectures { modelContext.insert(lecture) }
    do {
      try modelContext.save()
      AddLectureDraftStore.clear()
      // 時間割が変わったのでホーム／ロック画面のウィジェットを更新する
      WidgetCenter.shared.reloadAllTimelines()
      closeSheet()
    } catch {
      // 再試行時に同じ範囲が二重登録されないよう，今回追加した分だけ戻す．
      for lecture in lectures { modelContext.delete(lecture) }
      saveErrorMessage = error.localizedDescription
      isShowingSaveError = true
    }
  }
}

#Preview {
  AddLectureView()
    .modelContainer(for: Lecture.self, inMemory: true)
}
