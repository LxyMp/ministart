import Foundation

/// The two surfaces stay reachable one way, and the clipboard is skipped when off.
@main
@MainActor
struct PaletteTabTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteTabAction, _ expected: PaletteTabAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func main() {
        expect(
            PaletteTabAction.resolve(mode: .launcher, clipboardEnabled: true),
            .carryQuery(.clipboard),
            "the launcher hands the typed text to the clipboard, one search narrowing both lists")
        expect(
            PaletteTabAction.resolve(mode: .clipboard, clipboardEnabled: true),
            .carryQuery(.launcher),
            "the clipboard closes the ring back to the launcher")

        // Off, the clipboard has no stop; the ring must not strand a reader on a dead screen.
        expect(
            PaletteTabAction.resolve(mode: .launcher, clipboardEnabled: false),
            .carryQuery(.launcher),
            "turned off, the clipboard is skipped and the launcher rings back onto itself")

        // A sub-screen is reached by a command or a hotkey, so Tab leaves rather than ringing on.
        for mode in [
            PaletteMode.emoji, .fileSearch, .calculatorHistory, .quicklinks, .snippets,
            .customCommands
        ] {
            expect(
                PaletteTabAction.resolve(mode: mode, clipboardEnabled: true),
                .carryQuery(.launcher),
                "\(mode.rawValue) is a sub-screen, so Tab exits to the launcher")
        }

        expect(
            PaletteTabAction.resolve(mode: .extensionCommand, clipboardEnabled: true),
            .carryQuery(.launcher),
            "an extension command exits to the launcher rather than joining the ring")

        // Two presses from the launcher have to land back on it, or the ring is a dead end.
        var mode = PaletteMode.launcher
        var visited: [PaletteMode] = []
        for _ in 0..<2 {
            switch PaletteTabAction.resolve(mode: mode, clipboardEnabled: true) {
            case .carryQuery(let next), .freshScreen(let next): mode = next
            }
            visited.append(mode)
        }
        if visited == [.clipboard, .launcher] {
            passes += 1
        } else {
            failures += 1
            print("FAIL: two presses ring back to the launcher — got \(visited)")
        }

        var offMode = PaletteMode.launcher
        var offVisited: [PaletteMode] = []
        for _ in 0..<2 {
            switch PaletteTabAction.resolve(mode: offMode, clipboardEnabled: false) {
            case .carryQuery(let next), .freshScreen(let next): offMode = next
            }
            offVisited.append(offMode)
        }
        if offVisited == [.launcher, .launcher] {
            passes += 1
        } else {
            failures += 1
            print("FAIL: turned off, both presses land back on the launcher — got \(offVisited)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
