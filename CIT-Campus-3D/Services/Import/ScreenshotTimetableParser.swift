import Foundation
import CoreGraphics
import ImageIO
import Vision

/// ポータルの時間割スクショを端末内で読む．曜日と1〜10限が写る表に対応する．
struct ScreenshotTimetableParser {
  struct Cell: Sendable {
    let weekday: Int
    let period: Int
    let lines: [String]
  }
  struct Result: Sendable {
    let semester: Int?
    let cells: [Cell]
  }
  enum Failure: LocalizedError {
    case image, headers, grid, empty
    var errorDescription: String? {
      switch self {
      case .image: return "画像を開けませんでした。別のスクショを選んでください。"
      case .headers: return "曜日の見出しを読み取れませんでした。月〜金（または土）の見出しが写った画像を選んでください。"
      case .grid: return "時限の区切りを確認できませんでした。1〜10限の表全体が写る、切れていないスクショを選んでください。"
      case .empty: return "授業を読み取れませんでした。文字が鮮明なスクショを選んでください。"
      }
    }
  }

  func parse(data: Data) throws -> Result {
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 4096,
      ] as CFDictionary)
    else { throw Failure.image }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.002
    try VNImageRequestHandler(cgImage: image).perform([request])
    let lines: [(text: String, rect: CGRect)] = (request.results ?? []).compactMap {
      guard let text = $0.topCandidates(1).first?.string else { return nil }
      let box = $0.boundingBox
      return (text, CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
    }
    let labels = ["月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
    let anchors = labels.enumerated().compactMap { index, label -> (day: Int, rect: CGRect)? in
      guard let line = lines.first(where: { $0.text.replacingOccurrences(of: " ", with: "") == label }) else { return nil }
      return (index + 2, line.rect)
    }
    guard anchors.count >= 5, Array(anchors.prefix(5).map(\.day)) == [2, 3, 4, 5, 6],
      let first = anchors.first, let last = anchors.last,
      anchors.allSatisfy({ abs($0.rect.midY - first.rect.midY) < 0.015 })
    else { throw Failure.headers }
    let centers = anchors.map { $0.rect.midX }
    guard zip(centers, centers.dropFirst()).allSatisfy({ $0 < $1 }) else { throw Failure.headers }
    let gap = (last.rect.midX - first.rect.midX) / CGFloat(anchors.count - 1)
    let columns = [max(0, centers[0] - gap / 2)]
      + zip(centers, centers.dropFirst()).map { ($0 + $1) / 2 }
      + [min(1, centers.last! + gap / 2)]
    let footer = lines.filter {
      $0.rect.minY > first.rect.maxY && ($0.text.contains("集中講義") || $0.text.contains("1限"))
    }.map { $0.rect.minY }.min() ?? 1
    let rows = try horizontalLines(image: image, left: columns[0], right: columns.last!,
                                   top: first.rect.midY, bottom: footer)
    // 不足した行を等分で推測すると誤った時限に登録されるため，全10行を確認する．
    guard rows.count == 11 else { throw Failure.grid }
    var cells: [Cell] = []
    for period in 1...10 {
      for (column, anchor) in anchors.enumerated() {
        try Task.checkCancellation()
        let contents = lines.filter {
          $0.rect.midX >= columns[column] && $0.rect.midX < columns[column + 1]
            && $0.rect.midY > rows[period - 1] && $0.rect.midY < rows[period]
        }.sorted {
          abs($0.rect.midY - $1.rect.midY) < min($0.rect.height, $1.rect.height) * 0.4
            ? $0.rect.minX < $1.rect.minX : $0.rect.midY < $1.rect.midY
        }.map { $0.text }
        // 装飾だけのセルは除外．科目情報の解析・修正はプレビュー側で行う．
        if contents.contains(where: { $0.contains("講義室") || $0.contains("教室") || $0.contains("キャンパス") }) {
          let rectangle = CGRect(
            x: columns[column] * CGFloat(image.width), y: rows[period - 1] * CGFloat(image.height),
            width: (columns[column + 1] - columns[column]) * CGFloat(image.width),
            height: (rows[period] - rows[period - 1]) * CGFloat(image.height)
          ).insetBy(dx: 2, dy: 2).integral
          let refined = try image.cropping(to: rectangle).map { try recognizeCell($0) } ?? contents
          cells.append(Cell(weekday: anchor.day, period: period, lines: refined))
        }
      }
    }
    guard !cells.isEmpty else { throw Failure.empty }
    let heading = lines.filter { $0.rect.maxY < first.rect.minY }.map(\.text).joined()
    let semester: Int? = heading.contains("後期") ? 2 : (heading.contains("前期") ? 1 : nil)
    return Result(semester: semester, cells: cells)
  }

  /// 小さい文字はセルごとに拡大して再認識し，同じ行の教員名などを結合する．
  private func recognizeCell(_ image: CGImage) throws -> [String] {
    let width = image.width * 3, height = image.height * 3
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.image }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let enlarged = context.makeImage() else { throw Failure.image }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.005
    try VNImageRequestHandler(cgImage: enlarged).perform([request])
    let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var rows: [[VNRecognizedTextObservation]] = []
    for observation in observations {
      if let last = rows.last?.first,
        abs(last.boundingBox.midY - observation.boundingBox.midY) < min(last.boundingBox.height, observation.boundingBox.height) * 0.5 {
        rows[rows.count - 1].append(observation)
      } else { rows.append([observation]) }
    }
    return rows.map { row in
      row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
  }

  /// 横罫線は多数の列にまたがる無彩色の線として検出する（文字や色付きヘッダは除外）．
  private func horizontalLines(image: CGImage, left: CGFloat, right: CGFloat,
                               top: CGFloat, bottom: CGFloat) throws -> [CGFloat] {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    let groups: [Int] = try bytes.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.image }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      let pixels = buffer.bindMemory(to: UInt8.self)
      let x0 = max(0, Int(left * CGFloat(width)) + 3)
      let x1 = min(width - 1, Int(right * CGFloat(width)) - 3)
      guard x1 > x0 else { throw Failure.grid }
      var groups: [[Int]] = []
      for y in max(0, Int(top * CGFloat(height)))..<min(height, Int(bottom * CGFloat(height))) {
        var count = 0
        for x in stride(from: x0, to: x1, by: 2) {
          let offset = (y * width + x) * 4
          let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
          if max(r, g, b) - min(r, g, b) < 22 && r > 90 && r < 235 { count += 1 }
        }
        if Double(count) / Double((x1 - x0 + 1) / 2) > 0.72 {
          if let last = groups.last?.last, y - last <= 3 { groups[groups.count - 1].append(y) }
          else { groups.append([y]) }
        }
      }
      return groups.map { $0[$0.count / 2] }
    }
    return groups.map { CGFloat($0) / CGFloat(height) }
  }
}
