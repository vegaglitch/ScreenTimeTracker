import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tracker: ScreenTimeTracker
    @State private var showAllHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Current session ───────────────────────────────────────────────
            SectionHeader(title: statusTitle)

            MenuRow(icon: "🖥", label: "Screen On (SOT)",
                    value: tracker.sotFormatted + (tracker.sotPaused ? " ⏸" : ""),
                    color: tracker.sotPaused ? .gray : .green)
            MenuRow(icon: "📺", label: "Total screen-on",
                    value: formatDuration(tracker.totalOnSecs), color: .blue)
            MenuRow(icon: "💤", label: "Idle (no input)",
                    value: formatDuration(tracker.idleSecs), color: .orange)
            MenuRow(icon: "🌑", label: "Screen Off",
                    value: formatDuration(tracker.screenOffSecs), color: .secondary)
            MenuRow(icon: "⏱", label: "Total since charge",
                    value: formatDuration(tracker.screenOnSecs + tracker.screenOffSecs + tracker.idleSecs),
                    color: .secondary)

            if !tracker.isCharging && tracker.sotPaused {
                MenuRow(icon: "🔌", label: "Plugged in at",
                        value: "\(tracker.plugInPct)%  Now: \(tracker.batteryPercent)%",
                        color: .secondary)
            }

            Divider().padding(.vertical, 4)

            // ── Usage stats ───────────────────────────────────────────────────
            SectionHeader(title: "USAGE STATS")

            if let da = tracker.dailyAvg() {
                MenuRow(icon: "📊", label: "Daily avg",
                        value: formatDuration(da), color: .blue)
            }
            MenuRow(icon: "📅", label: "This week",
                    value: formatDuration(tracker.weekTotal()), color: .blue)

            let (sym, dp) = tracker.trend()
            let lw = tracker.weekTotal(weeksAgo: 1)
            let trendColor: Color = sym == "↑" ? .red : sym == "↓" ? .green : .secondary
            MenuRow(icon: sym, label: "vs last week",
                    value: lw > 0 ? "\(String(format: "%+.0f", dp))%  (\(formatDuration(lw)))" : "not enough data",
                    color: trendColor)

            Divider().padding(.vertical, 4)

            // ── Averages ──────────────────────────────────────────────────────
            SectionHeader(title: "SCREEN-ON AVERAGES")

            let periods: [(String, Int?)] = [
                ("Last 7 days", 7), ("Last 30 days", 30),
                ("Last 6 months", 182), ("Last year", 365), ("All time", nil)
            ]
            let avg30 = tracker.avgScreenOn(days: 30)
            let cnt30 = tracker.sessionsInWindow(days: 30).count
            DisclosureGroup(
                content: {
                    ForEach(periods, id: \.0) { label, days in
                        let v = tracker.avgScreenOn(days: days)
                        let cnt = tracker.sessionsInWindow(days: days).count
                        MenuRow(icon: "📊", label: label,
                                value: v != nil ? "\(formatDuration(v!))  (\(cnt) sessions)" : "Not enough data",
                                color: .orange)
                    }
                },
                label: {
                    MenuRow(icon: "🖥", label: "Per session (30d)",
                            value: avg30 != nil ? "\(formatDuration(avg30!))  (\(cnt30) sessions)" : "Not enough data",
                            color: .orange)
                }
            )

            Divider().padding(.vertical, 4)

            // ── Session history ───────────────────────────────────────────────
            SectionHeader(title: "SESSION HISTORY")

            let displayed = showAllHistory ? tracker.sessions.reversed() : Array(tracker.sessions.suffix(10).reversed())

            if tracker.sessions.isEmpty {
                Text("  No completed sessions yet")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            } else {
                ForEach(displayed, id: \.date) { s in
                    HistoryRow(session: s)
                }

                Button(showAllHistory ? "▲ Show less" : "▼ Show all \(tracker.sessions.count) sessions") {
                    showAllHistory.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }

            Divider().padding(.vertical, 4)

            // ── Actions ───────────────────────────────────────────────────────
            Button("↺  Reset Current Session") {
                let alert = NSAlert()
                alert.messageText = "Reset Current Session?"
                alert.informativeText = "Clears current counters. History is preserved."
                alert.addButton(withTitle: "Reset")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    tracker.resetSession()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

            Button("💾  Backup Now") {
                tracker.backupNow()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

            // Restore from backup
            DisclosureGroup("🗂  Restore from Backup") {
                let backups = tracker.availableBackups()
                if backups.isEmpty {
                    Text("  No backups found")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                } else {
                    ForEach(backups, id: \.self) { backup in
                        Button("  \(backup)") {
                            let alert = NSAlert()
                            alert.messageText = "Restore \(backup)?"
                            alert.informativeText = "This will replace your current session history."
                            alert.addButton(withTitle: "Restore")
                            alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn {
                                tracker.restoreBackup(named: backup)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 1)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

            Button("✕  Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .padding(8)
        .frame(width: 460)
    }

    var statusTitle: String {
        if tracker.isCharging { return "CHARGING — SOT PAUSED" }
        if tracker.sotPaused  { return "SOT PAUSED (drain to \(tracker.plugInPct)%, now \(tracker.batteryPercent)%)" }
        return "CURRENT CHARGE SESSION"
    }
}

// ── Sub-views ─────────────────────────────────────────────────────────────────
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.primary.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

struct MenuRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(icon).frame(width: 20)
            Text(label)
                .font(.system(size: 12, design: .default))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

struct HistoryRow: View {
    let session: Session
    var body: some View {
        HStack {
            Text(session.date)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.purple)
            Spacer()
            Text("SOT: \(formatDuration(session.screenOnSecs))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.purple)
            Text("Total: \(formatDuration(session.totalSecs))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.purple)
            if let drain = session.drainPct, drain > 0 {
                Text("🔋\(drain)%")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
}
