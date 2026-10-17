// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Darwin
import GreenshotCore

/// Gathers what `EnvironmentSnapshot` holds from this Mac and this process (upstream `EnvironmentInfo` and
/// `SystemInfoSectionViewModel.Refresh`: process memory, threads, uptime, screens). Never the host or user name.
@MainActor
enum SystemInfo {
    static func snapshot(now: Date = Date()) -> EnvironmentSnapshot {
        let bundle = Bundle.main
        var snapshot = EnvironmentSnapshot(
            appName: AppInfo.name,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            architecture: AppAboutCredits.architecture,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            now: now)
        snapshot.translated = sysctlInt("sysctl.proc_translated") == 1
        snapshot.model = sysctlString("hw.model")
        snapshot.chip = sysctlString("machdep.cpu.brand_string")
        snapshot.physicalMemory = ProcessInfo.processInfo.physicalMemory
        snapshot.appMemory = footprint()
        snapshot.peakMemory = peakResidentSize()
        snapshot.threads = threadCount()
        snapshot.launched = processStart()
        snapshot.locale = Locale.current.identifier
        snapshot.thermalState = thermalState
        snapshot.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        snapshot.screens = screens()
        return snapshot
    }

    static func screens() -> [EnvironmentSnapshot.Screen] {
        let primary = NSScreen.screens.first
        return NSScreen.screens.map { screen in
            EnvironmentSnapshot.Screen(
                name: screen.localizedName, width: Int(screen.frame.width), height: Int(screen.frame.height),
                scale: Double(screen.backingScaleFactor), refreshRate: screen.maximumFramesPerSecond,
                edrNow: Double(screen.maximumExtendedDynamicRangeColorComponentValue),
                edrPotential: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
                colorSpace: screen.colorSpace?.localizedName ?? "", isMain: screen == primary)
        }
    }

    private static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer).trimmingCharacters(in: .whitespaces)
    }

    static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// The memory Activity Monitor shows for the app.
    private static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// The most memory the app had (macOS gives `ru_maxrss` in bytes).
    private static func peakResidentSize() -> UInt64? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return UInt64(max(0, usage.ru_maxrss))
    }

    private static func threadCount() -> Int? {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return nil }
        let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(count))
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), size)
        return Int(count)
    }

    /// When this process started (`kinfo_proc.kp_proc.p_starttime`).
    static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
