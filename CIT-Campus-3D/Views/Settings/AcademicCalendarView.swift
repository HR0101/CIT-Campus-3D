//
//  AcademicCalendarView.swift
//  CIT-Campus-3D
//
//  登録済みの学年暦（授業期間・休講日・主な行事）を確認する読み取り専用画面．
//

import SwiftUI

/// 学年暦の確認画面
struct AcademicCalendarView: View {

  /// 表示する学年暦
  let calendar = AcademicCalendar.current

  var body: some View {
    List {
      // 授業期間（前期・後期）
      Section("授業期間") {
        ForEach(calendar.terms, id: \.startKey) { term in
          HStack {
            Text(term.semester.displayName)
              .font(.headline)
            Spacer()
            Text("\(AcademicCalendar.monthDayText(fromKey: term.startKey)) 〜 \(AcademicCalendar.monthDayText(fromKey: term.endKey))")
              .foregroundStyle(.secondary)
          }
        }
      }

      // 休講日
      Section {
        ForEach(calendar.closureDays) { day in
          HStack {
            Text(calendar.monthDayWeekdayText(fromKey: day.key))
            Spacer()
            Text(day.reason)
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("休講日")
      } footer: {
        Text("授業期間内でも，これらの日は授業がないものとして「次の授業」を判定します．土曜・日曜はもともと授業がないものとして扱います．祝日でも授業実施日（祝日授業日）は通常どおり扱います．")
      }

      // 主な行事
      Section("主な行事") {
        ForEach(calendar.notableDays) { day in
          HStack {
            Text(calendar.monthDayWeekdayText(fromKey: day.key))
            Spacer()
            Text(day.label)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.trailing)
          }
        }
      }
    }
    .navigationTitle("\(calendar.academicYear)年度 学年暦")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    AcademicCalendarView()
  }
  .preferredColorScheme(.dark)
}
