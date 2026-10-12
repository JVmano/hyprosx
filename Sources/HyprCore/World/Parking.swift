import Foundation

public enum Parking {
    public static func usesBottomLeft(_ monitor: MonitorInfo, among all: [MonitorInfo]) -> Bool {
        let f = monitor.frame
        let xOff = f.width * 0.1, yOff = f.height * 0.1
        let br = Point(x: f.maxX, y: f.maxY), bl = Point(x: f.minX, y: f.maxY)
        func score(_ p: [Point]) -> Int {
            all.reduce(0) { acc, m in
                acc + (m.frame.contains(p[0]) ? 1 : 0) + (m.frame.contains(p[1]) ? 1 : 0) + (m.frame.contains(p[2]) ? 10 : 0)
            }
        }
        let brScore = score([br + Point(x: 2, y: -yOff), br + Point(x: -xOff, y: 2), br + Point(x: 2, y: 2)])
        let blScore = score([bl + Point(x: -2, y: -yOff), bl + Point(x: xOff, y: 2), bl + Point(x: -2, y: 2)])
        return blScore < brScore
    }

    public static func origin(windowSize: Size, monitor: MonitorInfo, among all: [MonitorInfo], bundleID: String) -> Point {
        let v = monitor.visibleFrame
        let offset: Double = bundleID == "us.zoom.xos" ? 0 : 1
        if usesBottomLeft(monitor, among: all) { return Point(x: v.minX + offset - windowSize.width, y: v.maxY - offset) }
        return Point(x: v.maxX - offset, y: v.maxY - offset)
    }
}
