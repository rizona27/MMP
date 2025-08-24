import SwiftUI
import Foundation // 用于 Date 的 Calendar

// MARK: - 通用辅助视图和枚举 (只保留未在 ClientView.swift 中定义的)

// 枚举 SortKey (保持不变)
enum SortKey: String, CaseIterable, Identifiable {
    case none = "无排序"
    case navReturn1m = "近1月"
    case navReturn3m = "近3月"
    case navReturn6m = "近6月"
    case navReturn1y = "近1年"

    var id: String { self.rawValue }
    
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

// 枚举 SortOrder (保持不变)
enum SortOrder: String, CaseIterable, Identifiable {
    case ascending = "升序"
    case descending = "降序"

    var id: String { self.rawValue }
}

// MARK: - SummaryView
struct SummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService

    @State private var isRefreshing = false
    @State private var unrecognizedFunds: [FundHolding] = []
    @State private var showingToast = false
    @State private var isRefreshingAllUnrecognizedFunds = false
    
    @State private var selectedSortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending
    
    @State private var expandedFundCodes: Set<String> = []
    
    @State private var isUnrecognizedFundsSectionExpanded: Bool = true
    @State private var refreshProgressText: String = ""
    
    private let calendar = Calendar.current

    private var persistentUnrecognizedFunds: [FundHolding] {
        if let data = UserDefaults.standard.data(forKey: "unrecognizedFunds"),
           let decoded = try? JSONDecoder().decode([FundHolding].self, from: data) {
            return decoded
        }
        return []
    }

    private func saveUnrecognizedFunds() {
        if let encoded = try? JSONEncoder().encode(unrecognizedFunds) {
            UserDefaults.standard.set(encoded, forKey: "unrecognizedFunds")
        }
    }

    private var recognizedFunds: [String: [FundHolding]] {
        let recognizedFundCodes = Set(dataManager.holdings.filter { $0.isValid }.map { $0.fundCode })
        let filteredFunds = dataManager.holdings.filter { holding in
            recognizedFundCodes.contains(holding.fundCode)
        }
        
        var groupedFunds: [String: [FundHolding]] = [:]
        for holding in filteredFunds {
            if groupedFunds[holding.fundCode] == nil {
                groupedFunds[holding.fundCode] = []
            }
            groupedFunds[holding.fundCode]?.append(holding)
        }
        return groupedFunds
    }

    private var sortedFundCodes: [String] {
        let codes = recognizedFunds.keys.sorted()
        
        if selectedSortKey == .none {
            return codes
        }
        
        let sortedCodes = codes.sorted { (code1, code2) in
            guard let funds1 = recognizedFunds[code1]?.first,
                  let funds2 = recognizedFunds[code2]?.first else {
                return false
            }
            let value1 = getSortValue(for: funds1, key: selectedSortKey)
            let value2 = getSortValue(for: funds2, key: selectedSortKey)

            if value1 != nil && value2 == nil {
                return true
            } else if value1 == nil && value2 != nil {
                return false
            } else if value1 == nil && value2 == nil {
                return code1 < code2
            }

            if sortOrder == .ascending {
                return value1! < value2!
            } else {
                return value1! > value2!
            }
        }
        return sortedCodes
    }

    private func getSortValue(for fund: FundHolding, key: SortKey) -> Double? {
        switch key {
        case .navReturn1m: return fund.navReturn1m
        case .navReturn3m: return fund.navReturn3m
        case .navReturn6m: return fund.navReturn6m
        case .navReturn1y: return fund.navReturn1y
        case .none: return nil
        }
    }
    
    private func getHoldingReturn(for fund: FundHolding) -> Double? {
        guard fund.purchaseAmount > 0 else { return nil }
        return (fund.totalValue - fund.purchaseAmount) / fund.purchaseAmount * 100
    }

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
        NavigationView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // 顶部按钮行
                    HStack {
                        // 左侧排序按钮
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
                        
                        // 刷新进度提示
                        if isRefreshing && !refreshProgressText.isEmpty {
                            Text(refreshProgressText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                        }
                        
                        // 右侧刷新按钮
                        Button(action: {
                            Task {
                                await refreshAllFunds()
                            }
                        }) {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18, weight: .medium))
                            }
                        }
                        .disabled(isRefreshing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    
                    // 基金列表
                    List {
                        if dataManager.holdings.filter({ $0.isValid }).isEmpty {
                            Text("当前没有基金持仓数据")
                                .foregroundColor(.gray)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(sortedFundCodes, id: \.self) { fundCode in
                                if let funds = recognizedFunds[fundCode], let _ = funds.first {
                                    DisclosureGroup(isExpanded: Binding(
                                        get: { expandedFundCodes.contains(fundCode) },
                                        set: { isExpanded in
                                            if isExpanded {
                                                expandedFundCodes.insert(fundCode)
                                            } else {
                                                expandedFundCodes.remove(fundCode)
                                            }
                                        }
                                    )) {
                                        // 展开后的第二张卡片
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Grid 布局的收益率显示
                                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                                GridRow {
                                                    Text("近1月:")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                    Text(funds.first!.navReturn1m?.formattedPercentage ?? "/")
                                                        .font(.subheadline)
                                                        .foregroundColor(colorForValue(funds.first!.navReturn1m))
                                                    Text("近3月:")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                    Text(funds.first!.navReturn3m?.formattedPercentage ?? "/")
                                                        .font(.subheadline)
                                                        .foregroundColor(colorForValue(funds.first!.navReturn3m))
                                                }
                                                GridRow {
                                                    Text("近6月:")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                    Text(funds.first!.navReturn6m?.formattedPercentage ?? "/")
                                                        .font(.subheadline)
                                                        .foregroundColor(colorForValue(funds.first!.navReturn6m))
                                                    Text("近1年:")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                    Text(funds.first!.navReturn1y?.formattedPercentage ?? "/")
                                                        .font(.subheadline)
                                                        .foregroundColor(colorForValue(funds.first!.navReturn1y))
                                                }
                                            }
                                            
                                            Divider()
                                            
                                            HStack(alignment: .top) {
                                                Text("持有客户:")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                    .fixedSize(horizontal: true, vertical: false)
                                                
                                                combinedClientAndReturnText(funds: funds, getHoldingReturn: getHoldingReturn)
                                                    .font(.subheadline)
                                                    .lineLimit(nil)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(10)
                                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                                    } label: {
                                        // 主要基金卡片部分
                                        FundHoldingCardLabel(
                                            fund: funds.first!,
                                            selectedSortKey: selectedSortKey,
                                            getColumnValue: getColumnValue // 已修复：将函数作为参数传递
                                        )
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    
                    // 未识别基金区域
                    if !unrecognizedFunds.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("未能识别基金:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Spacer()
                                
                                // 一键刷新按钮
                                Button(action: {
                                    Task {
                                        await refreshAllUnrecognizedFunds()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        if isRefreshingAllUnrecognizedFunds {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                        } else {
                                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                        }
                                        Text("刷新")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(isRefreshingAllUnrecognizedFunds)

                                Button(action: {
                                    withAnimation {
                                        isUnrecognizedFundsSectionExpanded.toggle()
                                    }
                                }) {
                                    Image(systemName: isUnrecognizedFundsSectionExpanded ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // 未识别基金列表（垂直折叠）
                            if isUnrecognizedFundsSectionExpanded {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(unrecognizedFunds, id: \.fundCode) { fund in
                                            HStack(spacing: 4) {
                                                Text(fund.fundCode)
                                                    .font(.caption.monospaced())
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                .navigationBarHidden(true)
                .onAppear {
                    unrecognizedFunds = dataManager.holdings.filter { !$0.isValid }
                    if !unrecognizedFunds.isEmpty {
                        isUnrecognizedFundsSectionExpanded = true
                    }
                }
                
                ToastView(message: "刷新成功！", isShowing: $showingToast)
                    .padding(.bottom, unrecognizedFunds.isEmpty || !isUnrecognizedFundsSectionExpanded ? 80 : 160)
            }
        }
    }
    
    // MARK: - 操作方法

    private func refreshAllFunds() async {
        isRefreshing = true
        fundService.addLog("开始全局刷新所有基金数据...", type: .info)

        let fundCodesToRefresh = Array(Set(dataManager.holdings.compactMap { holding in
            // 只刷新无效的，或者净值日期不是今天的基金
            if !holding.isValid || !calendar.isDateInToday(holding.navDate) {
                return holding.fundCode
            }
            return nil
        }))

        let totalCount = fundCodesToRefresh.count
        
        // 如果没有需要刷新的基金，直接返回
        if totalCount == 0 {
            await MainActor.run {
                isRefreshing = false
                refreshProgressText = ""
                fundService.addLog("没有需要刷新的基金数据。", type: .info)
                withAnimation {
                    showingToast = true
                }
            }
            return
        }

        for (index, code) in fundCodesToRefresh.enumerated() {
            // 更新进度提示
            await MainActor.run {
                refreshProgressText = "[\(index+1)/\(totalCount)]"
            }
            
            let _ = await refreshSingleFund(fundCode: code)
        }

        await MainActor.run {
            unrecognizedFunds = dataManager.holdings.filter { !$0.isValid }
            saveUnrecognizedFunds()
            
            if !unrecognizedFunds.isEmpty {
                isUnrecognizedFundsSectionExpanded = true
            } else {
                isUnrecognizedFundsSectionExpanded = false
            }

            isRefreshing = false
            refreshProgressText = ""
            fundService.addLog("所有基金刷新完成。", type: .info)
            withAnimation {
                showingToast = true
            }
        }
    }
    
    private func refreshAllUnrecognizedFunds() async {
        isRefreshingAllUnrecognizedFunds = true
        fundService.addLog("开始批量刷新所有未能识别的基金...", type: .info)

        let fundCodesToRefresh = unrecognizedFunds.map { $0.fundCode }
        let totalCount = fundCodesToRefresh.count
        
        // 如果没有需要刷新的基金，直接返回
        if totalCount == 0 {
            await MainActor.run {
                isRefreshingAllUnrecognizedFunds = false
                fundService.addLog("没有需要刷新的未识别基金。", type: .info)
            }
            return
        }
        
        for (_, code) in fundCodesToRefresh.enumerated() {
            let success = await refreshSingleFund(fundCode: code)
            
            if success {
                await MainActor.run {
                    unrecognizedFunds.removeAll(where: { $0.fundCode == code })
                    fundService.addLog("基金 \(code) 成功识别，已从列表中移除。", type: .success)
                }
            }
        }

        await MainActor.run {
            unrecognizedFunds = dataManager.holdings.filter { !$0.isValid }
            saveUnrecognizedFunds()
            
            if unrecognizedFunds.isEmpty {
                isUnrecognizedFundsSectionExpanded = false
            }
            
            isRefreshingAllUnrecognizedFunds = false
            fundService.addLog("所有未能识别的基金刷新完成。", type: .info)
            withAnimation {
                showingToast = true
            }
        }
    }
    
    private func refreshSingleFund(fundCode: String) async -> Bool {
        // 1. 从 API 获取数据
        let fetchedFundInfo = await fundService.fetchFundInfo(code: fundCode)
        
        // 2. 在主线程上更新所有相关持仓
        await MainActor.run {
            // 找到所有该基金代码下的持仓
            let indicesToUpdate = dataManager.holdings.indices.filter { dataManager.holdings[$0].fundCode == fundCode }
            
            for index in indicesToUpdate {
                dataManager.holdings[index].fundName = fetchedFundInfo.fundName
                dataManager.holdings[index].currentNav = fetchedFundInfo.currentNav
                dataManager.holdings[index].navDate = fetchedFundInfo.navDate
                dataManager.holdings[index].isValid = fetchedFundInfo.isValid
                dataManager.holdings[index].navReturn1m = fetchedFundInfo.navReturn1m
                dataManager.holdings[index].navReturn3m = fetchedFundInfo.navReturn3m
                dataManager.holdings[index].navReturn6m = fetchedFundInfo.navReturn6m
                dataManager.holdings[index].navReturn1y = fetchedFundInfo.navReturn1y
            }
            
            // 确保没有重复的无效持仓
            let validHoldings = dataManager.holdings.filter { $0.fundCode == fundCode && $0.isValid }
            if !validHoldings.isEmpty {
                // 如果至少有一个有效持仓，删除所有无效持仓
                dataManager.holdings.removeAll { $0.fundCode == fundCode && !$0.isValid }
            }
            dataManager.saveData()
        }
        
        return fetchedFundInfo.isValid
    }
}

// 独立的基金卡片视图 (已拆分为标签和内容)
struct FundHoldingCardLabel: View {
    var fund: FundHolding
    var selectedSortKey: SortKey
    var getColumnValue: (FundHolding, String?) -> String // 新增：传递函数作为参数
    
    @Environment(\.colorScheme) var colorScheme
    
    private var baseColor: Color {
        fund.fundCode.morandiColor()
    }
    
    private func colorForValue(_ value: Double?) -> Color {
        guard let number = value else {
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
    
    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Text("**\(fund.fundName)**")
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
                    gradient: Gradient(colors: [
                        baseColor,
                        colorScheme == .dark ? Color(.systemGray6) : .white
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
            
            if selectedSortKey != .none {
                VStack(alignment: .trailing) {
                    let valueString = getColumnValue(fund, selectedSortKey.keyPathString) // 已修复：正确调用传递进来的函数
                    let numberValue = Double(valueString.replacingOccurrences(of: "%", with: ""))
                    Text(valueString)
                        .font(.headline)
                        .foregroundColor(colorForValue(numberValue))
                }
                .padding(.horizontal, 16)
            }
            
            // DisclosureGroup 的箭头会自动处理动画，此处无需额外添加
        }
    }
}

// 优化后的函数，解决了编译器警告 (保持不变)
private func combinedClientAndReturnText(funds: [FundHolding], getHoldingReturn: (FundHolding) -> Double?) -> Text {
    let sortedFunds = funds.sorted { $0.clientName < $1.clientName }
    
    var combinedText: Text = Text("")
    
    guard !sortedFunds.isEmpty else {
        return Text("")
    }

    // 先处理第一个元素
    var firstText = Text(sortedFunds[0].clientName)
    if let holdingReturn = getHoldingReturn(sortedFunds[0]) {
        firstText = firstText + Text("(\(holdingReturn.formattedPercentage))")
            .foregroundColor(colorForValue(holdingReturn))
    }
    combinedText = firstText

    // 循环剩余元素并添加分隔符
    for holding in sortedFunds.dropFirst() {
        var nextText = Text(holding.clientName)
        if let holdingReturn = getHoldingReturn(holding) {
            nextText = nextText + Text("(\(holdingReturn.formattedPercentage))")
                .foregroundColor(colorForValue(holdingReturn))
        }
        combinedText = combinedText + Text("、") + nextText
    }
    
    return combinedText
}

private func colorForValue(_ value: Double?) -> Color {
    guard let number = value else {
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
