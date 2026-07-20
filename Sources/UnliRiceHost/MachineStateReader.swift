import CoreGraphics
import Foundation
import IOKit.ps
import UnliRiceCore

/// Reads the two facts `RoutineScheduler` gates on.
///
/// Lives in this target rather than in `UnliRiceCore` on purpose: this needs
/// IOKit and CoreGraphics, and the core is the layer `unlirice-mcp` and the
/// whole test suite link. `RoutineScheduler.gate` takes the answer as a plain
/// struct so the policy stays testable without a Mac in a particular power
/// state.
///
/// It moved *out* of the GUI when `unlirice-agent` appeared: the daemon gates on
/// exactly the same two facts, and two copies of "is this Mac on power" that
/// could disagree would mean Eco's promise held in one process and not the
/// other.
extension MachineState {
    public static func current() -> MachineState {
        MachineState(isOnPower: isOnPower(), idleFor: secondsSinceLastInput())
    }

    static func isOnPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            // A desktop with no battery reports no power sources at all. Treating
            // that as "on battery" would mean Eco never runs on a Mac mini.
            return true
        }
        if sources.isEmpty { return true }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue { return true }
        }
        return false
    }

    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
    }
}
