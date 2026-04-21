import Foundation
import QuietTermCore
import SwiftTerm
import SwiftUI
import UIKit

struct SwiftTermRendererView: UIViewRepresentable {
    let session: TerminalSession
    let fixtureStream: TerminalFixtureStream

    init(
        session: TerminalSession,
        fixtureStream: TerminalFixtureStream? = nil
    ) {
        self.session = session
        self.fixtureStream = fixtureStream ?? Self.defaultFixtureStream()
    }

    func makeUIView(context: Context) -> QuietTermTerminalHostView {
        let view = QuietTermTerminalHostView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.configureForQuietTerm()
        context.coordinator.configure(session: session)

        DispatchQueue.main.async {
            view.feedFixtureIfNeeded(fixtureStream)
            view.updateSizeIfNeeded()
        }

        return view
    }

    func updateUIView(_ uiView: QuietTermTerminalHostView, context: Context) {
        context.coordinator.configure(session: session)
        uiView.feedFixtureIfNeeded(fixtureStream)
        uiView.updateSizeIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func defaultFixtureStream() -> TerminalFixtureStream {
        if ProcessInfo.processInfo.environment["QUIET_TERM_SCROLLBACK_SMOKE"] == "1" {
            return TerminalFixtureStream(
                chunks: TerminalFixtureStream.kan21Demo.chunks + TerminalFixtureStream.scrollbackSmoke().chunks
            )
        }

        return .kan21Demo
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        private var session: TerminalSession?
        private(set) var resizeEvents: [TerminalResizeEvent] = []

        func configure(session: TerminalSession) {
            self.session = session
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            resizeEvents.append(TerminalResizeEvent(columns: newCols, rows: newRows))
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            // KAN-21 is output rendering only; keyboard/input dispatch belongs to KAN-22.
        }

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

        func bell(source: TerminalView) {}

        func clipboardCopy(source: TerminalView, content: Data) {}

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

final class QuietTermTerminalHostView: TerminalView {
    private var hasFedFixture = false
    private var pendingFixtureStream: TerminalFixtureStream?
    private var lastAppliedSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSizeIfNeeded()
    }

    func configureForQuietTerm() {
        backgroundColor = .black
        nativeBackgroundColor = .black
        nativeForegroundColor = .white
        caretColor = .systemGreen
        selectedTextBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.35)
        font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        allowMouseReporting = false
        optionAsMetaKey = true
        linkReporting = .none
        changeScrollback(TerminalRendererDefaults.scrollbackLineLimit)
    }

    func feedFixtureIfNeeded(_ fixtureStream: TerminalFixtureStream) {
        guard !hasFedFixture else {
            return
        }

        guard bounds.width.isFinite,
              bounds.width > 0,
              bounds.height.isFinite,
              bounds.height > 0 else {
            pendingFixtureStream = fixtureStream
            return
        }

        hasFedFixture = true
        pendingFixtureStream = nil
        changeScrollback(TerminalRendererDefaults.scrollbackLineLimit)

        for chunk in fixtureStream.chunks {
            feed(byteArray: chunk.bytes[...])
        }
    }

    func updateSizeIfNeeded() {
        let newSize = bounds.size
        guard newSize.width.isFinite,
              newSize.width > 0,
              newSize.height.isFinite,
              newSize.height > 0 else {
            return
        }

        if newSize != lastAppliedSize {
            lastAppliedSize = newSize
            let cellSize = Self.terminalCellSize(for: font)
            let gridSize = TerminalGridSize(
                viewportWidth: Double(newSize.width),
                viewportHeight: Double(newSize.height),
                cellWidth: Double(cellSize.width),
                cellHeight: Double(cellSize.height)
            )
            resize(cols: gridSize.columns, rows: gridSize.rows)
        }

        if let pendingFixtureStream {
            feedFixtureIfNeeded(pendingFixtureStream)
        }
    }

    private static func terminalCellSize(for font: UIFont) -> CGSize {
        let glyphSize = ("W" as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: max(1, ceil(glyphSize.width)),
            height: max(1, ceil(font.lineHeight))
        )
    }
}
