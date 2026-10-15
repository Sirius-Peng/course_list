import SwiftUI
import ScheduleCore

struct CourseStatusCard: View {
    let snapshot: ScheduleSnapshot?
    let date: Date
    var body: some View {
        let status = ScheduleEngine.status(in: snapshot, at: date)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(status.heading, systemImage: status.phase == .current ? "book.closed.fill" : "clock")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if snapshot?.isDemo == true { Text("演示").font(.caption).foregroundStyle(.orange) }
            }
            if let course = status.course {
                Text(course.title).font(.title2.bold()).lineLimit(2)
                Label(course.timeRange, systemImage: "clock").monospacedDigit()
                Label(course.displayLocation, systemImage: "mappin.and.ellipse")
                if !SchoolClock.calendar.isDate(course.start, inSameDayAs: date) {
                    Text(SchoolClock.format(course.start, "M月d日 EEEE")).font(.caption).foregroundStyle(.secondary)
                }
                if status.simultaneous.count > 1 { Text("同时间另有 \(status.simultaneous.count - 1) 门课").font(.caption).foregroundStyle(.orange) }
                if status.phase == .current, let next = status.next {
                    Divider()
                    Text("下一课 · \(next.title) \(SchoolClock.format(next.start, "M/d HH:mm"))").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(status.phase == .needsImport ? "把课表装进口袋" : status.heading).font(.title3.bold())
                Text(status.phase == .needsImport ? "在 iPhone 导入课表，锁屏和手表就能随时查看。" : "打开 App 查看或更新学期安排。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if status.stale { Text("课表已超过 7 天未更新").font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct CourseRow: View {
    let course: CourseOccurrence
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(.tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(course.title).font(.headline)
                Text(course.timeRange).font(.subheadline).monospacedDigit()
                Text(course.displayLocation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5)
    }
}
