import Foundation
import QuietTermCore
import SwiftUI

#if canImport(SwiftTerm) && canImport(UIKit)
import SwiftTerm
import UIKit

struct SwiftTermRendererView: UIViewRepresentable {
    var sessionID: UUID
    var outputCounter: Int
    var drainOutput: () -> [Data]
    var sendInput: (Data) -> Void

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.backgroundColor = .black
        view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.accessibilityIdentifier = "quietterm.terminal"
        DispatchQueue.main.async {
            _ = view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.sendInput = sendInput
        for output in drainOutput() {
            uiView.feed(byteArray: Array(output)[...])
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sendInput: sendInput)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        var sendInput: (Data) -> Void

        init(sendInput: @escaping (Data) -> Void) {
            self.sendInput = sendInput
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            sendInput(Data(data))
        }

        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
#else
struct SwiftTermRendererView: View {
    var sessionID: UUID
    var outputCounter: Int
    var drainOutput: () -> [Data]
    var sendInput: (Data) -> Void

    var body: some View {
        Text("SwiftTerm is not linked in this build.")
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .background(Color.black)
            .foregroundStyle(Color.green)
    }
}
#endif
