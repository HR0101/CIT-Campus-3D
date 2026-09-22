//
//  PrivacyPolicyView.swift
//  CIT-Campus-3D
//
//  プライバシーポリシー（アプリ内表示）．本アプリの実際のデータ取り扱いを反映する．
//  外部ホスティング用の同内容Markdownは docs/legal/privacy-policy.md に置く．
//

import SwiftUI

/// プライバシーポリシー画面
struct PrivacyPolicyView: View {
  var body: some View {
    LegalDocumentScaffold(title: "プライバシーポリシー") {
      LegalParagraph(
        "本ポリシーは，\(AppMetadata.developerName)（以下「開発者」）が提供する"
          + "「\(AppMetadata.displayName)」（以下「本アプリ」）における利用者情報の取り扱いを定めるものです．"
      )

      LegalNotice(
        "本アプリは，利用者の情報を開発者のサーバーへ収集しません．"
          + "認証情報や時間割などのデータは，原則として利用者の端末内，"
          + "または利用者自身のiCloud（Appleアカウント）内にのみ保存されます．"
      )

      LegalHeading("1. 取得・利用する情報と目的")

      LegalParagraph("本アプリは，以下の情報を各目的のために取り扱います．")
      LegalBullet(
        "位置情報（現在地）：次の講義棟までの徒歩経路の案内，および在校判定に利用します．"
          + "経路の計算にはApple純正の地図機能（MapKit）を利用するため，経路探索の際に座標がAppleへ送信されます．"
      )
      LegalBullet(
        "大学の認証情報（ユーザーID・パスワード・ワンタイムパスワードのキー）："
          + "利用者が登録した場合に限り，大学ポータルおよびmanabaへのログイン自動入力に利用します．"
      )
      LegalBullet(
        "時間割・課題・休講／補講などの学修情報：時間割表示，課題の締切リマインダー，"
          + "休講・補講の反映に利用します．"
      )
      LegalBullet(
        "地図データの取得：地図表示のため，地図タイル配信元（OpenFreeMap）へ通信します．"
          + "この際，一般的なインターネット通信と同様にIPアドレス等が配信元へ送信されます．"
      )

      LegalHeading("2. 情報の保存場所")
      LegalBullet(
        "認証情報：端末内のキーチェーンにのみ保存します（この端末限定の保護領域で，"
          + "iCloudキーチェーンには同期しません）．開発者や第三者へ送信することはありません．"
      )
      LegalBullet(
        "時間割・課題・休講／補講：端末内に保存し，利用者がiCloudを有効にしている場合は"
          + "利用者自身のiCloud（プライベートデータベース）に同期されます．開発者はこれにアクセスできません．"
      )
      LegalBullet("位置情報：端末内で処理し，経路探索のためにAppleへ渡す以外に外部へ送信しません．")

      LegalHeading("3. 認証情報の送信先")
      LegalParagraph(
        "登録された認証情報は，利用者が各サービスへログインする目的でのみ，"
          + "千葉工業大学のポータル（統合認証）およびmanaba（朝日ネット）の各サーバーへ送信されます．"
          + "これは利用者本人が当該サービスへログインする行為であり，開発者がこれらの情報を受領・保存することはありません．"
      )

      LegalHeading("4. 第三者提供・広告・解析")
      LegalBullet("取得した情報を第三者へ販売・提供することはありません．")
      LegalBullet("広告は表示しません．")
      LegalBullet("第三者の解析・トラッキングツールは使用しません．")

      LegalHeading("5. 通知")
      LegalParagraph(
        "授業前・出発時刻・課題締切のリマインダーは，端末内で生成するローカル通知です．"
          + "通知の利用には端末の通知許可が必要で，設定アプリからいつでも変更できます．"
      )

      LegalHeading("6. データの削除")
      LegalBullet("認証情報：設定 ＞ CITポータル連携 から削除できます．")
      LegalBullet("時間割：時間割画面から個別または一括で削除できます．")
      LegalBullet(
        "iCloud上のデータ：端末の「設定」＞ Apple ID ＞ iCloud から本アプリのデータを削除できます．"
      )
      LegalBullet("本アプリを削除すると，端末内に保存された情報は削除されます．")

      LegalHeading("7. お子さまの利用")
      LegalParagraph(
        "本アプリは大学の在学者を主な対象としており，13歳未満の方の利用を想定していません．"
      )

      LegalHeading("8. ポリシーの改定")
      LegalParagraph(
        "本ポリシーは必要に応じて改定することがあります．重要な変更がある場合は，"
          + "アプリの更新等を通じてお知らせします．"
      )

      LegalHeading("9. お問い合わせ")
      LegalParagraph("本ポリシーに関するお問い合わせ先：\(AppMetadata.contactEmail)")

      Text(AppMetadata.copyright)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
  }
}

#Preview {
  NavigationStack {
    PrivacyPolicyView()
  }
}
