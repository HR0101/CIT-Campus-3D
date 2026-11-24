import SwiftUI

/// 時間割未登録の授業でも，教室番号から既存の出席フローを開く．
struct RoomAttendanceView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.elasticSheetDismiss) private var elasticSheetDismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  @State private var roomNumber = ""
  @State private var destination: AttendanceDestination?
  @State private var detectionAnimator = InoDetectionAnimator()
  @FocusState private var isRoomFocused: Bool

  private var detectedRoomID: String? {
    AttendanceRoom.roomID(for: roomNumber)
  }

  private var detectedURL: URL? {
    AttendanceRoom.url(for: roomNumber)
  }

  private var isInputValid: Bool {
    detectedURL != nil
  }

  private var actionButtonBackground: Color {
    guard isInputValid else {
      return InoMotion.inactiveControl.opacity(colorScheme == .dark ? 0.35 : 0.72)
    }
    return colorScheme == .dark ? .cyan : InoMotion.activeInk
  }

  private var actionButtonForeground: Color {
    guard isInputValid else {
      return .white.opacity(colorScheme == .dark ? 0.65 : 0.92)
    }
    return colorScheme == .dark ? .black : .white
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            InoCausalTextFieldAnchor(text: roomNumber) {
              TextField("教室番号（例：731、642、1024）", text: $roomNumber)
                .keyboardType(.numberPad)
                .focused($isRoomFocused)
            }

            HStack {
              Spacer(minLength: 0)
              InoCausalDetectedPill(
                idleSymbol: "checkmark.seal",
                idleLabel: "教室番号を自動判定",
                detectedSymbol: "checkmark.seal.fill",
                detectedLabel: detectedRoomID.map { "出席ID \($0)" } ?? "教室番号を自動判定",
                isExpanded: detectionAnimator.isPillExpanded
              )
            }
          }

          Button {
            guard let url = detectedURL else { return }
            isRoomFocused = false
            destination = AttendanceDestination(url: url)
          } label: {
            Text("この教室の出席画面を開く")
              .font(.subheadline.weight(.semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .foregroundStyle(actionButtonForeground)
              .background(actionButtonBackground, in: Capsule())
              .animation(.easeInOut(duration: InoMotion.activationDuration), value: isInputValid)
          }
          .buttonStyle(.plain)
          .disabled(!isInputValid)
        } header: {
          Text("教室番号を入力")
        } footer: {
          Text("時間割への登録は不要です。731教室は出席用の7301へ自動変換します。保存したID・パスワードでログインし、出席受付中なら出席を送信します。結果は出席画面で確認してください。")
        }

        if !roomNumber.isEmpty && !isInputValid {
          Text("教室番号を3〜5桁の数字で入力してください。全角数字も使えます。")
            .foregroundStyle(.secondary)
        }
      }
      .scrollContentBackground(.hidden)
      .inoCausalDetectionOverlay(animator: detectionAnimator)
      .navigationTitle("教室番号から出席")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") {
            closeSheet()
          }
        }
      }
      .sheet(item: $destination) { destination in
        AttendanceSheetView(url: destination.url)
      }
    }
    .presentationDetents([.height(360), .large])
    .presentationDragIndicator(.visible)
    .onChange(of: detectedRoomID) { _, newRoomID in
      detectionAnimator.scheduleDetection(key: newRoomID, reduceMotion: reduceMotion)
    }
    .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: detectionAnimator.isPillExpanded)
    .onDisappear {
      detectionAnimator.cancel()
    }
    .task {
      try? await Task.sleep(for: .milliseconds(160))
      guard !Task.isCancelled else { return }
      isRoomFocused = true
    }
  }

  private func closeSheet() {
    isRoomFocused = false
    detectionAnimator.cancel()
    if let elasticSheetDismiss {
      elasticSheetDismiss()
    } else {
      dismiss()
    }
  }
}
