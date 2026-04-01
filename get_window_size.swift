import Foundation
import CoreGraphics

let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windowList {
    if let ownerName = window[kCGWindowOwnerName as String] as? String,
       ownerName.contains("BoltTubeMaxNative") || ownerName.contains("BoltTube") {
        if let bounds = window[kCGWindowBounds as String] as? [String: Any],
           let width = bounds["Width"] as? CGFloat,
           let height = bounds["Height"] as? CGFloat {
            print("Width: \(width), Height: \(height)")
            break
        }
    }
}
