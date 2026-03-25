import SwiftUI

struct LogView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationView {
            List {
                if app.logs.isEmpty {
                    Text("Noch keine Einträge")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else {
                    ForEach(app.logs) { entry in
                        LogRow(entry: entry)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Leeren") {
                        app.logs.removeAll()
                    }
                    .disabled(app.logs.isEmpty)
                }
            }
        }
    }
}

struct LogRow: View {
    let entry: LogEntry

    var color: Color {
        switch entry.level {
        case .info:    return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.icon)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.primary)
                Text(LogRow.fmt.string(from: entry.date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
