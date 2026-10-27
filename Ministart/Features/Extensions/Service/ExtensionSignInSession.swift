import AppKit
import AuthenticationServices

/// One browser sign-in. It catches its own redirect, so an installed Raycast cannot take it.
@MainActor
final class ExtensionSignInSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: LocalizedError {
        case cancelled

        var errorDescription: String? { "Sign-in was cancelled." }
    }

    private nonisolated let anchor: ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    override init() {
        anchor = NSApp.keyWindow ?? ASPresentationAnchor()
    }

    /// Resolves with the redirect URL; cancelling the task closes the browser window.
    /// `ASWebAuthenticationSession.cancel()` does not always invoke the completion handler,
    /// so task cancellation resumes the continuation itself — exactly once, whichever side
    /// gets there first.
    func run(url: URL, callbackScheme: String) async throws -> URL {
        let box = ResumeOnce()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.setContinuation(continuation)
                let session = ASWebAuthenticationSession(
                    url: url, callback: .customScheme(callbackScheme)
                ) { @Sendable redirect, error in
                    if let redirect {
                        box.resume(returning: redirect)
                    } else if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        box.resume(throwing: error)
                    } else {
                        box.resume(throwing: Failure.cancelled)
                    }
                }
                session.presentationContextProvider = self
                self.session = session
                session.start()
                if Task.isCancelled {
                    Task { @MainActor in self.session?.cancel() }
                    box.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.session?.cancel()
                box.resume(throwing: CancellationError())
            }
        }
    }
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

/// A checked continuation that resumes exactly once, whichever path reaches it first.
@MainActor
private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var resumed = false

    func setContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: URL) {
        finish { $0.resume(returning: value) }
    }

    func resume(throwing error: Error) {
        finish { $0.resume(throwing: error) }
    }

    private func finish(_ body: (CheckedContinuation<URL, Error>) -> Void) {
        assert(Thread.isMainThread)
        guard !resumed, let continuation else { return }
        resumed = true
        self.continuation = nil
        body(continuation)
    }
}

