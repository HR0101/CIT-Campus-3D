//
//  TTWidgetBundle.swift
//  CITWidget
//
//  ウィジェット拡張のエントリポイント．
//  ホーム画面ウィジェット（小・中・大）とロック画面アクセサリウィジェットを束ねる．
//
//  ※ Xcodeで Widget Extension ターゲットを作成すると，テンプレートが生成する
//    「<ProductName>Bundle.swift」など @main 付きのサンプルが別に出来る．
//    @main が重複してビルドできなくなるため，テンプレート生成の .swift は削除し，
//    このファイル群（TT*.swift）を残すこと．
//

import SwiftUI
import WidgetKit

@main
struct CITWidgetBundle: WidgetBundle {
  var body: some Widget {
    // ホーム画面（小・中・大）
    TimetableWidget()
    // ロック画面・文字盤（次の授業）
    NextClassAccessoryWidget()
  }
}
