import SwiftUI

struct APILogView: View {
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss

    private let allLogTypes: [LogType] = [.success, .error, .warning, .info, .network, .cache]

    @AppStorage("selectedLogTypes") private var storedSelectedLogTypes: String = ""
    @State private var selectedLogTypes: Set<LogType> = []
    @State private var expandedLogTypes: Set<LogType> = []
    private var groupedLogs: [LogType: [LogEntry]] {
        Dictionary(grouping: fundService.logMessages) { $0.type }
    }

    private var filteredLogTypes: [LogType] {
        allLogTypes.filter { selectedLogTypes.contains($0) }
    }

    private var isAllSelected: Bool {
        selectedLogTypes.count == allLogTypes.count
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach([LogType.success, .error, .warning, .info], id: \.self) { logType in
                            LogTypeToggle(
                                logType: logType,
                                isSelected: Binding(
                                    get: { selectedLogTypes.contains(logType) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedLogTypes.insert(logType)
                                        } else {
                                            selectedLogTypes.remove(logType)
                                        }
                                        saveSelectedLogTypes()
                                    }
                                ),
                                color: color(for: logType)
                            )
                        }
                    }
                    
                    HStack(spacing: 8) {
                        ForEach([LogType.network, .cache], id: \.self) { logType in
                            LogTypeToggle(
                                logType: logType,
                                isSelected: Binding(
                                    get: { selectedLogTypes.contains(logType) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedLogTypes.insert(logType)
                                        } else {
                                            selectedLogTypes.remove(logType)
                                        }
                                        saveSelectedLogTypes()
                                    }
                                ),
                                color: color(for: logType)
                            )
                        }

                        Button(action: {}) {
                            HStack(spacing: 4) {
                                Image(systemName: "circle")
                                    .foregroundColor(.clear)
                                    .font(.system(size: 14))
                                Text("占位")
                                    .font(.caption)
                                    .foregroundColor(.clear)
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 6, height: 6)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(true)
                        .hidden()

                        Button(action: {
                            toggleAllSelection()
                            saveSelectedLogTypes()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isAllSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isAllSelected ? .blue : .gray)
                                    .font(.system(size: 14))

                                Text("全选")
                                    .font(.caption)
                                    .foregroundColor(.primary)

                                Circle()
                                    .fill(.blue)
                                    .frame(width: 6, height: 6)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isAllSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isAllSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundColor(.gray.opacity(0.5))
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                Divider()

                if fundService.logMessages.isEmpty {
                    Spacer()
                    Text("暂无API查询日志。")
                        .foregroundColor(.gray)
                    Spacer()
                } else if filteredLogTypes.isEmpty {
                    Spacer()
                    Text("请至少选择一种日志类型")
                        .foregroundColor(.gray)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredLogTypes, id: \.self) { logType in
                                if let logs = groupedLogs[logType], !logs.isEmpty {
                                    LogTypeCard(
                                        logType: logType,
                                        logs: logs,
                                        color: color(for: logType),
                                        maxVisibleItems: 3,
                                        isExpanded: Binding(
                                            get: { expandedLogTypes.contains(logType) },
                                            set: { isExpanded in
                                                if isExpanded {
                                                    expandedLogTypes.insert(logType)
                                                } else {
                                                    expandedLogTypes.remove(logType)
                                                }
                                            }
                                        )
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        fundService.logMessages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .onAppear {
                restoreSelectedLogTypes()
            }
        }
    }
    
    private func toggleAllSelection() {
        if isAllSelected {
            selectedLogTypes.removeAll()
        } else {
            selectedLogTypes = Set(allLogTypes)
        }
    }
    
    private func color(for type: LogType) -> Color {
        switch type {
        case .error:
            return .red
        case .success:
            return .green
        case .network:
            return .blue
        case .cache:
            return .purple
        case .info:
            return .orange
        case .warning:
            return .yellow
        }
    }

    private func saveSelectedLogTypes() {
        let selectedTypesArray = Array(selectedLogTypes).map { $0.rawValue }
        if let encoded = try? JSONEncoder().encode(selectedTypesArray) {
            storedSelectedLogTypes = String(data: encoded, encoding: .utf8) ?? ""
        }
    }

    private func restoreSelectedLogTypes() {
        if let data = storedSelectedLogTypes.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            selectedLogTypes = Set(decoded.compactMap { LogType(rawValue: $0) })
        } else {
            selectedLogTypes = Set(allLogTypes)
        }
    }
}

struct LogTypeToggle: View {
    let logType: LogType
    @Binding var isSelected: Bool
    let color: Color
    
    var body: some View {
        Button(action: {
            isSelected.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? color : .gray)
                    .font(.system(size: 14))
                Text(logType.displayName)
                    .font(.caption)
                    .foregroundColor(.primary)
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LogTypeCard: View {
    let logType: LogType
    let logs: [LogEntry]
    let color: Color
    let maxVisibleItems: Int
    @Binding var isExpanded: Bool

    private let estimatedItemHeight: CGFloat = 50
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                Text(logType.displayName)
                    .font(.headline)
                    .foregroundColor(color)
                
                Spacer()
                
                Text("(\(logs.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                if isExpanded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(logs.reversed()) { log in
                                LogItemView(log: log)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                } else {
                    ForEach(logs.prefix(maxVisibleItems).reversed()) { log in
                        LogItemView(log: log)
                    }
                }
                if logs.count > maxVisibleItems {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Text(isExpanded ? "折叠" : "展开全部 (\(logs.count) 条)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct LogItemView: View {
    let log: LogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(formattedTimestamp(log.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
                
                Text(log.message)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
        }
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

extension LogType {
    var displayName: String {
        switch self {
        case .error:
            return "错误"
        case .success:
            return "成功"
        case .network:
            return "网络"
        case .cache:
            return "缓存"
        case .info:
            return "信息"
        case .warning:
            return "警告"
        }
    }
}

extension View {
    func hidden(_ shouldHide: Bool = true) -> some View {
        opacity(shouldHide ? 0 : 1)
    }
}
