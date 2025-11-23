import SwiftUI

@main
struct ClipboardMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("BibTeX", systemImage: "doc.text") {
            BibtexView()
                .frame(width: 340, height: 190)
                .padding()
        }
        .menuBarExtraStyle(.window) // window-like popover from the menu bar icon
    }
}
