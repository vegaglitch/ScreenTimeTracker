import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @EnvironmentObject var tracker: ScreenTimeTracker

    var sotColor: Color {
        if tracker.sotPaused { return .gray }
        let hrs = tracker.screenOnSecs / 3600
        if hrs <= 4  { return Color(red: 0,   green: 0.8,  blue: 0) }
        if hrs <= 8  { return Color(red: 1,   green: 0.53, blue: 0) }
        return Color(red: 1, green: 0.13, blue: 0.13)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(tracker.sotFormatted + (tracker.sotPaused ? " ⏸" : ""))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(sotColor)

            Image(nsImage: drawBattery(percent: tracker.batteryPercent,
                                       charging: tracker.isCharging))
                .interpolation(.high)
        }
    }
}

func drawBattery(percent: Int, charging: Bool) -> NSImage {
    // Horizontal battery sized to match menu bar height
    // Body + nub, thick border, readable % text inside
    let W: CGFloat = 44   // total width including nub
    let H: CGFloat = 18   // matches menu bar icon height
    let nubW: CGFloat = 4
    let nubH: CGFloat = H * 0.45
    let bodyW = W - nubW
    let corner: CGFloat = 4

    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()

    // Fill color
    let fillColor: NSColor
    if charging {
        fillColor = NSColor(red: 0.20, green: 0.60, blue: 0.90, alpha: 1)
    } else if percent > 60 {
        fillColor = NSColor(red: 0.18, green: 0.75, blue: 0.18, alpha: 1)
    } else if percent > 30 {
        fillColor = NSColor(red: 0.95, green: 0.65, blue: 0.00, alpha: 1)
    } else if percent > 15 {
        fillColor = NSColor(red: 0.95, green: 0.38, blue: 0.00, alpha: 1)
    } else {
        fillColor = NSColor(red: 0.88, green: 0.12, blue: 0.12, alpha: 1)
    }

    let borderColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    let bgColor     = NSColor(white: 0.75, alpha: 1)

    // Nub on right — same color as fill
    let nubY = (H - nubH) / 2
    let nubPath = NSBezierPath(roundedRect: NSRect(x: bodyW, y: nubY, width: nubW, height: nubH),
                               xRadius: 2, yRadius: 2)
    fillColor.setFill()
    nubPath.fill()

    // Body background
    let bodyRect = NSRect(x: 0, y: 0, width: bodyW, height: H)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: corner, yRadius: corner)
    bgColor.setFill(); bodyPath.fill()
    borderColor.setStroke(); bodyPath.lineWidth = 2; bodyPath.stroke()

    // Fill level (left to right)
    let pad: CGFloat = 3
    let maxFillW = bodyW - pad * 2
    let fillW = maxFillW * CGFloat(max(0, min(100, percent))) / 100
    if fillW > 0 {
        let fillRect = NSRect(x: pad, y: pad, width: fillW, height: H - pad * 2)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: corner - 1.5, yRadius: corner - 1.5)
        fillColor.setFill(); fillPath.fill()
    }

    // Text inside
    let txt = charging ? "⚡" : "\(percent)%"
    let fontSize: CGFloat = charging ? 12 : 10
    let txtColor: NSColor = percent > 50 ? NSColor(white: 0.08, alpha: 1) : .white
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: charging ? NSColor.white : txtColor
    ]
    let str = NSAttributedString(string: txt, attributes: attrs)
    let sz = str.size()
    let midX = bodyW / 2
    let midY = H / 2
    str.draw(at: CGPoint(x: midX - sz.width / 2, y: midY - sz.height / 2))

    img.unlockFocus()
    return img
}
