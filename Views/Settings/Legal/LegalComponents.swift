//
//  LegalComponents.swift
//  CIT-Campus-3D
//
//  プライバシーポリシー・利用規約・ライセンス表示など，法的文書を
//  読みやすく表示するための共通レイアウト部品をまとめる．
//

import SwiftUI

/// 法的文書の共通スクロール枠（タイトル・更新日・本文）
struct LegalDocumentScaffold<Content: View>: View {

  /// 文書タイトル
  let title: String
  /// 更新日などの補足（無ければ空文字）
  var subtitle: String = AppMetadata.legalLastUpdated
  /// 本文
  @ViewBuilder let content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// 文書内の見出し
struct LegalHeading: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.headline)
      .padding(.top, 6)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// 文書内の段落
struct LegalParagraph: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// 文書内の箇条書き1項目
struct LegalBullet: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("・")
        .font(.subheadline)
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// 強調したい注意書き（枠つき）
struct LegalNotice: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.orange.opacity(0.14))
      )
  }
}
