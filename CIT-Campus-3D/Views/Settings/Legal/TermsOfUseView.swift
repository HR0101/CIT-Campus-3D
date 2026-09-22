//
//  TermsOfUseView.swift
//  CIT-Campus-3D
//
//  利用規約・免責事項（アプリ内表示）．大学・manabaの非公認である旨を明記する．
//  外部ホスティング用の同内容Markdownは docs/legal/terms-of-use.md に置く．
//

import SwiftUI

/// 利用規約・免責事項画面
struct TermsOfUseView: View {
  var body: some View {
    LegalDocumentScaffold(title: "利用規約・免責事項") {
      LegalParagraph(
        "本規約は，\(AppMetadata.developerName)（以下「開発者」）が提供する"
          + "「\(AppMetadata.displayName)」（以下「本アプリ」）の利用条件を定めるものです．"
          + "本アプリを利用された時点で，本規約に同意したものとみなします．"
      )

      LegalNotice(
        "本アプリは，学校法人千葉工業大学，および manaba（株式会社朝日ネット）の"
          + "公式アプリではありません．これらの組織・サービスとは一切関係がなく，"
          + "提携・監修・承認を受けたものでもありません（非公認の個人開発アプリです）．"
      )

      LegalHeading("1. 本アプリの位置づけ")
      LegalBullet(
        "本アプリは在学者の利便のために個人が開発した非公式ツールであり，"
          + "千葉工業大学および朝日ネットとは独立しています．"
      )
      LegalBullet(
        "「千葉工業大学」「manaba」その他の名称・商標は，それぞれの権利者に帰属します．"
      )

      LegalHeading("2. 認証情報・自動ログインについて")
      LegalBullet(
        "本アプリのポータル・manaba連携機能は，利用者が自らの意思で登録した認証情報を用いて，"
          + "利用者本人の操作としてログイン・情報取得を行うものです．"
      )
      LegalBullet(
        "各サービス（大学ポータル・manaba等）の利用規約を遵守する責任は利用者にあります．"
          + "本アプリの利用が各サービスの規約に抵触しないことを，利用者ご自身でご確認ください．"
      )
      LegalBullet(
        "規約違反やアカウントの停止・制限等が生じた場合でも，開発者は一切の責任を負いません．"
      )

      LegalHeading("3. 表示情報の正確性")
      LegalBullet(
        "時間割・休講／補講・課題・経路・所要時間などの表示は，取得時点の情報や推定に基づくものであり，"
          + "正確性・完全性・最新性を保証しません．"
      )
      LegalNotice(
        "授業や提出物に関わる重要な判断は，必ず大学ポータル・manaba等の公式情報でご確認ください．"
          + "本アプリの表示のみを根拠とした行動による不利益について，開発者は責任を負いません．"
      )

      LegalHeading("4. 免責")
      LegalBullet(
        "本アプリは現状有姿で提供され，特定目的への適合性等についていかなる保証も行いません．"
      )
      LegalBullet(
        "外部サービス（地図配信・大学側サイト等）の仕様変更・障害により，"
          + "本アプリの機能が予告なく利用できなくなる場合があります．"
      )
      LegalBullet(
        "本アプリの利用または利用不能から生じた損害について，開発者は法令で許される範囲で一切責任を負いません．"
      )

      LegalHeading("5. 禁止事項")
      LegalBullet("法令または各サービスの規約に違反する目的での利用．")
      LegalBullet("他者の認証情報を無断で登録・利用する行為．")
      LegalBullet("本アプリを通じて取得した情報の不正な利用・第三者への提供．")

      LegalHeading("6. 規約の変更")
      LegalParagraph(
        "開発者は，必要に応じて本規約を変更することがあります．変更後に本アプリを継続して利用された場合，"
          + "変更後の規約に同意したものとみなします．"
      )

      LegalHeading("7. 準拠法")
      LegalParagraph("本規約は日本法に準拠し，解釈されます．")

      LegalHeading("8. お問い合わせ")
      LegalParagraph("本規約に関するお問い合わせ先：\(AppMetadata.contactEmail)")

      Text(AppMetadata.copyright)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
  }
}

#Preview {
  NavigationStack {
    TermsOfUseView()
  }
}
