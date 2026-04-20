import Foundation
import Combine
import AppKit
import UserNotifications
import IOKit
import IOKit.ps

// ── Constants ─────────────────────────────────────────────────────────────────
let FULL_CHARGE_PCT     = 98
let IDLE_THRESHOLD_SECS = 300.0
let MAX_GAP_SECS        = 90.0
let MAX_SESSIONS        = 90
let MAX_BACKUPS         = 365
let TIMER_INTERVAL      = 60.0

let DATA_DIR   = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("ScreenTimeTracker")
let DATA_FILE  = DATA_DIR.appendingPathComponent("sessions.json")
let PREFS_FILE = DATA_DIR.appendingPathComponent("prefs.json")
let BACKUP_DIR = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Documents/Backup files/MacScreenTime")

// ── Session model ─────────────────────────────────────────────────────────────
struct Session: Codable, Identifiable {
    var id: String { date }
    var date: String
    var screenOnSecs: Double
    var totalSecsOn: Double?
    var screenOffSecs: Double
    var idleSecs: Double?
    var totalSecs: Double
    var avgOnPerHour: Double
    var drainPct: Int?
    var pctAtStart: Int?
    var pctAtEnd: Int?

    enum CodingKeys: String, CodingKey {
        case date
        case screenOnSecs  = "screen_on_secs"
        case totalSecsOn   = "total_secs_on"
        case screenOffSecs = "screen_off_secs"
        case idleSecs      = "idle_secs"
        case totalSecs     = "total_secs"
        case avgOnPerHour  = "avg_on_per_hour"
        case drainPct      = "drain_pct"
        case pctAtStart    = "pct_at_start"
        case pctAtEnd      = "pct_at_end"
    }
}

struct CurrentSession: Codable {
    var screenOnSecs: Double  = 0
    var totalSecsOn: Double   = 0
    var screenOffSecs: Double = 0
    var idleSecs: Double      = 0
    var pctAtStart: Int?      = nil
    var plugInPct: Int?       = nil
    var wasCharging: Bool?    = nil
    var lastSaveTime: Double  = 0

    enum CodingKeys: String, CodingKey {
        case screenOnSecs  = "screen_on_secs"
        case totalSecsOn   = "total_secs_on"
        case screenOffSecs = "screen_off_secs"
        case idleSecs      = "idle_secs"
        case pctAtStart    = "pct_at_start"
        case plugInPct     = "plug_in_pct"
        case wasCharging   = "was_charging"
        case lastSaveTime  = "last_save_time"
    }
}

struct AppData: Codable {
    var sessions: [Session]      = []
    var current: CurrentSession? = nil
}

struct Prefs: Codable {
    var lastWeeklyNotif: String? = nil
    enum CodingKeys: String, CodingKey {
        case lastWeeklyNotif = "last_weekly_notif"
    }
}

// ── IOKit battery reader ──────────────────────────────────────────────────────
func readBatteryIOKit() -> (Int, Bool) {
    var percent = 100
    var charging = false
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("AppleSmartBattery"))
    if service != 0 {
        if let cap = IORegistryEntryCreateCFProperty(
            service, "CurrentCapacity" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
            percent = cap
        }
        // Use ExternalConnected for instant detection when charger plugged in
        // IsCharging has a delay of a few seconds after connection
        if let ext = IORegistryEntryCreateCFProperty(
            service, "ExternalConnected" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            charging = ext
        } else if let chg = IORegistryEntryCreateCFProperty(
            service, "IsCharging" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            charging = chg
        }
        IOObjectRelease(service)
    }
    return (percent, charging)
}

// ── Main tracker ──────────────────────────────────────────────────────────────
class ScreenTimeTracker: ObservableObject {
    @Published var screenOnSecs: Double  = 0
    @Published var totalOnSecs: Double   = 0
    @Published var screenOffSecs: Double = 0
    @Published var idleSecs: Double      = 0
    @Published var batteryPercent: Int   = 100
    @Published var isCharging: Bool      = false
    @Published var sotPaused: Bool       = false
    @Published var sessions: [Session]   = []
    @Published var plugInPct: Int        = 100

    static weak var shared: ScreenTimeTracker?

    private var data: AppData = AppData()
    private var prefs: Prefs  = Prefs()
    private var timer: Timer?
    private let lock = NSLock()

    var sotFormatted: String { formatDuration(screenOnSecs) }

    init() {
        ScreenTimeTracker.shared = self
        createDirs()
        data     = loadData()
        prefs    = loadPrefs()
        sessions = data.sessions

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onSleep),
            name: NSWorkspace.willSleepNotification, object: nil)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Instant power source change notifications
        let psSource = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async {
                ScreenTimeTracker.shared?.tick()
            }
        }, nil).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), psSource, .defaultMode)

        // Read battery synchronously before first render
        let (initPct, initCharging) = readBatteryIOKit()
        batteryPercent = initPct
        isCharging     = initCharging
        sotPaused      = initCharging
        plugInPct      = initPct

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: TIMER_INTERVAL,
                                      repeats: true) { [weak self] _ in self?.tick() }
    }

    func tick() {
        let (pct, charging, _) = batteryInfo()
        let scrOn = screenIsOn()
        let idleS = idleSeconds()

        lock.lock()
        updateSession(percent: pct, charging: charging, scrOn: scrOn, idleS: idleS)
        saveData()
        lock.unlock()

        runBackup()
        checkWeeklyNotif()
        updatePublished()
    }

    @objc func onWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.tick() }
    }

    @objc func onSleep() {
        lock.lock()
        saveData()
        lock.unlock()
    }

    // ── Session logic ─────────────────────────────────────────────────────────
    private func updateSession(percent: Int, charging: Bool, scrOn: Bool, idleS: Double) {
        let now = Date().timeIntervalSince1970
        var cur = data.current ?? CurrentSession()

        let lastSave    = cur.lastSaveTime > 0 ? cur.lastSaveTime : now
        var pctAtStart  = cur.pctAtStart
        let wasCharging = cur.wasCharging
        var plugInPct   = cur.plugInPct ?? percent
        let gap         = max(0, now - lastSave)

        let justPluggedIn = (wasCharging != nil) && (wasCharging == false) && charging
        if justPluggedIn { plugInPct = percent }
        if cur.plugInPct == nil { plugInPct = percent }

        let sotActive = !charging && percent <= plugInPct

        if gap > 0 && gap <= MAX_GAP_SECS {
            if scrOn && !charging {
                if idleS >= IDLE_THRESHOLD_SECS {
                    cur.idleSecs += gap
                } else {
                    cur.totalSecsOn += gap
                    if sotActive { cur.screenOnSecs += gap }
                }
            } else if !scrOn && !charging {
                cur.screenOffSecs += gap
            }
        } else if gap > MAX_GAP_SECS {
            cur.screenOffSecs += gap
        }

        var justFull = false
        if percent >= FULL_CHARGE_PCT && (wasCharging == true) && !charging {
            justFull = true
        } else if wasCharging == nil && percent >= FULL_CHARGE_PCT && !charging
                  && pctAtStart != nil && (percent - pctAtStart!) >= 5 {
            justFull = true
        } else if wasCharging == nil && percent >= FULL_CHARGE_PCT
                  && !charging && gap / 3600 >= 4 {
            justFull = true
        }

        if justFull {
            closeSession(current: cur, pctEnd: plugInPct)
            cur        = CurrentSession()
            pctAtStart = percent
            plugInPct  = percent
        }

        if pctAtStart == nil { pctAtStart = percent }

        cur.pctAtStart   = pctAtStart
        cur.plugInPct    = plugInPct
        cur.wasCharging  = charging
        cur.lastSaveTime = now
        data.current     = cur
    }

    private func closeSession(current cur: CurrentSession, pctEnd: Int) {
        let on_s  = cur.screenOnSecs
        let tot_s = cur.totalSecsOn
        let off_s = cur.screenOffSecs
        let idle  = cur.idleSecs
        guard on_s > 0 || tot_s > 0 else { return }

        let total = tot_s + off_s + idle
        let hrs   = total > 0 ? total / 3600 : 1
        let start = cur.pctAtStart ?? 0
        let drain = max(0, start - pctEnd)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        let session = Session(
            date:          df.string(from: Date()),
            screenOnSecs:  on_s.rounded(),
            totalSecsOn:   tot_s.rounded(),
            screenOffSecs: off_s.rounded(),
            idleSecs:      idle.rounded(),
            totalSecs:     total.rounded(),
            avgOnPerHour:  (on_s / hrs).rounded(),
            drainPct:      drain,
            pctAtStart:    start,
            pctAtEnd:      pctEnd
        )
        data.sessions.append(session)
        if data.sessions.count > MAX_SESSIONS {
            data.sessions = Array(data.sessions.suffix(MAX_SESSIONS))
        }
        saveData()
    }

    func resetSession() {
        lock.lock()
        let (pct, charging, _) = batteryInfo()
        let cur = data.current ?? CurrentSession()
        closeSession(current: cur, pctEnd: pct)
        var fresh = CurrentSession()
        fresh.pctAtStart   = pct
        fresh.plugInPct    = pct
        fresh.wasCharging  = charging
        fresh.lastSaveTime = Date().timeIntervalSince1970
        data.current = fresh
        saveData()
        lock.unlock()
        updatePublished()
    }

    private func updatePublished() {
        let cur = data.current ?? CurrentSession()
        DispatchQueue.main.async {
            self.screenOnSecs   = cur.screenOnSecs
            self.totalOnSecs    = cur.totalSecsOn
            self.screenOffSecs  = cur.screenOffSecs
            self.idleSecs       = cur.idleSecs
            self.plugInPct      = cur.plugInPct ?? self.batteryPercent
            self.sessions       = self.data.sessions
        }
    }

    // ── Battery ───────────────────────────────────────────────────────────────
    func batteryInfo() -> (Int, Bool, Bool) {
        let (percent, charging) = readBatteryIOKit()
        if Thread.isMainThread {
            self.batteryPercent = percent
            self.isCharging     = charging
            self.sotPaused      = charging || percent > self.plugInPct
        } else {
            DispatchQueue.main.async {
                self.batteryPercent = percent
                self.isCharging     = charging
                self.sotPaused      = charging || percent > self.plugInPct
            }
        }
        return (percent, charging, percent >= FULL_CHARGE_PCT)
    }

    func screenIsOn() -> Bool {
        return CGDisplayIsActive(CGMainDisplayID()) != 0
    }

    func idleSeconds() -> Double {
        return CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~UInt32(0))!)
    }

    // ── Stats ─────────────────────────────────────────────────────────────────
    func avgScreenOn(days: Int?) -> Double? {
        let ss = sessionsInWindow(days: days).filter { $0.screenOnSecs > 0 }
        guard !ss.isEmpty else { return nil }
        return ss.map { $0.screenOnSecs }.reduce(0, +) / Double(ss.count)
    }

    func dailyAvg() -> Double? {
        guard !sessions.isEmpty else { return nil }
        var byDay: [String: Double] = [:]
        for s in sessions {
            let day = String(s.date.prefix(10))
            byDay[day, default: 0] += s.screenOnSecs
        }
        return byDay.values.reduce(0, +) / Double(byDay.count)
    }

    func weekTotal(weeksAgo: Int = 0) -> Double {
        let cal = Calendar.current
        let today = Date()
        guard let refDate = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: today),
              let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: refDate)),
              let we = cal.date(byAdding: .weekOfYear, value: 1, to: ws) else { return 0 }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        return sessions.filter {
            guard let d = df.date(from: $0.date) else { return false }
            return d >= ws && d < we
        }.map { $0.screenOnSecs }.reduce(0, +)
    }

    func trend() -> (String, Double) {
        let tw = weekTotal(weeksAgo: 0)
        let lw = weekTotal(weeksAgo: 1)
        guard lw > 0 else { return ("—", 0) }
        let dp = (tw - lw) / lw * 100
        if abs(dp) < 5 { return ("→", dp) }
        return dp > 0 ? ("↑", dp) : ("↓", dp)
    }

    func sessionsInWindow(days: Int?) -> [Session] {
        guard let days = days else { return sessions }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        return sessions.filter {
            guard let d = df.date(from: $0.date) else { return false }
            return d >= cutoff
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    func createDirs() {
        try? FileManager.default.createDirectory(at: DATA_DIR, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: BACKUP_DIR, withIntermediateDirectories: true)
    }

    func loadData() -> AppData {
        guard let d = try? Data(contentsOf: DATA_FILE),
              let obj = try? JSONDecoder().decode(AppData.self, from: d) else {
            return AppData()
        }
        return obj
    }

    func saveData() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let d = try? encoder.encode(data) {
            try? d.write(to: DATA_FILE)
        }
    }

    func loadPrefs() -> Prefs {
        guard let d = try? Data(contentsOf: PREFS_FILE),
              let p = try? JSONDecoder().decode(Prefs.self, from: d) else {
            return Prefs()
        }
        return p
    }

    func savePrefs() {
        if let d = try? JSONEncoder().encode(prefs) {
            try? d.write(to: PREFS_FILE)
        }
    }

    func backupNow() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "sessions_\(df.string(from: Date())).json"
        let dest = BACKUP_DIR.appendingPathComponent(name)
        try? FileManager.default.copyItem(at: DATA_FILE, to: dest)
        let alert = NSAlert()
        alert.messageText = "Backup Created"
        alert.informativeText = name
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func availableBackups() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: BACKUP_DIR, includingPropertiesForKeys: nil))?.sorted { $0.path > $1.path } ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("sessions_") && $0.pathExtension == "json" }
            .map { $0.lastPathComponent }
    }

    func restoreBackup(named name: String) {
        let src = BACKUP_DIR.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        lock.lock()
        try? FileManager.default.removeItem(at: DATA_FILE)
        try? FileManager.default.copyItem(at: src, to: DATA_FILE)
        data = loadData()
        lock.unlock()
        DispatchQueue.main.async {
            self.sessions = self.data.sessions
        }
    }

    func runBackup() {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dest = BACKUP_DIR.appendingPathComponent("sessions_\(df.string(from: Date())).json")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.copyItem(at: DATA_FILE, to: dest)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: BACKUP_DIR, includingPropertiesForKeys: nil))?.sorted { $0.path < $1.path } ?? []
        if files.count > MAX_BACKUPS {
            files.prefix(files.count - MAX_BACKUPS).forEach {
                try? FileManager.default.removeItem(at: $0)
            }
        }
    }

    func checkWeeklyNotif() {
        let now = Date()
        let cal = Calendar.current
        guard cal.component(.weekday, from: now) == 2,
              cal.component(.hour, from: now) >= 8 else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-'W'ww"
        let weekStr = df.string(from: now)
        guard prefs.lastWeeklyNotif != weekStr else { return }

        let lw = weekTotal(weeksAgo: 1)
        let da = dailyAvg()
        let (sym, _) = trend()
        let daStr = da.map { formatDuration($0) } ?? "—"
        let msg = "Last week: \(formatDuration(lw)) \(sym)\nDaily avg: \(daStr)"

        let content = UNMutableNotificationContent()
        content.title = "Weekly Screen Time Summary"
        content.body  = msg
        let req = UNNotificationRequest(identifier: "weekly-\(weekStr)",
                                         content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)

        prefs.lastWeeklyNotif = weekStr
        savePrefs()
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
func formatDuration(_ secs: Double) -> String {
    let s = max(0, Int(secs))
    let h = s / 3600
    let m = (s % 3600) / 60
    return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
}
