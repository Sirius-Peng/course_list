import SwiftUI
import ScheduleCore

struct ICSSubscriptionSection: View {
    @EnvironmentObject var model: ScheduleModel
    @EnvironmentObject var subscriptions: ICSSubscriptionManager
    let add: () -> Void
    @State private var confirmStop = false
    var body: some View {
        Section("ICS 链接订阅") {
            if let record = subscriptions.subscription {
                LabeledContent("订阅来源", value: record.url.host ?? "ICS")
                Toggle("自动更新", isOn: Binding(get: { record.automatic }, set: { value in
                    do { try subscriptions.setAutomatic(value) } catch { subscriptions.report(error) }
                })).accessibilityIdentifier("subscription.auto")
                if let date = record.lastCheckedAt { LabeledContent("最近检查", value: SchoolClock.format(date, "M/d HH:mm")) }
                if let date = record.lastUpdatedAt { LabeledContent("内容更新", value: SchoolClock.format(date, "M/d HH:mm")) }
                Button("立即刷新订阅", systemImage: "arrow.clockwise") { Task { await subscriptions.refreshIfNeeded(using: model, force: true) } }
                    .disabled(subscriptions.isRefreshing).accessibilityIdentifier("subscription.refresh")
                Button("更换订阅链接", systemImage: "link") { add() }.accessibilityIdentifier("subscription.change")
                Button("停止订阅", role: .destructive) { confirmStop = true }.accessibilityIdentifier("subscription.stop")
                if subscriptions.isRefreshing { ProgressView("正在检查订阅…") }
                Text("开启后在打开 App 或系统允许的后台刷新中，约每 6 小时检查一次；也可随时手动刷新。学期范围沿用订阅时的设置，更换链接可重新设置。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("添加 ICS 链接订阅", systemImage: "link.badge.plus") { add() }.accessibilityIdentifier("subscription.add")
            }
            if let message = subscriptions.message { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("subscription.status") }
        }
        .confirmationDialog("停止订阅？", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("停止订阅", role: .destructive) { do { try subscriptions.stop() } catch { subscriptions.report(error) } }
        } message: { Text("当前课程会保留，但不再从链接获取更新。") }
    }
}
