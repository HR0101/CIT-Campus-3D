//
//  InoMotion.swift
//  CIT-Campus-3D
//
//  ino UI Motion Grammar に基づく共通モーション定数・弾性アーチシート・
//  因果テキスト判定アニメーション基盤．
//  開く＝低ダンピング弾性スプリング，閉じる＝高ダンピング即時格納，
//  背面スケール1.0x維持（Quiet Backing），Reduce Motion配慮を統一的に提供する．
//

import SwiftUI

// MARK: - モーション文法トークンと幾何ヘルパー

/// ino-ui-motion の物理定数・タイミング・カラー・軌道計算ヘルパー
enum InoMotion {

  // MARK: スプリング（非対称ダンピング）

  /// 開く・展開する動き（低ダンピングによる生命感と発見性）
  static let openSpring = Animation.spring(response: 0.45, dampingFraction: 0.50)

  /// 弾性アーチシートの収束スプリング（振幅比 ~0.15 の凹サグを伴う）
  static let archSpring = Animation.spring(response: 0.45, dampingFraction: 0.52)

  /// 判定ピル展開用スプリング（約2%の軽快なオーバーシュート）
  static let pillSpring = Animation.spring(response: 0.42, dampingFraction: 0.68)

  /// 閉じる・格納する動き（高ダンピングで揺れ戻しを抑えて素早く復帰）
  static let closeSpring = Animation.spring(response: 0.30, dampingFraction: 0.90)

  /// リキッドキャンセル格納用スプリング
  static let closeMetaballSpring = Animation.spring(response: 0.30, dampingFraction: 0.92)

  /// Reduce Motion 有効時の穏やかなクロスフェード
  static let reduceMotionCrossfade = Animation.easeInOut(duration: 0.18)

  // MARK: タイミング・スクリム定数

  /// 入力連動ボタン活性の遷移時間（約160ms）
  static let activationDuration: Double = 0.16

  /// 入力確定後のリアルタイム判定デバウンス（450–600ms 推奨範囲の中央値）
  static let detectionDebounce: Duration = .milliseconds(520)

  /// Quiet Backing の半透明スクリム不透明度（約20%）
  static let scrimOpacity: Double = 0.20

  /// スクリムのフェードイン時間
  static let scrimFadeDuration: Double = 0.25

  /// 弾性アーチの凸ピーク変位量（886px幅で+140px ≒ +62pt相当）
  static let archPeakBow: CGFloat = 58

  // MARK: カラートークン（CampusTheme 単一インディゴ・インク統合）

  /// テキスト判定の下線・飛翔オーブ色
  static var detectionAccent: Color { CampusTheme.accent }

  /// 判定結果ピル背景色
  static var pillBackground: Color { CampusTheme.accentFill }

  /// 非活性送信ボタン背景色
  static let inactiveControl = Color(red: 0.643, green: 0.627, blue: 0.671)

  /// 活性送信ボタン背景色（#191729）
  static let activeInk = Color(red: 0.098, green: 0.090, blue: 0.161)

  /// 破壊的アクション色
  static var destructiveCrimson: Color { CampusTheme.danger }

  // MARK: ヘルパー

  static func openAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion ? reduceMotionCrossfade : openSpring
  }

  static func closeAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion ? reduceMotionCrossfade : closeSpring
  }

  /// 2次ベジェ曲線上の点を計算する
  static func quadBezierPoint(
    t: CGFloat,
    p0: CGPoint,
    control: CGPoint,
    p1: CGPoint
  ) -> CGPoint {
    let clamped = min(max(t, 0), 1)
    let u = 1 - clamped
    let x = u * u * p0.x + 2 * u * clamped * control.x + clamped * clamped * p1.x
    let y = u * u * p0.y + 2 * u * clamped * control.y + clamped * clamped * p1.y
    return CGPoint(x: x, y: y)
  }

  /// 発射直後にいったん上へホップしてから目標点へ急降下する放物線制御点を返す
  static func parabolicControlPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
    let x = start.x + (end.x - start.x) * 0.25
    let y = min(start.y, end.y) - 20
    return CGPoint(x: x, y: y)
  }

  /// 放物線アーク飛翔中のオーブ位置を返す
  static func parabolicFlightPoint(t: CGFloat, from start: CGPoint, to end: CGPoint) -> CGPoint {
    quadBezierPoint(
      t: t,
      p0: start,
      control: parabolicControlPoint(from: start, to: end),
      p1: end
    )
  }

  /// 飛翔進行度に応じたオーブ直径（9pt -> 5pt へテーパー縮小）
  static func orbDiameter(progress: CGFloat) -> CGFloat {
    let clamped = min(max(progress, 0), 1)
    return 9.0 - 4.0 * clamped
  }
}

// MARK: - Pattern 1: 弾性アーチ変形シート

/// シート上端の凸アーチ／凹サグを表現する Animatable な Shape
struct ElasticArchSheetShape: Shape {
  var cornerRadius: CGFloat = 28
  /// 正: 上へ凸アーチ、負: 下へ凹サグ、0: 水平
  var bowOffset: CGFloat

  var animatableData: CGFloat {
    get { bowOffset }
    set { bowOffset = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let r = min(cornerRadius, rect.width / 2)

    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + r, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    // 2次ベジェの頂点変位は制御点変位の1/2になるため ×2 で指定する
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - r, y: rect.minY),
      control: CGPoint(x: rect.midX, y: rect.minY - bowOffset * 2)
    )
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + r),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

/// 弾性アーチシートの高さプリセット
enum ElasticArchSheetDetent: Equatable {
  /// コンパクト入力向け（教室番号から出席など）
  case compact
  /// フル近い作成フォーム向け（授業を追加など）
  case tall

  func height(in containerHeight: CGFloat) -> CGFloat {
    let safeMax = max(220, containerHeight - 6)
    switch self {
    case .compact:
      return min(max(320, containerHeight * 0.56), safeMax)
    case .tall:
      return min(max(320, containerHeight * 0.92), safeMax)
    }
  }
}

private struct ElasticSheetDismissKey: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
  /// 弾性アーチシート内から自身を閉じるためのアクション（標準シート時は nil）
  var elasticSheetDismiss: (() -> Void)? {
    get { self[ElasticSheetDismissKey.self] }
    set { self[ElasticSheetDismissKey.self] = newValue }
  }
}

/// ルートビュー（TabView上層）に弾性アーチシートを表示するコーディネータ
@Observable
@MainActor
final class ElasticArchSheetCoordinator {

  fileprivate struct Presentation {
    let id = UUID()
    let token: UUID
    let detent: ElasticArchSheetDetent
    let onDismiss: () -> Void
    let content: () -> AnyView
  }

  fileprivate var activePresentation: Presentation?
  fileprivate var isOpenTarget = false

  /// 外部からの閉じる要求を受け付け、ホスト側で格納アニメーションを実行する
  func present(
    token: UUID,
    detent: ElasticArchSheetDetent,
    onDismiss: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> some View
  ) {
    activePresentation = Presentation(
      token: token,
      detent: detent,
      onDismiss: onDismiss,
      content: { AnyView(content()) }
    )
    isOpenTarget = true
  }

  /// 指定トークンのシートを閉じる（表示側バインディングの false 化に対応）
  func dismiss(token: UUID) {
    guard activePresentation?.token == token else { return }
    isOpenTarget = false
  }

  /// 現在表示中のシートを閉じる
  func requestDismiss() {
    guard activePresentation != nil else { return }
    isOpenTarget = false
  }

  fileprivate func completeDismissal(for presentationID: UUID) {
    guard let current = activePresentation, current.id == presentationID else { return }
    activePresentation = nil
    current.onDismiss()
  }
}

/// 背面コンテンツのスケールを 1.0x に維持したまま弾性アーチシートを重畳するホスト
struct ElasticArchSheetHost<Content: View>: View {
  @Bindable var coordinator: ElasticArchSheetCoordinator
  let content: Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  @State private var sheetProgress: CGFloat = 0
  @State private var scrimProgress: CGFloat = 0
  @State private var bowOffset: CGFloat = 0
  @State private var dragOffset: CGFloat = 0
  @State private var animationEpoch = 0
  @State private var bowTask: Task<Void, Never>?
  @State private var dismissTask: Task<Void, Never>?

  init(
    coordinator: ElasticArchSheetCoordinator,
    @ViewBuilder content: () -> Content
  ) {
    self.coordinator = coordinator
    self.content = content()
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        // 背面コンテンツは 1.0x スケールのまま固定（Quiet Backing）
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let presentation = coordinator.activePresentation {
          let sheetHeight = presentation.detent.height(in: geometry.size.height)
          let travel = sheetHeight + geometry.safeAreaInsets.bottom + 80
          let verticalOffset = (1 - sheetProgress) * travel + dragOffset

          // 約20%の半透明スクリム
          Color.black
            .opacity(InoMotion.scrimOpacity * scrimProgress)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
              coordinator.requestDismiss()
            }
            .accessibilityHidden(true)

          sheetSurface(
            presentation: presentation,
            sheetHeight: sheetHeight,
            verticalOffset: verticalOffset
          )
          .transition(.identity)
          .zIndex(1)
        }
      }
    }
    .sensoryFeedback(.impact(weight: .light, intensity: 0.65), trigger: coordinator.activePresentation?.id)
    .onChange(of: coordinator.activePresentation?.id) { _, newID in
      guard newID != nil, coordinator.isOpenTarget else { return }
      animateOpen()
    }
    .onChange(of: coordinator.isOpenTarget) { _, isOpen in
      guard let presentation = coordinator.activePresentation else { return }
      if isOpen {
        animateOpen()
      } else {
        animateClose(presentationID: presentation.id)
      }
    }
  }

  @ViewBuilder
  private func sheetSurface(
    presentation: ElasticArchSheetCoordinator.Presentation,
    sheetHeight: CGFloat,
    verticalOffset: CGFloat
  ) -> some View {
    let shape = ElasticArchSheetShape(cornerRadius: 24, bowOffset: bowOffset)
    let surfaceColor = Color(uiColor: .systemGroupedBackground)
    let bottomOverhang: CGFloat = 120

    ZStack(alignment: .top) {
      shape
        .fill(surfaceColor)
        .overlay {
          shape.stroke(CampusTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: -4)

      VStack(spacing: 0) {
        // ドラッグハンドル（シート上端のアーチ頂点に追従）
        Capsule()
          .fill(CampusTheme.textMuted.opacity(0.45))
          .frame(width: 36, height: 4)
          .padding(.top, 8)
          .padding(.bottom, 8)
          .offset(y: -bowOffset)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .gesture(sheetDragGesture)
          .accessibilityHidden(true)

        presentation.content()
          .environment(\.elasticSheetDismiss, { coordinator.requestDismiss() })
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding(.bottom, bottomOverhang)
      .clipShape(shape)
    }
    .frame(height: sheetHeight + bottomOverhang)
    .offset(y: verticalOffset + bottomOverhang)
    .allowsHitTesting(coordinator.isOpenTarget)
    .accessibilityAddTraits(.isModal)
  }

  private var sheetDragGesture: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        guard coordinator.isOpenTarget else { return }
        let translation = max(0, value.translation.height)
        dragOffset = translation
        if !reduceMotion {
          bowOffset = -min(translation * 0.08, 12)
        }
      }
      .onEnded { value in
        guard coordinator.isOpenTarget else { return }
        if value.translation.height > 110 || value.predictedEndTranslation.height > 170 {
          coordinator.requestDismiss()
        } else {
          withAnimation(InoMotion.openAnimation(reduceMotion: reduceMotion)) {
            dragOffset = 0
            bowOffset = 0
          }
        }
      }
  }

  private func animateOpen() {
    bowTask?.cancel()
    dismissTask?.cancel()
    animationEpoch += 1
    let currentEpoch = animationEpoch

    sheetProgress = 0
    scrimProgress = 0
    bowOffset = 0
    dragOffset = 0

    if reduceMotion {
      withAnimation(InoMotion.reduceMotionCrossfade) {
        scrimProgress = 1
        sheetProgress = 1
      }
      return
    }

    withAnimation(.easeOut(duration: InoMotion.scrimFadeDuration)) {
      scrimProgress = 1
    }
    withAnimation(InoMotion.archSpring) {
      sheetProgress = 1
    }
    withAnimation(.easeOut(duration: 0.14)) {
      bowOffset = InoMotion.archPeakBow
    }

    bowTask = Task {
      try? await Task.sleep(for: .milliseconds(140))
      guard !Task.isCancelled, animationEpoch == currentEpoch else { return }
      withAnimation(InoMotion.archSpring) {
        bowOffset = 0
      }
    }
  }

  private func animateClose(presentationID: UUID) {
    bowTask?.cancel()
    dismissTask?.cancel()
    animationEpoch += 1
    let currentEpoch = animationEpoch

    withAnimation(InoMotion.closeAnimation(reduceMotion: reduceMotion)) {
      scrimProgress = 0
      sheetProgress = 0
      bowOffset = 0
      dragOffset = 0
    }

    let delayMs = reduceMotion ? 200 : 320
    dismissTask = Task {
      try? await Task.sleep(for: .milliseconds(delayMs))
      guard !Task.isCancelled, animationEpoch == currentEpoch else { return }
      coordinator.completeDismissal(for: presentationID)
    }
  }
}

private struct ElasticArchSheetModifier<SheetContent: View>: ViewModifier {
  @Binding var isPresented: Bool
  let detent: ElasticArchSheetDetent
  let sheetContent: () -> SheetContent

  @Environment(ElasticArchSheetCoordinator.self) private var coordinator: ElasticArchSheetCoordinator?
  @State private var token = UUID()

  func body(content: Content) -> some View {
    if let coordinator {
      content
        .onChange(of: isPresented, initial: true) { _, presented in
          if presented {
            coordinator.present(
              token: token,
              detent: detent,
              onDismiss: { isPresented = false },
              content: sheetContent
            )
          } else {
            coordinator.dismiss(token: token)
          }
        }
        .onDisappear {
          coordinator.dismiss(token: token)
        }
    } else {
      // 単体プレビュー等、ルートホストがない環境では標準シートへフォールバック
      content
        .sheet(isPresented: $isPresented, content: sheetContent)
    }
  }
}

extension View {
  /// ino-ui-motion 準拠の弾性アーチモーダルとして表示する
  func elasticArchSheet<SheetContent: View>(
    isPresented: Binding<Bool>,
    detent: ElasticArchSheetDetent = .tall,
    @ViewBuilder content: @escaping () -> SheetContent
  ) -> some View {
    modifier(ElasticArchSheetModifier(isPresented: isPresented, detent: detent, sheetContent: content))
  }
}

// MARK: - Pattern 3: リアルタイムテキスト判定 → 放物線オーブ飛翔 → ピル展開

/// 画面グローバル座標でのテキスト下線矩形アンカー
struct InoCausalSourceAnchorKey: PreferenceKey {
  static let defaultValue: CGRect? = nil
  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
    value = nextValue() ?? value
  }
}

/// 画面グローバル座標での着弾先ターゲット中心座標
struct InoCausalTargetAnchorKey: PreferenceKey {
  static let defaultValue: CGPoint? = nil
  static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) {
    value = nextValue() ?? value
  }
}

/// 4段階の因果テキスト判定アニメーションを管理する状態コントローラ
@Observable
@MainActor
final class InoDetectionAnimator {
  var isUnderlineVisible = false
  var underlineProgress: CGFloat = 0
  var condenseProgress: CGFloat = 0
  var isOrbFlying = false
  var flightProgress: CGFloat = 0
  var isPillExpanded = false

  private var detectionTask: Task<Void, Never>?
  private var lastCompletedKey: String?

  /// 入力変化時にデバウンス付きで「下線 → オーブ凝縮 → 放物線飛翔 → ピル展開」を実行する
  func scheduleDetection(key: String?, reduceMotion: Bool) {
    detectionTask?.cancel()

    guard let key, !key.isEmpty else {
      lastCompletedKey = nil
      resetVisuals(reduceMotion: reduceMotion)
      return
    }

    if lastCompletedKey == key && isPillExpanded {
      return
    }

    resetVisuals(reduceMotion: reduceMotion)

    detectionTask = Task {
      try? await Task.sleep(for: InoMotion.detectionDebounce)
      guard !Task.isCancelled else { return }

      if reduceMotion {
        lastCompletedKey = key
        withAnimation(InoMotion.reduceMotionCrossfade) {
          isPillExpanded = true
        }
        return
      }

      // Phase 1: 下線ドロー (~0.23s)
      isUnderlineVisible = true
      underlineProgress = 0
      condenseProgress = 0
      withAnimation(.easeOut(duration: 0.23)) {
        underlineProgress = 1
      }

      try? await Task.sleep(for: .milliseconds(235))
      guard !Task.isCancelled else { return }

      // Phase 2: 右端へオーブ凝縮 (~0.15s) + 溜め (~0.03s)
      withAnimation(.easeInOut(duration: 0.15)) {
        condenseProgress = 1
      }

      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled else { return }

      // Phase 3: 放物線アーク飛翔 (~0.27s)
      isUnderlineVisible = false
      isOrbFlying = true
      flightProgress = 0
      withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.27)) {
        flightProgress = 1
      }

      try? await Task.sleep(for: .milliseconds(320))
      guard !Task.isCancelled else { return }

      // Phase 4: 着弾変態 & ピル展開
      isOrbFlying = false
      lastCompletedKey = key
      withAnimation(InoMotion.pillSpring) {
        isPillExpanded = true
      }
    }
  }

  func cancel() {
    detectionTask?.cancel()
    detectionTask = nil
  }

  private func resetVisuals(reduceMotion: Bool) {
    isUnderlineVisible = false
    underlineProgress = 0
    condenseProgress = 0
    isOrbFlying = false
    flightProgress = 0
    if isPillExpanded {
      withAnimation(InoMotion.closeAnimation(reduceMotion: reduceMotion)) {
        isPillExpanded = false
      }
    }
  }
}

/// TextField 内の現在入力テキストの実際の横幅を測定し、下線矩形を報告するラッパ
struct InoCausalTextFieldAnchor<Field: View>: View {
  let text: String
  let field: Field

  init(
    text: String,
    @ViewBuilder field: () -> Field
  ) {
    self.text = text
    self.field = field()
  }

  var body: some View {
    ZStack(alignment: .leading) {
      field
      // テキストレイアウトの実測幅を取得（FormのUIKitホスト越えにも対応するため .global 座標を使用）
      Text(text.isEmpty ? " " : text)
        .font(.body)
        .lineLimit(1)
        .fixedSize()
        .hidden()
        .background {
          GeometryReader { textGeo in
            let frame = textGeo.frame(in: .global)
            Color.clear.preference(
              key: InoCausalSourceAnchorKey.self,
              value: text.isEmpty ? nil : CGRect(
                x: frame.minX,
                y: frame.maxY + 2,
                width: textGeo.size.width,
                height: 2.5
              )
            )
          }
        }
        .allowsHitTesting(false)
    }
  }
}

/// 下線ドロー → オーブ凝縮 → 放物線飛翔を描画する Animatable オーバーレイ
struct InoCausalFlightLayer: View, Animatable {
  let globalSourceRect: CGRect?
  let globalTargetPoint: CGPoint?
  let isUnderlineVisible: Bool
  var underlineProgress: CGFloat
  var condenseProgress: CGFloat
  let isOrbFlying: Bool
  var flightProgress: CGFloat

  var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
    get {
      AnimatablePair(underlineProgress, AnimatablePair(condenseProgress, flightProgress))
    }
    set {
      underlineProgress = newValue.first
      condenseProgress = newValue.second.first
      flightProgress = newValue.second.second
    }
  }

  var body: some View {
    GeometryReader { hostGeo in
      let hostOrigin = hostGeo.frame(in: .global).origin
      if let globalSourceRect {
        let sourceRect = CGRect(
          x: globalSourceRect.minX - hostOrigin.x,
          y: globalSourceRect.minY - hostOrigin.y,
          width: min(globalSourceRect.width, max(24, hostGeo.size.width - 48)),
          height: globalSourceRect.height
        )
        let clampedUnderline = min(max(underlineProgress, 0), 1)
        let clampedCondense = min(max(condenseProgress, 0), 1)
        let startX = sourceRect.minX + sourceRect.width * clampedCondense
        let endX = sourceRect.minX + sourceRect.width * clampedUnderline
        let orbOrigin = CGPoint(x: sourceRect.maxX, y: sourceRect.midY)

        if isUnderlineVisible {
          let lineWidth = max(0, endX - startX)
          if lineWidth > 0.5 {
            Capsule()
              .fill(InoMotion.detectionAccent)
              .frame(width: lineWidth, height: sourceRect.height)
              .position(x: startX + lineWidth / 2, y: sourceRect.midY)
          }

          if clampedCondense > 0.02 {
            let orbSize = 9.0 * min(1, clampedCondense * 1.25)
            Circle()
              .fill(InoMotion.detectionAccent)
              .frame(width: orbSize, height: orbSize)
              .shadow(color: InoMotion.detectionAccent.opacity(0.22), radius: 2)
              .position(orbOrigin)
          }
        }

        if isOrbFlying, let globalTargetPoint {
          let targetPoint = CGPoint(
            x: globalTargetPoint.x - hostOrigin.x,
            y: globalTargetPoint.y - hostOrigin.y
          )
          let position = InoMotion.parabolicFlightPoint(
            t: flightProgress,
            from: orbOrigin,
            to: targetPoint
          )
          let diameter = InoMotion.orbDiameter(progress: flightProgress)
          Circle()
            .fill(InoMotion.detectionAccent)
            .frame(width: diameter, height: diameter)
            .shadow(color: InoMotion.detectionAccent.opacity(0.22), radius: 2)
            .position(position)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// 着弾後にアイコン変態とともに展開する検出結果タグ
struct InoCausalDetectedPill: View {
  let idleSymbol: String
  let idleLabel: String
  let detectedSymbol: String
  let detectedLabel: String
  let isExpanded: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: isExpanded ? detectedSymbol : idleSymbol)
        .font(.subheadline.weight(.medium))
        .contentTransition(.symbolEffect(.replace))
        .foregroundStyle(isExpanded ? .white : InoMotion.detectionAccent)
        .background {
          GeometryReader { iconGeo in
            let frame = iconGeo.frame(in: .global)
            Color.clear.preference(
              key: InoCausalTargetAnchorKey.self,
              value: CGPoint(x: frame.midX, y: frame.midY)
            )
          }
        }

      Text(isExpanded ? detectedLabel : idleLabel)
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(isExpanded ? .white : CampusTheme.textSecondary)
        .lineLimit(1)
        .contentTransition(.numericText())
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background {
      RoundedRectangle(cornerRadius: CampusTheme.controlRadius)
        .fill(isExpanded ? InoMotion.pillBackground : CampusTheme.raisedSurface)
    }
    .overlay {
      RoundedRectangle(cornerRadius: CampusTheme.controlRadius)
        .strokeBorder(isExpanded ? .clear : CampusTheme.hairline, lineWidth: 1)
    }
    .animation(InoMotion.pillSpring, value: isExpanded)
  }
}

private struct InoCausalDetectionOverlayModifier: ViewModifier {
  let animator: InoDetectionAnimator

  @State private var sourceRect: CGRect?
  @State private var targetPoint: CGPoint?

  func body(content: Content) -> some View {
    content
      .onPreferenceChange(InoCausalSourceAnchorKey.self) { sourceRect = $0 }
      .onPreferenceChange(InoCausalTargetAnchorKey.self) { targetPoint = $0 }
      .overlay {
        InoCausalFlightLayer(
          globalSourceRect: sourceRect,
          globalTargetPoint: targetPoint,
          isUnderlineVisible: animator.isUnderlineVisible,
          underlineProgress: animator.underlineProgress,
          condenseProgress: animator.condenseProgress,
          isOrbFlying: animator.isOrbFlying,
          flightProgress: animator.flightProgress
        )
      }
  }
}

extension View {
  /// Causal Text Detection の下線・凝縮オーブ・放物線飛翔オーバーレイを付与する
  func inoCausalDetectionOverlay(animator: InoDetectionAnimator) -> some View {
    modifier(InoCausalDetectionOverlayModifier(animator: animator))
  }
}

// MARK: - Pattern 4: リキッドキャンセルUI（iOS 26 GlassEffectContainer 2段階連鎖分離）

/// キャンセルボタンのグローバル座標アンカー
struct InoCancelOriginAnchorKey: PreferenceKey {
  static let defaultValue: CGRect? = nil
  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
    value = nextValue() ?? value
  }
}

/// 割り込み耐性・タイトル時間差復帰を備えたリキッドキャンセル制御
@Observable
@MainActor
final class InoLiquidCancelController {
  var isExpanded = false
  var isOverlayMounted = false
  var showDiscardPill = false
  var showSaveDraftPill = false
  var showHeaderChrome = true
  var iconRotation: Angle = .zero

  private var epoch = 0
  private var scheduledTask: Task<Void, Never>?

  func toggle(reduceMotion: Bool) {
    if isExpanded {
      close(reduceMotion: reduceMotion)
    } else {
      open(reduceMotion: reduceMotion)
    }
  }

  func open(reduceMotion: Bool) {
    scheduledTask?.cancel()
    epoch += 1
    let currentEpoch = epoch

    isExpanded = true
    isOverlayMounted = true
    withAnimation(.easeOut(duration: 0.12)) {
      showHeaderChrome = false
    }

    if reduceMotion {
      iconRotation = .zero
      withAnimation(InoMotion.reduceMotionCrossfade) {
        showDiscardPill = true
        showSaveDraftPill = true
      }
      return
    }

    scheduledTask = Task {
      // 1フレーム待機してベース円を GlassEffectContainer に登録してから分離させる
      try? await Task.sleep(for: .milliseconds(16))
      guard !Task.isCancelled, self.epoch == currentEpoch else { return }

      withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
        self.iconRotation = .degrees(90)
      }
      withAnimation(InoMotion.openSpring) {
        self.showDiscardPill = true
      }

      try? await Task.sleep(for: .milliseconds(100))
      guard !Task.isCancelled, self.epoch == currentEpoch else { return }

      withAnimation(InoMotion.openSpring) {
        self.showSaveDraftPill = true
      }
    }
  }

  func close(reduceMotion: Bool) {
    scheduledTask?.cancel()
    epoch += 1
    let currentEpoch = epoch

    isExpanded = false

    if reduceMotion {
      withAnimation(InoMotion.reduceMotionCrossfade) {
        showSaveDraftPill = false
        showDiscardPill = false
        showHeaderChrome = true
      }
      scheduledTask = Task {
        try? await Task.sleep(for: .milliseconds(190))
        guard !Task.isCancelled, self.epoch == currentEpoch else { return }
        self.isOverlayMounted = false
      }
      return
    }

    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
      iconRotation = .zero
    }
    withAnimation(InoMotion.closeMetaballSpring) {
      showSaveDraftPill = false
    }

    scheduledTask = Task {
      try? await Task.sleep(for: .milliseconds(60))
      guard !Task.isCancelled, self.epoch == currentEpoch else { return }

      withAnimation(InoMotion.closeMetaballSpring) {
        self.showDiscardPill = false
      }

      // カプセル格納完了後に時間差でタイトル・保存ボタンを復帰させる（重なり防止）
      try? await Task.sleep(for: .milliseconds(190))
      guard !Task.isCancelled, self.epoch == currentEpoch else { return }

      withAnimation(.easeOut(duration: 0.17)) {
        self.showHeaderChrome = true
      }

      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled, self.epoch == currentEpoch else { return }

      self.isOverlayMounted = false
    }
  }

  func cancelAll() {
    scheduledTask?.cancel()
    scheduledTask = nil
  }
}

/// iOS 26 ネイティブ GlassEffectContainer による2段階リキッドキャンセルクラスター
struct InoLiquidCancelOverlay: View {
  @Bindable var controller: InoLiquidCancelController
  let originGlobalFrame: CGRect?
  let onDiscard: () -> Void
  let onSaveDraft: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var liquidNamespace

  var body: some View {
    if controller.isOverlayMounted {
      GeometryReader { hostGeo in
        let hostOrigin = hostGeo.frame(in: .global).origin
        let buttonSize: CGFloat = 36
        let leading = originGlobalFrame.map { max(12, ($0.midX - hostOrigin.x) - buttonSize / 2) } ?? 16
        let top = originGlobalFrame.map { max(4, ($0.midY - hostOrigin.y) - buttonSize / 2) } ?? 8

        ZStack(alignment: .topLeading) {
          // 展開中の背景タップでスナッピーに閉じる
          if controller.isExpanded {
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture {
                controller.close(reduceMotion: reduceMotion)
              }
              .accessibilityHidden(true)
          }

          GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
              Button {
                controller.toggle(reduceMotion: reduceMotion)
              } label: {
                Image(systemName: "xmark")
                  .font(.system(size: 14, weight: .semibold))
                  .rotationEffect(controller.iconRotation)
                  .frame(width: buttonSize, height: buttonSize)
              }
              .foregroundStyle(.primary)
              .glassEffect(.regular.interactive(), in: .circle)
              .glassEffectID("close", in: liquidNamespace)
              .accessibilityLabel(controller.isExpanded ? "キャンセルメニューを閉じる" : "キャンセル")

              if controller.showDiscardPill {
                Button {
                  controller.cancelAll()
                  onDiscard()
                } label: {
                  Label("捨てる", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(InoMotion.destructiveCrimson)
                    .padding(.horizontal, 12)
                    .frame(height: buttonSize)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("discard", in: liquidNamespace)
                .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
              }

              if controller.showSaveDraftPill {
                Button {
                  controller.cancelAll()
                  onSaveDraft()
                } label: {
                  Label("下書きに保存", systemImage: "tray.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(height: buttonSize)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("saveDraft", in: liquidNamespace)
                .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
              }
            }
          }
          .padding(.leading, leading)
          .padding(.top, top)
          .sensoryFeedback(.selection, trigger: controller.isExpanded)
        }
      }
    }
  }
}

