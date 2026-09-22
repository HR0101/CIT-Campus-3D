//
//  AcknowledgementsView.swift
//  CIT-Campus-3D
//
//  地図データの帰属表示（OpenStreetMap）と，利用しているオープンソースソフトウェアの
//  ライセンス表示．OpenStreetMapのデータ利用にはODbLにより帰属表示が必要なため，本画面で明示する．
//

import SwiftUI

/// ライセンス・帰属表示画面
struct AcknowledgementsView: View {
  var body: some View {
    LegalDocumentScaffold(title: "ライセンス・帰属表示", subtitle: "") {

      LegalHeading("地図データ")
      LegalParagraph(
        "本アプリの地図は，OpenStreetMapのデータを利用しています．"
          + "地図データは OpenStreetMap への貢献者によるもので，"
          + "Open Database License（ODbL）の下で提供されています．"
      )
      LegalBullet("© OpenStreetMap contributors")
      Link(
        "OpenStreetMap 著作権・ライセンス",
        destination: AppMetadata.openStreetMapCopyrightURL
      )
      .font(.subheadline)
      LegalParagraph(
        "地図タイル・スタイルの配信には OpenFreeMap を，スキーマには OpenMapTiles を利用しています．"
      )
      ackLink(
        "OpenFreeMap",
        url: "https://openfreemap.org/"
      )
      ackLink(
        "OpenMapTiles",
        url: "https://openmaptiles.org/"
      )

      LegalHeading("オープンソースソフトウェア")
      LegalParagraph("本アプリは以下のオープンソースソフトウェアを利用しています．")

      ackLibrary(
        name: "MapLibre Native",
        license: "BSD-2-Clause License",
        copyright: "© MapLibre contributors",
        url: "https://github.com/maplibre/maplibre-gl-native-distribution"
      )
      ackLibrary(
        name: "CoreXLSX",
        license: "Apache License 2.0",
        copyright: "© Max Desiatov and CoreOffice contributors",
        url: "https://github.com/CoreOffice/CoreXLSX"
      )
      ackLibrary(
        name: "XMLCoder",
        license: "MIT License",
        copyright: "© Shawn Moore and XMLCoder contributors",
        url: "https://github.com/MaxDesiatov/XMLCoder"
      )
      ackLibrary(
        name: "ZIPFoundation",
        license: "MIT License",
        copyright: "© Thomas Zoechling",
        url: "https://github.com/weichsel/ZIPFoundation"
      )

      LegalParagraph(
        "各ソフトウェアのライセンス全文は，上記リンク先のリポジトリでご確認いただけます．"
      )
    }
  }

  /// ライブラリ1件の表示（名称・ライセンス・著作権・リンク）
  @ViewBuilder
  private func ackLibrary(
    name: String,
    license: String,
    copyright: String,
    url: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(name)
        .font(.subheadline.bold())
      Text("\(license)・\(copyright)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let link = URL(string: url) {
        Link(url, destination: link)
          .font(.caption)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  /// 注記つきの外部リンク1件
  @ViewBuilder
  private func ackLink(_ title: String, url: String) -> some View {
    if let link = URL(string: url) {
      Link(title, destination: link)
        .font(.subheadline)
    } else {
      Text(title).font(.subheadline)
    }
  }
}

#Preview {
  NavigationStack {
    AcknowledgementsView()
  }
}
