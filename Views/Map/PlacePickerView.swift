//
//  PlacePickerView.swift
//  CIT-Campus-3D
//
//  全キャンパスの建物・施設を一覧から選び，経路案内の目的地に設定するシート．
//

import CoreLocation
import SwiftUI

/// 場所一覧（目的地の手動選択）
struct PlacePickerView: View {

  /// 現在地（距離表示に使う．無ければ距離は表示しない）
  let currentLocation: CLLocation?

  /// 場所が選ばれたときの処理
  let onSelect: (CampusBuilding) -> Void

  @Environment(\.dismiss) private var dismiss

  /// 検索文字列
  @State private var searchText = ""

  /// 距離表示の定数
  private enum FormatConstants {
    /// km表示に切り替える境界（メートル）
    static let metersPerKilometer: Double = 1_000
  }

  /// キャンパスごとにまとめた場所（検索で絞り込み済み）
  private var groupedPlaces: [(campus: Campus, places: [CampusBuilding])] {
    Campus.allCases.compactMap { campus in
      let places = CampusBuilding.allBuildings
        .filter { $0.campus == campus && matchesSearch($0) }
      return places.isEmpty ? nil : (campus, places)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(groupedPlaces, id: \.campus) { group in
          Section("\(group.campus.displayName)キャンパス") {
            ForEach(group.places) { place in
              Button {
                onSelect(place)
                dismiss()
              } label: {
                placeRow(place)
              }
            }
          }
        }
      }
      .navigationTitle("場所を選んで案内")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $searchText, prompt: "建物・施設名で検索")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") {
            dismiss()
          }
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  // MARK: - 行

  /// 場所1件の行（名称・付帯施設・現在地からの距離）
  private func placeRow(_ place: CampusBuilding) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "mappin.circle.fill")
        .font(.title3)
        .foregroundStyle(.cyan)

      VStack(alignment: .leading, spacing: 2) {
        Text(place.name)
          .font(.body)
          .foregroundStyle(.primary)
        if let facilityNote = place.facilityNote {
          Text(facilityNote)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      if let distanceText = distanceText(to: place) {
        Text(distanceText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Private

  /// 検索文字列に一致するか（空なら全件一致）
  private func matchesSearch(_ place: CampusBuilding) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return true }
    if place.name.localizedCaseInsensitiveContains(query) {
      return true
    }
    if let facilityNote = place.facilityNote {
      return facilityNote.localizedCaseInsensitiveContains(query)
    }
    return false
  }

  /// 現在地から場所までの距離の表示文字列（現在地が無ければnil）
  private func distanceText(to place: CampusBuilding) -> String? {
    guard let currentLocation else { return nil }
    let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
    let distance = currentLocation.distance(from: placeLocation)
    if distance >= FormatConstants.metersPerKilometer {
      return String(format: "約%.1fkm", distance / FormatConstants.metersPerKilometer)
    }
    return "約\(Int(distance))m"
  }
}

#Preview {
  PlacePickerView(currentLocation: nil) { _ in }
}
