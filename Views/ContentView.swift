//
//  ContentView.swift
//  CIT-Campus-3D
//
//  ルートビュー．マップと時間割の2タブ構成．
//  毎分の再評価で「次の授業」を判定し，マップの目的地へ反映する．
//

import SwiftData
import SwiftUI

struct ContentView: View {

  /// 全登録授業
  @Query private var lectures: [Lecture]

  /// 次の授業の判定サービス
  private let nextLectureResolver = NextLectureResolver()

  var body: some View {
    // 毎分再評価して「次の授業」の切り替わりを自動で反映する
    TimelineView(.everyMinute) { context in
      let nextLecture = nextLectureResolver.resolveNextLecture(
        from: lectures,
        now: context.date
      )
      TabView {
        Tab("マップ", systemImage: "map.fill") {
          CampusMapView(
            destinationBuilding: nextLecture?.lecture.building,
            nextLecture: nextLecture
          )
        }
        Tab("時間割", systemImage: "calendar") {
          TimetableListView()
        }
      }
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Lecture.self, inMemory: true)
}
