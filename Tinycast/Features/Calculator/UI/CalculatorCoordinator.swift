import AppKit

/// Owns copying a calculation out.
@MainActor
final class CalculatorCoordinator {
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// History records the canonical answer; only what reaches the pasteboard is localized.

    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(copyText)
    }

    /// `⌘↵` on the card: the answer becomes the query, so the next step chains onto it.
    @discardableResult
    func putAnswerInSearchBar(_ result: CalcResult) -> Bool {
        guard case .value(let display, let copyText) = result.payload, result.canChain,
            !core.palette.isComposing
        else { return false }
        core.palette.rewriteQuery(copyText)
        return true
    }

    func copyCalculationWithExpression(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(
            "\(result.expression) = \(copyText)")
    }

}
