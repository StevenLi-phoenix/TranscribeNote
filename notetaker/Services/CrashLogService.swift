import Darwin
import Foundation
import os

/// Pre-computed C file path for the crash log, set at `install()` time.
/// Stored as a global so the signal handler can access it without Swift runtime calls.
nonisolated(unsafe) private var signalCrashLogCPath: UnsafeMutablePointer<CChar>?

/// Top-level C-compatible signal handler (cannot capture context).
/// Uses only async-signal-safe POSIX calls — no Swift runtime, no Foundation, no heap allocation.
nonisolated private func handleSignal(_ signalNumber: Int32) {
    guard let cPath = signalCrashLogCPath else {
        // No path available — re-raise with default handler
        signal(signalNumber, SIG_DFL)
        raise(signalNumber)
        return
    }

    let fd = open(cPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if fd >= 0 {
        // Write "Signal: " header
        let header: StaticString = "Signal: "
        header.withUTF8Buffer { buf in
            _ = write(fd, buf.baseAddress, buf.count)
        }

        // Write signal number as ASCII digits (async-signal-safe)
        writeInt32AsASCII(fd: fd, value: signalNumber)

        let newline: StaticString = "\n"
        newline.withUTF8Buffer { buf in
            _ = write(fd, buf.baseAddress, buf.count)
        }

        close(fd)
    }

    signal(signalNumber, SIG_DFL)
    raise(signalNumber)
}

/// Writes an Int32 as decimal ASCII digits to a file descriptor.
/// Async-signal-safe: uses only stack memory and the `write` syscall.
nonisolated private func writeInt32AsASCII(fd: Int32, value: Int32) {
    var val = value
    if val < 0 {
        let minus: StaticString = "-"
        minus.withUTF8Buffer { buf in
            _ = write(fd, buf.baseAddress, buf.count)
        }
        val = -val
    }

    // Int32 max is 2147483647 — 10 digits + null
    var buf: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var pos = 10 // write digits from end

    if val == 0 {
        buf.10 = 0x30 // '0'
        pos = 10
    } else {
        while val > 0 {
            withUnsafeMutableBytes(of: &buf) { ptr in
                ptr[pos] = UInt8(val % 10) + 0x30 // '0'
            }
            val /= 10
            pos -= 1
        }
        pos += 1 // point to first digit
    }

    withUnsafeBytes(of: &buf) { ptr in
        _ = write(fd, ptr.baseAddress! + pos, 11 - pos)
    }
}

/// Top-level C-compatible exception handler (cannot capture context).
nonisolated private func handleUncaughtException(_ exception: NSException) {
    CrashLogService.writeExceptionCrashLog(exception)
}

nonisolated enum CrashLogService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "CrashLog")

    private static var crashLogDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("notetaker/CrashLogs", isDirectory: true)
    }

    private static var crashLogFile: URL {
        crashLogDirectory.appendingPathComponent("last_crash.log")
    }

    static func install() {
        // Check for previous crash log
        checkPreviousCrash()

        // Create crash log directory eagerly so signal handler doesn't need to
        try? FileManager.default.createDirectory(at: crashLogDirectory, withIntermediateDirectories: true)

        // Pre-compute crash log path as a C string for the signal handler.
        // Intentional leak: strdup'd pointer must live for the process lifetime.
        let path = crashLogFile.path
        let cPath = strdup(path)
        signalCrashLogCPath = cPath
        logger.debug("Crash log path: \(path)")

        // Install ObjC exception handler (non-capturing top-level function)
        NSSetUncaughtExceptionHandler(handleUncaughtException)

        // Install POSIX signal handlers (non-capturing — calls top-level function)
        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP]
        for sig in signals {
            signal(sig, handleSignal)
        }

        logger.info("Crash log handlers installed")
    }

    /// Called from the top-level exception handler.
    /// Runs in normal Objective-C runtime context — safe to use Swift/Foundation.
    fileprivate static func writeExceptionCrashLog(_ exception: NSException) {
        let info = """
        Uncaught Exception: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "unknown")
        Stack: \(exception.callStackSymbols.joined(separator: "\n"))
        Date: \(Date())
        """
        writeCrashLog(info)
    }

    /// Best-effort crash log write for exception handler context.
    private static func writeCrashLog(_ content: String) {
        try? FileManager.default.createDirectory(at: crashLogDirectory, withIntermediateDirectories: true)
        try? content.write(to: crashLogFile, atomically: true, encoding: .utf8)
    }

    private static func checkPreviousCrash() {
        let file = crashLogFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }

        do {
            let content = try String(contentsOf: file, encoding: .utf8)
            logger.warning("Previous crash detected:\n\(content)")
            try FileManager.default.removeItem(at: file)
        } catch {
            logger.error("Failed to read/clean crash log: \(error.localizedDescription)")
        }
    }
}
