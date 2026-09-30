import SwiftUI

struct ActivityLogTab: View {
    @ObservedObject var store = LogStore.shared
    @State private var copied = false
    @State private var failuresOnly = false

    private var visibleEntries: [LogEntry] {
        failuresOnly ? store.entries.filter { $0.kind == .failure } : store.entries
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Picker("Show", selection: $failuresOnly) {
                    Text("All").tag(false)
                    Text("Failures").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()

                Text("\(visibleEntries.count) entries")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(action: copyLog) {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.borderless)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                } label: {
                    Label("Log File", systemImage: "folder")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Show the saved log in Finder")

                Button("Clear") { store.clear() }
                    .buttonStyle(.borderless).font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(visibleEntries) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: visibleEntries.last?.id) { _, lastID in
                    if let lastID { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))

            // Legend
            HStack(spacing: 16) {
                LegendItem(color: .primary.opacity(0.5), label: "Info")
                LegendItem(color: .green, label: "Success")
                LegendItem(color: .red, label: "Failed")
                Spacer()
                Text("Saved to ~/Library/Logs/Spotlight Off")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }

    private func copyLog() {
        let text = visibleEntries.map { "[\($0.timestamp)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
        }
    }
}

struct LogRow: View {
    let entry: LogEntry

    var textColor: Color {
        switch entry.kind {
        case .info:    return Color(NSColor.secondaryLabelColor)
        case .success: return .green
        case .failure: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("[\(entry.timestamp)]")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .fixedSize()
            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}
