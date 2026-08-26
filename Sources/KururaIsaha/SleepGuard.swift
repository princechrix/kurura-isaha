import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from idling to sleep while a timer is counting.
///
/// This is `kIOPMAssertPreventUserIdleSystemSleep`, which needs no privileges and no
/// entitlement — but it only defeats the *idle* timer. Closing the lid or choosing Sleep
/// still sleeps the machine, and `DispatchSourceTimer` does not tick while it is out. The
/// engine covers that case separately by recomputing against the wall clock on wake.
final class SleepGuard {
    private var assertion: IOPMAssertionID = 0
    private(set) var isHeld = false

    func hold(reason: String) {
        guard !isHeld, Settings.shared.preventSleep else { return }
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else { return }
        assertion = identifier
        isHeld = true
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isHeld = false
    }

    deinit { release() }
}
