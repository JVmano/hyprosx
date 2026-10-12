import Foundation

public enum WindowGeometry {
    public static func sticks(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 2 }

    public static func frame(tile: Rect, workArea: Rect, gapsIn: Edges, borderSize: Double, pseudoSize: Size?) -> Rect {
        let box = tile.rounded()
        let l = sticks(box.minX, workArea.minX), r = sticks(box.maxX, workArea.maxX)
        let t = sticks(box.minY, workArea.minY), b = sticks(box.maxY, workArea.maxY)
        let offL = l ? 0 : gapsIn.left, offT = t ? 0 : gapsIn.top
        let offR = r ? 0 : gapsIn.right, offB = b ? 0 : gapsIn.bottom
        var pos = Point(x: box.x + offL, y: box.y + offT)
        var size = Size(width: box.width - offL - offR, height: box.height - offT - offB)
        if let pseudo = pseudoSize {
            var scale = 1.0
            if pseudo.width > size.width || pseudo.height > size.height {
                if pseudo.width > size.width { scale = size.width / pseudo.width }
                if pseudo.height * scale > size.height { scale = size.height / pseudo.height }
            }
            let fitted = Size(width: pseudo.width * scale, height: pseudo.height * scale)
            pos = Point(x: pos.x + (size.width - fitted.width) / 2, y: pos.y + (size.height - fitted.height) / 2)
            size = fitted
        }
        return Rect(x: pos.x + borderSize, y: pos.y + borderSize,
                    width: max(1, size.width - 2 * borderSize), height: max(1, size.height - 2 * borderSize)).rounded()
    }

    public static func focalPoint(of box: Rect, _ direction: Direction) -> Point {
        switch direction {
        case .up: return Point(x: box.x + box.width / 2, y: box.y - 1)
        case .down: return Point(x: box.x + box.width / 2, y: box.maxY + 1)
        case .left: return Point(x: box.x - 1, y: box.y + box.height / 2)
        case .right: return Point(x: box.maxX + 1, y: box.y + box.height / 2)
        }
    }
}
