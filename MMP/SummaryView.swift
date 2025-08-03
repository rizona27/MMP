import SwiftUI
import Foundation

// MARK: - 新增通用的 Toast 视图，用于提示刷新完成
struct ToastView: View {
    var message: String
    @Binding var isShowing: Bool

    var body: some View {
        if isShowing {
            Text(message)
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            isShowing = false
                        }
                    }
                }
        }
    }
}

// 收益率排序维度枚举
enum SortKey: String, CaseIterable, Identifiable {
    case none = "无排序"
    case navReturn1m = "近1月"
    case navReturn3m = "近3月"
    case navReturn6m = "近6月"
    case navReturn1y = "近1年"

    var id: String { self.rawValue }
    
    // 用于获取对应 KeyPath 的字符串
    var keyPathString: String? {
        switch self {
        case .navReturn1m: return "navReturn1m"
        case .navReturn3m: return "navReturn3m"
        case .navReturn6m: return "navReturn6m"
        case .navReturn1y: return "navReturn1y"
        case .none: return nil
        }
    }

    var next: SortKey {
        switch self {
        case .none: return .navReturn1m
        case .navReturn1m: return .navReturn3m
        case .navReturn3m: return .navReturn6m
        case .navReturn6m: return .navReturn1y
        case .navReturn1y: return .none
        }
    }
}

// 排序顺序枚举
enum SortOrder: String, CaseIterable, Identifiable {
    case ascending = "升序"
    case descending = "降序"

    var id: String { self.rawValue }
}

// 扩展Color，用于计算亮度并决定文本颜色
extension Color {
    func luminance() -> Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        let uiColor = UIColor(self)
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let luminance = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
        return luminance
    }
    
    func textColorBasedOnLuminance() -> Color {
        return self.luminance() > 0.5 ? .black : .white
    }
}

// MARK: - SummaryView
struct SummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService

    @State private var isRefreshing = false
    @State private var unrecognizedFunds: [FundHolding] = []
    @State private var showingToast = false

    // 排序状态
    @State private var selectedSortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending
    
    // 追踪展开的基金卡片
    @State private var expandedFunds: Set<UUID> = []

    // 持久化存储未识别基金
    private var persistentUnrecognizedFunds: [FundHolding] {
        if let data = UserDefaults.standard.data(forKey: "unrecognizedFunds"),
           let decoded = try? JSONDecoder().decode([FundHolding].self, from: data) {
            return decoded
        }
        return []
    }

    // 保存未识别基金
    private func saveUnrecognizedFunds() {
        if let encoded = try? JSONEncoder().encode(unrecognizedFunds) {
            UserDefaults.standard.set(encoded, forKey: "unrecognizedFunds")
        }
    }

    // 已识别基金（参与排序）
    private var recognizedFunds: [FundHolding] {
        let unrecognizedFundCodes = Set(unrecognizedFunds.map { $0.fundCode })

        var funds = dataManager.holdings.filter { holding in
            !unrecognizedFundCodes.contains(holding.fundCode)
        }

        if selectedSortKey != .none {
            funds.sort { (fund1, fund2) in
                let value1 = getSortValue(for: fund1, key: selectedSortKey)
                let value2 = getSortValue(for: fund2, key: selectedSortKey)

                if value1 != nil && value2 == nil {
                    return true
                } else if value1 == nil && value2 != nil {
                    return false
                } else if value1 == nil && value2 == nil {
                    return fund1.fundCode < fund2.fundCode
                }

                if sortOrder == .ascending {
                    return value1! < value2!
                } else {
                    return value1! > value2!
                }
            }
        } else {
            funds.sort { $0.fundCode < $1.fundCode }
        }

        return funds
    }

    // 获取排序值
    private func getSortValue(for fund: FundHolding, key: SortKey) -> Double? {
        switch key {
        case .navReturn1m: return fund.navReturn1m
        case .navReturn3m: return fund.navReturn3m
        case .navReturn6m: return fund.navReturn6m
        case .navReturn1y: return fund.navReturn1y
        case .none: return nil
        }
    }
    
    // 计算持有收益率
    private func getHoldingReturn(for fund: FundHolding) -> Double? {
        guard fund.purchaseAmount > 0 else { return nil }
        return (fund.totalValue - fund.purchaseAmount) / fund.purchaseAmount * 100
    }

    // 获取排序按钮的图标
    private func sortButtonIconName() -> String {
        switch selectedSortKey {
        case .none: return "line.3.horizontal.decrease.circle"
        case .navReturn1m: return "calendar"
        case .navReturn3m: return "calendar.day.timeline.leading"
        case .navReturn6m: return "calendar.day.timeline.trailing"
        case .navReturn1y: return "calendar.badge.clock"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // 排序按钮 (图标形式)
                    Button(action: {
                        withAnimation {
                            selectedSortKey = selectedSortKey.next
                        }
                    }) {
                        HStack {
                            Image(systemName: sortButtonIconName())
                                .foregroundColor(.primary)
                            if selectedSortKey != .none {
                                Text(selectedSortKey.rawValue)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }

                    // 增/降序切换按钮
                    if selectedSortKey != .none {
                        Button(action: {
                            withAnimation {
                                sortOrder = (sortOrder == .ascending) ? .descending : .ascending
                            }
                        }) {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        }
                    }
                    
                    Spacer()

                    // 刷新按钮 (右上角)
                    Button(action: refreshFundReturns) {
                        HStack {
                            if isRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .disabled(isRefreshing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
                
                List {
                    if dataManager.holdings.isEmpty && unrecognizedFunds.isEmpty {
                        Text("当前没有基金持仓数据")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(recognizedFunds) { fund in
                            FundHoldingCard(
                                fund: fund,
                                isExpanded: Binding(
                                    get: { expandedFunds.contains(fund.id) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedFunds.insert(fund.id)
                                        } else {
                                            expandedFunds.remove(fund.id)
                                        }
                                    }
                                ),
                                selectedSortKey: selectedSortKey,
                                getHoldingReturn: getHoldingReturn
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        
                        if !unrecognizedFunds.isEmpty {
                            ForEach(unrecognizedFunds, id: \.fundCode) { fund in
                                UnrecognizedFundCard(fund: fund, removeAction: removeUnrecognizedFund)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationBarHidden(true)
            .onAppear {
                unrecognizedFunds = persistentUnrecognizedFunds
            }
            
            ToastView(message: "刷新成功！", isShowing: $showingToast)
                .padding(.bottom, 80)
        }
    }
    
    // MARK: - 操作方法

    private func refreshFundReturns() {
        isRefreshing = true
        fundService.addLog("开始刷新基金收益率数据...")

        let persistentUnrecognized = persistentUnrecognizedFunds
        var newUnrecognizedFunds = persistentUnrecognized

        let uniqueFundCodes = Set(dataManager.holdings.map { $0.fundCode })
        let originalHoldings = dataManager.holdings

        Task {
            var updatedHoldings: [FundHolding] = []
            var fetchedUnrecognized: [FundHolding] = []

            await withTaskGroup(of: (FundHolding, Bool).self) { group in
                for code in uniqueFundCodes {
                    group.addTask {
                        var holding = await fundService.fetchFundInfo(code: code)

                        if let original = originalHoldings.first(where: { $0.fundCode == code }) {
                            holding.clientName = original.clientName
                            holding.clientID = original.clientID
                            holding.purchaseAmount = original.purchaseAmount
                            holding.purchaseShares = original.purchaseShares
                            holding.purchaseDate = original.purchaseDate
                            holding.remarks = original.remarks
                        }

                        let isValid = holding.navReturn1m != nil || holding.navReturn3m != nil ||
                                      holding.navReturn6m != nil || holding.navReturn1y != nil

                        return (holding, isValid)
                    }
                }

                for await (holding, isValid) in group {
                    if isValid {
                        updatedHoldings.append(holding)
                    } else {
                        if !fetchedUnrecognized.contains(where: { $0.fundCode == holding.fundCode }) {
                            fetchedUnrecognized.append(holding)
                        }
                    }
                }
            }

            await MainActor.run {
                for fund in fetchedUnrecognized {
                    if !newUnrecognizedFunds.contains(where: { $0.fundCode == fund.fundCode }) {
                        newUnrecognizedFunds.append(fund)
                    }
                }

                dataManager.holdings = updatedHoldings
                unrecognizedFunds = newUnrecognizedFunds

                dataManager.saveData()
                saveUnrecognizedFunds()
                isRefreshing = false
                fundService.addLog("基金收益率刷新完成")
                withAnimation {
                    showingToast = true
                }
            }
        }
    }

    private func removeUnrecognizedFund(fundCode: String) {
        unrecognizedFunds.removeAll { $0.fundCode == fundCode }
        saveUnrecognizedFunds()
    }
}

// 独立的基金卡片视图
struct FundHoldingCard: View {
    var fund: FundHolding
    @Binding var isExpanded: Bool
    var selectedSortKey: SortKey
    var getHoldingReturn: (FundHolding) -> Double?
    
    private var baseColor: Color {
        fund.fundCode.morandiColor()
    }
    
    // MARK: - 辅助方法
    
    private func colorForValue(_ value: String) -> Color {
        guard let number = Double(value.replacingOccurrences(of: "%", with: "")) else {
            return .primary
        }

        if number > 0 {
            return .red
        } else if number < 0 {
            return .green
        } else {
            return .primary
        }
    }

    private func getColumnValue(for fund: FundHolding, keyPath: String?) -> String {
        guard let keyPath = keyPath else { return "/" }
        switch keyPath {
        case "navReturn1m": return fund.navReturn1m?.formattedPercentage ?? "/"
        case "navReturn3m": return fund.navReturn3m?.formattedPercentage ?? "/"
        case "navReturn6m": return fund.navReturn6m?.formattedPercentage ?? "/"
        case "navReturn1y": return fund.navReturn1y?.formattedPercentage ?? "/"
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 卡片头部 (可点击区域)
            HStack(alignment: .center) {
                // 左侧基金名称和代码，带渐变背景
                HStack(spacing: 8) {
                    Text("**\(fund.fundName)**") // 这行代码将文字加粗
                        .font(.subheadline)
                        .foregroundColor(baseColor.textColorBasedOnLuminance())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(fund.fundCode)
                        .font(.caption.monospaced())
                        .foregroundColor(baseColor.textColorBasedOnLuminance().opacity(0.8))
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [baseColor, .white]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                // 右侧收益率（仅在选择排序时显示）
                if selectedSortKey != .none {
                    VStack(alignment: .trailing) {
                        Text(getColumnValue(for: fund, keyPath: selectedSortKey.keyPathString))
                            .font(.headline)
                            .foregroundColor(colorForValue(getColumnValue(for: fund, keyPath: selectedSortKey.keyPathString)))
                    }
                    .padding(.horizontal, 16)
                }
                
                // 展开/折叠箭头
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
            }
            .contentShape(Rectangle()) // 使整个卡片区域可点击
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            
            // 展开后的内容
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // 净值收益率列表
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("近1月收益率: \(fund.navReturn1m?.formattedPercentage ?? "/")")
                                .foregroundColor(colorForValue(fund.navReturn1m?.formattedPercentage ?? ""))
                            Text("近3月收益率: \(fund.navReturn3m?.formattedPercentage ?? "/")")
                                .foregroundColor(colorForValue(fund.navReturn3m?.formattedPercentage ?? ""))
                            Text("近6月收益率: \(fund.navReturn6m?.formattedPercentage ?? "/")")
                                .foregroundColor(colorForValue(fund.navReturn6m?.formattedPercentage ?? ""))
                            Text("近1年收益率: \(fund.navReturn1y?.formattedPercentage ?? "/")")
                                .foregroundColor(colorForValue(fund.navReturn1y?.formattedPercentage ?? ""))
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    Divider()
                    
                    // 持有客户信息和收益率
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("持有客户: \(fund.clientName)")
                                .font(.subheadline)
                            if let holdingReturn = getHoldingReturn(fund) {
                                Text("持有收益率: \(holdingReturn.formattedPercentage)")
                                    .foregroundColor(colorForValue(holdingReturn.formattedPercentage))
                                    .font(.subheadline)
                            }
                        }
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// 独立的未识别基金卡片
struct UnrecognizedFundCard: View {
    var fund: FundHolding
    var removeAction: (String) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading) {
                Text("未能识别: \(fund.fundName.isEmpty ? "未知基金" : fund.fundName)")
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(fund.fundCode)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            
            Spacer()
            
            Button("移除") {
                removeAction(fund.fundCode)
            }
            .foregroundColor(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray5))
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// 扩展Double格式化百分比
extension Double {
    var formattedPercentage: String {
        String(format: "%.2f%%", self)
    }
}

// Preview Provider
struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryView()
            .environmentObject(DataManager())
            .environmentObject(FundService())
    }
}
