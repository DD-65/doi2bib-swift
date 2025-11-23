import SwiftUI
import AppKit   // Needed for NSPasteboard on macOS

struct ClipboardView: View {
    @State private var text: String = ""
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Copy")
                .font(.headline)

            TextField("Type text to copy…", text: $text)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button {
                    copyToClipboard(text)
                    copied = true
                } label: {
                    Label(
                        copied ? "Copied!" : "Copy to Clipboard",
                        systemImage: "doc.on.doc"
                    )
                }
                .keyboardShortcut(.return, modifiers: []) // Press Enter to copy
                .disabled(text.isEmpty)
            }
        }
        .onChange(of: text) { _ in
            // Reset “Copied!” label when user edits text again
            copied = false
        }
    }
}

// MARK: - Clipboard helper

private func copyToClipboard(_ string: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
}
