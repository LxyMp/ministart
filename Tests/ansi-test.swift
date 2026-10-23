// Compiles the shipped ANSI interpreter, so a streamed log can't lose real output.
import AppKit

/// The view's run record, restated minimally so the harness compiles the interpreter alone.
struct CommandRun: Identifiable {
    let id = UUID()
    var generation = 0
    var revision = 0
    var log = ""
    var delta = ""
}

@main
@MainActor
struct AnsiTest {
    static var failures = 0

    static func check(_ description: String, _ condition: Bool) {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    static func main() {
        splitSequence()
        sgrParameters()
        truncatedOscWaits()
        carriageRewind()
        colourCarriesAcrossChunks()
        extendedColourStaysInStep()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    static func colour(_ storage: NSTextStorage, at index: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    static func isBold(_ storage: NSTextStorage, at index: Int) -> Bool {
        guard let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    /// The reported defect: a flush every few bytes splits a CSI sequence in half.
    static func splitSequence() {
        var interpreter = ANSIInterpreter()
        let storage = NSTextStorage()
        interpreter.render("downloading \u{1B}[", into: storage, font: font)
        interpreter.render("31mred", into: storage, font: font)
        check(
            "a colour sequence split across chunks loses no text",
            storage.string == "downloading red")
        check(
            "…and still colours the text after it",
            colour(storage, at: 13) == NSColor.systemRed && colour(storage, at: 0) == NSColor.labelColor)
    }

    static func sgrParameters() {
        var interpreter = ANSIInterpreter()
        let storage = NSTextStorage()
        interpreter.render("\u{1B}[1;31mhot\u{1B}[0mplain", into: storage, font: font)
        check("semicolon parameters apply together", storage.string == "hotplain")
        check(
            "…and reset returns to the default face",
            colour(storage, at: 0) == NSColor.systemRed && isBold(storage, at: 0)
                && colour(storage, at: 3) == NSColor.labelColor && !isBold(storage, at: 3))
    }

    static func truncatedOscWaits() {
        var interpreter = ANSIInterpreter()
        let storage = NSTextStorage()
        interpreter.render("\u{1B}]0;partial ti", into: storage, font: font)
        interpreter.render("tle\u{07}visible", into: storage, font: font)
        check(
            "an OSC split across chunks never leaks its title as text",
            storage.string == "visible")
    }

    static func carriageRewind() {
        var interpreter = ANSIInterpreter()
        let storage = NSTextStorage()
        interpreter.render("frame 1\n10%", into: storage, font: font)
        interpreter.render("\r99%", into: storage, font: font)
        check("a carriage return redraws its line in place", storage.string == "frame 1\n99%")
    }

    static func colourCarriesAcrossChunks() {
        var interpreter = ANSIInterpreter()
        let storage = NSTextStorage()
        interpreter.render("\u{1B}[31m", into: storage, font: font)
        interpreter.render("still red", into: storage, font: font)
        check("a colour set in one chunk governs the next", colour(storage, at: 0) == NSColor.systemRed)
    }

    static func extendedColourStaysInStep() {
        var interpreter = ANSIInterpreter()
        let storage = NSTextStorage()
        interpreter.render("\u{1B}[38;5;196mX\u{1B}[1mY", into: storage, font: font)
        check(
            "an extended colour's parameters are skipped, keeping later codes in step",
            storage.string == "XY" && isBold(storage, at: 1) && !isBold(storage, at: 0))
    }
}
