//
//  TimetableImporter.swift
//  CIT-Campus-3D
//
//  時間割ファイル（Excel/PDF）インポートの入口．
//  拡張子に応じたパーサへ振り分け，セキュリティスコープ付きURLへのアクセスを管理する．
//

import Foundation

/// インポート処理で発生しうるエラー
enum ImportError: LocalizedError {
  /// 対応していないファイル形式
  case unsupportedFileType
  /// ファイルを開けない
  case cannotOpenFile
  /// ファイル形式が想定と異なる
  case invalidFormat(detail: String)
  /// 授業が1件も見つからなかった
  case noLecturesFound

  var errorDescription: String? {
    switch self {
    case .unsupportedFileType:
      return "対応していないファイル形式です．ポータルからダウンロードしたExcel（.xlsx）またはPDF（.pdf）を選択してください．"
    case .cannotOpenFile:
      return "ファイルを開けませんでした．いったんファイルを「ファイル」アプリに保存してから，再度選択してください．"
    case .invalidFormat(let detail):
      return "ファイルの形式が学生時間割表と異なるようです（\(detail)）．ポータルの「学生時間割表」からダウンロードしたファイルか確認してください．"
    case .noLecturesFound:
      return "授業が1件も見つかりませんでした．Excel形式（.xlsx）のファイルで再度お試しください．"
    }
  }
}

/// 時間割ファイルのインポートを担うサービス
struct TimetableImporter {

  /// ファイルを解析して授業ドラフトの一覧を返す
  /// - Parameter url: ユーザーが選択したファイルのURL（セキュリティスコープ付きの場合あり）
  func importTimetable(from url: URL) throws -> [LectureDraft] {
    // 「ファイル」アプリ経由のURLはアクセス権の取得が必要
    let hasSecurityScope = url.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        url.stopAccessingSecurityScopedResource()
      }
    }

    switch url.pathExtension.lowercased() {
    case "xlsx":
      return try XLSXTimetableParser().parse(fileURL: url)
    case "pdf":
      return try PDFTimetableParser().parse(fileURL: url)
    default:
      throw ImportError.unsupportedFileType
    }
  }
}
