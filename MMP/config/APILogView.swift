import SwiftUI

struct APILogView: View {
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss
    
    // 手动定义所有日志类型，并按照你想要的顺序排列
    private let allLogTypes: [LogType] = [.success, .error, .warning, .info, .network, .cache]
    
    // 使用 AppStorage 保存用户选择的日志类型
    @AppStorage("selectedLogTypes") private var storedSelectedLogTypes: String = ""
    
    // 选中的日志类型（默认从存储中恢复或全选）
    @State private var selectedLogTypes: Set<LogType> = []
    
    // 展开的日志类型
    @State private var expandedLogTypes: Set<LogType> = []
    
    // 按类型分组的日志
    private var groupedLogs: [LogType: [LogEntry]] {
        Dictionary(grouping: fundService.logMessages) { $0.type }
    }
    
    // 过滤后的日志类型（只显示选中的类型），并保持指定的顺序
    private var filteredLogTypes: [LogType] {
        allLogTypes.filter { selectedLogTypes.contains($0) }
    }
    
    // 检查是否全选
    private var isAllSelected: Bool {
        selectedLogTypes.count == allLogTypes.count
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 日志类型筛选器 - 优化布局
                VStack(spacing: 12) {
                    // 第一行 - 成功、错误、警告、信息
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
                    
                    // 第二行 - 网络、缓存，全选按钮
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
                        
                        // 占位按钮，确保对齐
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
                        
                        // 全选按钮 - 使用与LogTypeToggle相同的样式
                        Button(action: {
                            toggleAllSelection()
                            saveSelectedLogTypes()
                        }) {
                            HStack(spacing: 4) {
                                // 选中状态指示器
                                Image(systemName: isAllSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isAllSelected ? .blue : .gray)
                                    .font(.system(size: 14))
                                
                                // 类型名称
                                Text("全选")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                
                                // 颜色标识点 (使用蓝色)
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
                
                // 日志内容区域
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
                            // 遍历 filteredLogTypes，它已经按照你指定的顺序排列
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
                // 在视图出现时恢复用户选择
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
    
    // 保存用户选择的日志类型
    private func saveSelectedLogTypes() {
        let selectedTypesArray = Array(selectedLogTypes).map { $0.rawValue }
        if let encoded = try? JSONEncoder().encode(selectedTypesArray) {
            storedSelectedLogTypes = String(data: encoded, encoding: .utf8) ?? ""
        }
    }
    
    // 恢复用户选择的日志类型
    private func restoreSelectedLogTypes() {
        if let data = storedSelectedLogTypes.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            selectedLogTypes = Set(decoded.compactMap { LogType(rawValue: $0) })
        } else {
            // 如果没有保存的选择，默认全选
            selectedLogTypes = Set(allLogTypes)
        }
    }
}

// 日志类型切换组件
struct LogTypeToggle: View {
    let logType: LogType
    @Binding var isSelected: Bool
    let color: Color
    
    var body: some View {
        Button(action: {
            isSelected.toggle()
        }) {
            HStack(spacing: 4) {
                // 选中状态指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? color : .gray)
                    .font(.system(size: 14))
                
                // 类型名称
                Text(logType.displayName)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                // 颜色标识点
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

// 日志类型卡片组件
struct LogTypeCard: View {
    let logType: LogType
    let logs: [LogEntry]
    let color: Color
    let maxVisibleItems: Int
    @Binding var isExpanded: Bool
    
    // 估算的日志项高度
    private let estimatedItemHeight: CGFloat = 50
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏
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
            
            // 日志内容
            VStack(alignment: .leading, spacing: 8) {
                if isExpanded {
                    // 展开状态 - 显示所有日志，但限制最大高度
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(logs.reversed()) { log in
                                LogItemView(log: log)
                            }
                        }
                    }
                    .frame(maxHeight: 300) // 限制最大高度，防止占用整个屏幕
                } else {
                    // 折叠状态 - 显示有限数量的日志
                    ForEach(logs.prefix(maxVisibleItems).reversed()) { log in
                        LogItemView(log: log)
                    }
                }
                
                // 如果日志数量超过最大显示数量，显示展开/折叠按钮
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

// 单条日志项组件
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

// 为 LogType 添加显示名称扩展
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

// 隐藏视图的扩展
extension View {
    func hidden(_ shouldHide: Bool = true) -> some View {
        opacity(shouldHide ? 0 : 1)
    }
}
