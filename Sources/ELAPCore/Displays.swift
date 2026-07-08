// ELAPCore — display model & discovery.

import Foundation
import CoreGraphics

public struct DisplayInfo {
    public let id: CGDirectDisplayID
    public let isBuiltIn: Bool
    public let isActive: Bool
    public let bounds: CGRect
    // Physical screen size in millimetres from EDID. Virtual/headless displays (macOS dummy
    // framebuffers, DisplayLink dock placeholders) report .zero here because they have no
    // physical panel. Used to distinguish real hardware from virtual displays.
    public let physicalSize: CGSize

    public init(id: CGDirectDisplayID, isBuiltIn: Bool, isActive: Bool, bounds: CGRect, physicalSize: CGSize) {
        self.id = id
        self.isBuiltIn = isBuiltIn
        self.isActive = isActive
        self.bounds = bounds
        self.physicalSize = physicalSize
    }
}

public func fetchDisplays(verbose: Bool = false) -> [DisplayInfo] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)

    var infos: [DisplayInfo] = ids.map { id in
        let builtIn      = CGDisplayIsBuiltin(id) != 0
        let active       = CGDisplayIsActive(id) != 0
        let bounds       = CGDisplayBounds(id)
        let physicalSize = CGDisplayScreenSize(id)
        if verbose {
            let kind  = builtIn ? "built-in" : "external"
            let state = active  ? "active"   : "INACTIVE"
            let w     = Int(bounds.width)
            let h     = Int(bounds.height)
            let pw    = Int(physicalSize.width)
            let ph    = Int(physicalSize.height)
            let phys  = (pw > 0 || ph > 0) ? "\(pw)x\(ph)mm" : "virtual"
            print("[verbose] Display \(id): \(kind), \(state), \(w)x\(h), \(phys)")
        }
        return DisplayInfo(id: id, isBuiltIn: builtIn, isActive: active, bounds: bounds, physicalSize: physicalSize)
    }

    // Recovery: if no built-in appears in the online list, it was previously disabled and
    // dropped out. Recover its ID so `elap on` and friends can still target it.
    if !infos.contains(where: { $0.isBuiltIn }) {
        var recoveredID: CGDirectDisplayID? = nil

        // Strategy 1 (primary): hardware probe. CGDisplayIsBuiltin queries hardware even for
        // offline displays, so walking 1...32 finds the built-in without needing the state file.
        for probe: CGDirectDisplayID in 1...32 {
            if CGDisplayIsBuiltin(probe) != 0 {
                recoveredID = probe
                if verbose { print("[verbose] Built-in display recovered via ID probe: \(probe)") }
                break
            }
        }

        // Strategy 2 (fallback): state file written just before disable.
        if recoveredID == nil, let saved = loadSavedBuiltInDisplayID() {
            recoveredID = saved
            if verbose { print("[verbose] Built-in display recovered via state file: \(saved)") }
        }

        if let id = recoveredID {
            // isActive: false, bounds/physicalSize: .zero — it is invisible/offline.
            infos.append(DisplayInfo(id: id, isBuiltIn: true, isActive: false, bounds: .zero, physicalSize: .zero))
        }
    }

    return infos
}

// Diagnostic: the *raw* CGGetOnlineDisplayList as CoreGraphics reports it right now, with no
// recovery/virtual-display filtering applied. This is the ground truth we compare against the
// physical reality of the cable. Used for edge-triggered logging so a physical disconnect that
// CoreGraphics fails to notice (stale per-process display cache) becomes visible in the log.
public func rawOnlineDisplaySnapshot() -> String {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)

    let parts = ids.map { id -> String in
        let kind   = CGDisplayIsBuiltin(id) != 0 ? "builtin" : "ext"
        let state  = CGDisplayIsActive(id)  != 0 ? "active"  : "inactive"
        let online = CGDisplayIsOnline(id)  != 0 ? "online"  : "offline"
        let sz     = CGDisplayScreenSize(id)
        let phys   = (sz.width > 0 || sz.height > 0) ? "phys" : "virtual"
        return "\(id)[\(kind),\(state),\(online),\(phys)]"
    }
    return "count=\(count) {\(parts.joined(separator: " "))}"
}
