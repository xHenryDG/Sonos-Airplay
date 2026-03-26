import SwiftUI

struct LogView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationView {
            List {
                if app.logs.isEmpty {
                    Text("Noch keine Einträge").foregroundColor(.secondary)
                        .font(.subheadline).padding(.vertical, 8)
                } else {
                    ForEach(app.logs) { e in
                        HStack(alignment: .top, spacing: 10) {
                            Text(e.icon)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(color(e.level))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.message)
                                    .font(.system(size: 13, design: .monospaced))
                                Text(fmt.string(from: e.date))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Leeren") { app.logs.removeAll() }.disabled(app.logs.isEmpty)
                }
            }
        }
    }

    private func color(_ l: LogEntry.Level) -> Color {
        switch l {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}
