//
//  InoMotionTests.swift
//  CIT-Campus-3DTests
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import CIT_Campus_3D

struct InoMotionTests {

  @Test func elasticArchShapeDeformsTopEdgeByBowOffset() {
    let rect = CGRect(x: 0, y: 100, width: 390, height: 600)

    var flatShape = ElasticArchSheetShape(cornerRadius: 28, bowOffset: 0)
    #expect(flatShape.animatableData == 0)
    let flatBounds = flatShape.path(in: rect).boundingRect
    #expect(abs(flatBounds.minY - 100) < 0.5)

    // 2次ベジェの頂点変位は制御点(minY - bowOffset * 2)に対して bowOffset 分上へ凸になる
    flatShape.animatableData = 60
    #expect(flatShape.bowOffset == 60)
    let convexBounds = flatShape.path(in: rect).boundingRect
    #expect(convexBounds.minY < 50)
    #expect(abs(convexBounds.minY - 40) < 1.0)

    // 凹サグ（負値）時は上端中央が rect.minY より下側へしなる
    let sagShape = ElasticArchSheetShape(cornerRadius: 28, bowOffset: -10)
    let sagPath = sagShape.path(in: rect)
    #expect(sagPath.contains(CGPoint(x: 195, y: 112)))
    #expect(!sagPath.contains(CGPoint(x: 195, y: 103)))
  }

  @Test func elasticArchDetentClampsBelowSafeTopWithKeyboard() {
    let fullHeight: CGFloat = 778
    let keyboardHeight: CGFloat = 442
    #expect(ElasticArchSheetDetent.tall.height(in: fullHeight) <= fullHeight - 6)
    #expect(ElasticArchSheetDetent.tall.height(in: keyboardHeight) <= keyboardHeight - 6)
    #expect(ElasticArchSheetDetent.compact.height(in: keyboardHeight) <= keyboardHeight - 6)
  }

  @Test func parabolicFlightHopsUpwardBeforeDivingToTarget() {
    let start = CGPoint(x: 60, y: 200)
    let end = CGPoint(x: 220, y: 420)

    let p0 = InoMotion.parabolicFlightPoint(t: 0, from: start, to: end)
    let pMid = InoMotion.parabolicFlightPoint(t: 0.25, from: start, to: end)
    let p1 = InoMotion.parabolicFlightPoint(t: 1, from: start, to: end)

    #expect(abs(p0.x - start.x) < 0.001)
    #expect(abs(p0.y - start.y) < 0.001)
    #expect(abs(p1.x - end.x) < 0.001)
    #expect(abs(p1.y - end.y) < 0.001)
    // 発射直後に上方向ホップを含む制御点のため、t=0.25 付近でも目標より上を通過する
    #expect(pMid.y < end.y)
    #expect(InoMotion.parabolicControlPoint(from: start, to: end).y < start.y)
  }

  @Test func orbDiameterTapersDuringFlight() {
    #expect(abs(InoMotion.orbDiameter(progress: 0) - 9.0) < 0.001)
    #expect(abs(InoMotion.orbDiameter(progress: 0.5) - 7.0) < 0.001)
    #expect(abs(InoMotion.orbDiameter(progress: 1) - 5.0) < 0.001)
  }

  @Test func addLectureDraftStoreRoundtripsAndClears() {
    let suiteName = "InoMotionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(AddLectureDraftStore.load(from: defaults) == nil)

    let draft = AddLectureDraft(
      semesterRawValue: Semester.secondHalf.rawValue,
      weekdayRawValue: Weekday.wednesday.rawValue,
      startPeriod: 3,
      endPeriod: 4,
      subjectName: "コンピュータグラフィックス",
      teacherName: "千葉 太郎",
      campusRawValue: Campus.tsudanuma.rawValue,
      buildingName: "7号館",
      roomNumber: "731"
    )
    AddLectureDraftStore.save(draft, to: defaults)
    #expect(AddLectureDraftStore.load(from: defaults) == draft)

    AddLectureDraftStore.clear(from: defaults)
    #expect(AddLectureDraftStore.load(from: defaults) == nil)
  }

  @Test @MainActor func liquidCancelInterruptsOpenAndRestoresHeader() async {
    let controller = InoLiquidCancelController()
    controller.open(reduceMotion: false)
    #expect(controller.isExpanded)
    #expect(controller.isOverlayMounted)
    #expect(!controller.showHeaderChrome)

    // 展開途中での割り込みタップで即座に格納へ切り替えられること
    try? await Task.sleep(for: .milliseconds(50))
    controller.close(reduceMotion: false)
    #expect(!controller.isExpanded)
    #expect(!controller.showSaveDraftPill)

    try? await Task.sleep(for: .milliseconds(460))
    #expect(controller.showHeaderChrome)
    #expect(!controller.isOverlayMounted)
  }

  @Test @MainActor func detectionAnimatorSupportsReduceMotionAndCancellation() async {
    let animator = InoDetectionAnimator()
    animator.scheduleDetection(key: "7301", reduceMotion: true)
    try? await Task.sleep(for: .milliseconds(620))
    #expect(animator.isPillExpanded)
    #expect(!animator.isOrbFlying)

    animator.scheduleDetection(key: nil, reduceMotion: true)
    #expect(!animator.isPillExpanded)
  }
}
