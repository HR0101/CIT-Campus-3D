import SwiftUI

/// 時間割未登録の授業でも，教室番号から既存の出席フローを開く．
struct RoomAttendanceView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var roomNumber = ""
  @State private var destination: AttendanceDestination?
  @FocusState private var isRoomFocused: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("教室番号（例：731、642、1024）", text: $roomNumber)
            .keyboardType(.numberPad)
            .focused($isRoomFocused)
          Button("この教室の出席画面を開く") {
            guard let url = AttendanceRoom.url(for: roomNumber) else { return }
            isRoomFocused = false
            destination = AttendanceDestination(url: url)
          }
          .disabled(AttendanceRoom.url(for: roomNumber) == nil)
        } header: {
          Text("教室番号を入力")
        } footer: {
          Text("時間割への登録は不要です。731教室は出席用の7301へ自動変換します。保存したID・パスワードでログインし、出席受付中なら出席を送信します。結果は出席画面で確認してください。")
        }
        if !roomNumber.isEmpty && AttendanceRoom.url(for: roomNumber) == nil {
          Text("教室番号を3〜5桁の数字で入力してください。全角数字も使えます。")
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("教室番号から出席")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
      }
      .sheet(item: $destination) { destination in
        AttendanceSheetView(url: destination.url)
      }
    }
  }
}
