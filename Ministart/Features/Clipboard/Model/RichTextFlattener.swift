import Foundation

/// HTML as the clipboard history keeps it: tags gone, block edges as newlines, entities decoded.
/// Foundation-only on purpose — `NSAttributedString(html:)` runs WebKit on the caller's thread.
enum RichTextFlattener {
    static func plainText(fromHTML html: String) -> String {
        // Regexes stay in the body: a stored one is shared mutable state to Swift 6.
        let scriptOrStyle = /(?i)<(?:script|style)\b[^>]*>[\s\S]*?<\/(?:script|style)>/
        let blockEdge = /(?i)<\/?(?:br|p|div|li)\b[^>]*>/
        let anyTag = /<[^>]+>/
        let withBreaks = html
            .replacing(scriptOrStyle, with: "")
            .replacing(blockEdge, with: "\n")
            .replacing(anyTag, with: "")
            .replacing(/\n{2,}/, with: "\n")
        return decodeEntities(in: withBreaks).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `&amp;` last, so an escaped entity in the source (`&amp;lt;`) stays escaped in the result.
    private static func decodeEntities(in text: String) -> String {
        var decoded = text.replacing(/&#x([0-9A-Fa-f]+);/) { match in
            String(Unicode.Scalar(UInt32(match.1, radix: 16) ?? 0xFFFD) ?? "\u{FFFD}")
        }
        decoded = decoded.replacing(/&#(\d+);/) { match in
            String(Unicode.Scalar(UInt32(match.1) ?? 0xFFFD) ?? "\u{FFFD}")
        }
        decoded = decoded.replacing(/&nbsp;/, with: " ")
        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
        ] {
            decoded = decoded.replacing(entity, with: character)
        }
        return decoded.replacing("&amp;", with: "&")
    }
}
