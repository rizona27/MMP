// SummaryView.swift
import SwiftUI
import Foundation

// MARK: - 通用辅助视图和枚举
enum SortKey: String, CaseIterable, Identifiable {
    case none = "无排序"
    case navReturn1m = "近1月"
    case navReturn3m = "近3月"
    case navReturn6m = "近6月"
    case navReturn1y = "近1年"

    var id: String { self.rawValue }

    // 修正 keyPathString，使其与东财接口字段命名规范对齐
    var keyPathString: String? {
        switch self {
        case .navReturn1m: return "syl_1y" // 东财接口近1月收益率字段
        case .navReturn3m: return "syl_3y" // 东财接口近3月收益率字段
        case .navReturn6m: return "syl_6y" // 东财接口近6月收益率字段
        case .navReturn1y: return "syl_1n" // 东财接口近1年收益率字段
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
    // 修改未识别基金的计算逻辑，只包含无效的基金
    private var unrecognizedFunds: [FundHolding] {
        dataManager.holdings.filter { !$0.isValid }
    }
    
    @State private var showingToast = false
    @State private var isRefreshingAllUnrecognizedFunds = false
    
    @State private var selectedSortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending
    
    @State private var expandedFundCodes: Set<String> = []
    
    @State private var refreshProgressText: String = ""
    @State private var showingUnrecognizedFundsAlert = false
    @State private var refreshStats: (success: Int, fail: Int) = (0, 0)
    @State private var failedFunds: [String] = []
    
    @State private var allExpanded = false

    private let calendar = Calendar.current
    private let maxConcurrentRequests = 3

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
            return codes.sorted() // 默认按基金代码升序排列
        }
    
        let sortedCodes = codes.sorted { (code1, code2) in
            guard let funds1 = recognizedFunds[code1]?.first,
                  let funds2 = recognizedFunds[code2]?.first else {
                return false
            }
            // 修正：调用 getSortValue
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

    private var areAnyCardsExpanded: Bool {
        !expandedFundCodes.isEmpty
    }

    private func toggleAllCards() {
        withAnimation {
            if areAnyCardsExpanded {
                expandedFundCodes.removeAll()
            } else {
                expandedFundCodes = Set(sortedFundCodes)
            }
        }
    }

    // 修正：根据东财字段名获取对应的值
    private func getSortValue(for fund: FundHolding, key: SortKey) -> Double? {
        switch key {
        case .navReturn1m: return fund.navReturn1m // 假定模型中 navReturn1m 对应的是 syl_1y
        case .navReturn3m: return fund.navReturn3m // 假定模型中 navReturn3m 对应的是 syl_3y
        case .navReturn6m: return fund.navReturn6m // 假定模型中 navReturn6m 对应的是 syl_6y
        case .navReturn1y: return fund.navReturn1y // 假定模型中 navReturn1y 对应的是 syl_1n
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
                        // 折叠/展开按钮
                        Button(action: {
                            toggleAllCards()
                        }) {
                            Image(systemName: areAnyCardsExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 16))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                        // 排序按钮，尺寸与刷新按钮一致
                        Button(action: {
                            withAnimation {
                                selectedSortKey = selectedSortKey.next
                            }
                        }) {
                            HStack {
                                Image(systemName: sortButtonIconName())
                                    .foregroundColor(.primary)
                                    .font(.system(size: 16))
                                if selectedSortKey != .none {
                                    Text(selectedSortKey.rawValue)
                                        .font(.system(size: 16))
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
                                    .font(.system(size: 16, weight: .bold)) // 修改图标大小为14
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28) // 与刷新按钮尺寸保持一致
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
                    
                        // 未识别基金提示按钮 - 只在有完全无收益率数据的基金时显示
                        if !unrecognizedFunds.isEmpty {
                            Button(action: {
                                showingUnrecognizedFundsAlert = true
                            }) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 16))
                            }
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
                
                    // 基金列表区域
                    VStack(spacing: 0) {
                        if dataManager.holdings.filter({ $0.isValid }).isEmpty {
                            Text("当前没有基金持仓数据")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        } else {
                            List {
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
                    
                                                    combinedClientAndReturnText(funds: funds, getHoldingReturn: getHoldingReturn, sortOrder: sortOrder)
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
                                                getColumnValue: { fund, keyPath in
                                                    // 修正：getColumnValue 也需要返回正确的值
                                                    getColumnValue(for: fund, keyPath: keyPath)
                                                }
                                            )
                                        }
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }
                            .listStyle(PlainListStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemGroupedBackground))
                .navigationBarHidden(true)
                .alert("以下基金需要刷新", isPresented: $showingUnrecognizedFundsAlert) {
                    Button("刷新以上基金", action: {
                        Task {
                            await refreshAllUnrecognizedFunds()
                        }
                    })
                    Button("刷新全部基金", action: {
                        Task {
                            await refreshAllFunds()
                        }
                    })
                    Button("暂不刷新基金", role: .cancel) { }
                } message: {
                    VStack(alignment: .leading, spacing: 8) {
                        // 修改：仅包含无效的基金
                        let fundsToRefresh = unrecognizedFunds.map { "\($0.fundName)[\($0.fundCode)]" }.joined(separator: "、")
                    
                        if !fundsToRefresh.isEmpty {
                            Text(fundsToRefresh)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    
                        if !failedFunds.isEmpty {
                            Text("刷新失败的基金:")
                                .font(.subheadline)
                                .foregroundColor(.purple)
                            Text(failedFunds.joined(separator: "、"))
                                .font(.caption)
                        }
                    }
                }
            
                ToastView(message: "刷新完成！成功: \(refreshStats.success), 失败: \(refreshStats.fail)", isShowing: $showingToast)
                    .padding(.bottom, 80)
            }
        }
    }
    
    // MARK: - 操作方法

    private func refreshAllFunds() async {
        await MainActor.run {
            isRefreshing = true
            refreshStats = (0, 0)
            failedFunds.removeAll()
            refreshProgressText = "准备刷新..."
            fundService.addLog("开始全局刷新所有基金数据...", type: .info)
        }

        let allFundCodes = Array(Set(dataManager.holdings.map { $0.fundCode }))
        let totalCount = allFundCodes.count
    
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
    
        var updatedFunds: [String: FundHolding] = [:]

        await withTaskGroup(of: (String, FundHolding?).self) { group in
            var iterator = allFundCodes.makeIterator()
            var activeTasks = 0
            
            // Initial task submission
            while activeTasks < maxConcurrentRequests, let code = iterator.next() {
                group.addTask {
                    await fetchFundWithRetry(code: code)
                }
                activeTasks += 1
            }
            
            // Process results and submit new tasks
            while let result = await group.next() {
                activeTasks -= 1
                await processFundResult(result: result, updatedFunds: &updatedFunds, totalCount: totalCount)
            
                if let code = iterator.next() {
                    group.addTask {
                        await fetchFundWithRetry(code: code)
                    }
                    activeTasks += 1
                }
            }
        }
    
        // 批量更新数据
        await MainActor.run {
            updateHoldingsWithNewData(updatedFunds: updatedFunds)
    
            isRefreshing = false
            refreshProgressText = ""
            fundService.addLog("所有基金刷新完成。成功: \(refreshStats.success), 失败: \(refreshStats.fail)", type: .info)
            withAnimation {
                showingToast = true
            }
        }
    }
    
    private func refreshAllUnrecognizedFunds() async {
        await MainActor.run {
            isRefreshing = true
            refreshStats = (0, 0)
            failedFunds.removeAll()
            fundService.addLog("开始批量刷新所有需要更新的基金...", type: .info)
        }

        let fundCodesToRefresh = Array(Set(unrecognizedFunds.map { $0.fundCode }))
        let totalCount = fundCodesToRefresh.count
    
        if totalCount == 0 {
            await MainActor.run {
                isRefreshing = false
                fundService.addLog("没有需要刷新的基金。", type: .info)
            }
            return
        }
    
        var updatedFunds: [String: FundHolding] = [:]
            
        await withTaskGroup(of: (String, FundHolding?).self) { group in
            var iterator = fundCodesToRefresh.makeIterator()
            var activeTasks = 0
            
            // Initial task submission
            while activeTasks < maxConcurrentRequests, let code = iterator.next() {
                group.addTask {
                    await fetchFundWithRetry(code: code)
                }
                activeTasks += 1
            }
            
            // Process results and submit new tasks
            while let result = await group.next() {
                activeTasks -= 1
                await processFundResult(result: result, updatedFunds: &updatedFunds, totalCount: totalCount)
            
                if let code = iterator.next() {
                    group.addTask {
                        await fetchFundWithRetry(code: code)
                    }
                    activeTasks += 1
                }
            }
        }
    
        // 批量更新数据
        await MainActor.run {
            updateHoldingsWithNewData(updatedFunds: updatedFunds)
    
            isRefreshing = false
            refreshProgressText = ""
            fundService.addLog("所有需要更新的基金刷新完成。成功: \(refreshStats.success), 失败: \(refreshStats.fail)", type: .info)
            withAnimation {
                showingToast = true
            }
        }
    }
    
    // 获取基金信息并重试 - 修改为使用新的接口
    private func fetchFundWithRetry(code: String) async -> (String, FundHolding?) {
        var retryCount = 0
        var fetchedFundDetails: (fundName: String, returns: (navReturn1m: Double?, navReturn3m: Double?, navReturn6m: Double?, navReturn1y: Double?))?

        while retryCount < 5 {
            fetchedFundDetails = await fundService.fetchFundDetailsFromEastmoney(code: code)
            
            if let details = fetchedFundDetails {
                // 判断是否有效：基金名称不为N/A，且至少有一个收益率数据不为nil
                let hasValidName = details.fundName != "N/A"
                let hasValidReturnData = details.returns.navReturn1m != nil || details.returns.navReturn3m != nil || details.returns.navReturn6m != nil || details.returns.navReturn1y != nil

                if hasValidName && hasValidReturnData {
                    // 构建一个FundHolding对象，只填充我们需要的字段
                    var holding = FundHolding.invalid(fundCode: code)
                    holding.fundName = details.fundName
                    holding.navReturn1m = details.returns.navReturn1m
                    holding.navReturn3m = details.returns.navReturn3m
                    holding.navReturn6m = details.returns.navReturn6m
                    holding.navReturn1y = details.returns.navReturn1y
                    holding.isValid = true

                    return (code, holding)
                } else {
                    // 如果没有有效数据，继续重试
                    fetchedFundDetails = nil
                }
            }

            retryCount += 1
            if retryCount < 5 {
                let retryDelay = Double(retryCount) * 0.5
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        return (code, nil)
    }
    
    // 处理基金获取结果
    private func processFundResult(result: (String, FundHolding?), updatedFunds: inout [String: FundHolding], totalCount: Int) async {
        let (code, fundInfo) = result
    
        await MainActor.run {
            if let fundInfo = fundInfo {
                let hasValidName = fundInfo.fundName != "N/A"
                let hasValidReturnData = fundInfo.navReturn1m != nil || fundInfo.navReturn3m != nil || fundInfo.navReturn6m != nil || fundInfo.navReturn1y != nil
            
                if hasValidName && hasValidReturnData {
                    updatedFunds[code] = fundInfo
                    refreshStats.success += 1
                    fundService.addLog("基金 \(code) 刷新成功", type: .success)
                } else {
                    refreshStats.fail += 1
                    failedFunds.append(code)
                    fundService.addLog("基金 \(code) 刷新失败：无有效名称或收益率数据", type: .error)
                }
            } else {
                refreshStats.fail += 1
                failedFunds.append(code)
                fundService.addLog("基金 \(code) 刷新失败：未获取到基金信息", type: .error)
            }
    
            refreshProgressText = "已完成 \(refreshStats.success + refreshStats.fail)/\(totalCount)"
        }
    }
    
    // 更新持仓数据 - 修改为只更新名称和收益率
    private func updateHoldingsWithNewData(updatedFunds: [String: FundHolding]) {
        var newHoldings = dataManager.holdings
    
        for (index, holding) in newHoldings.enumerated() {
            if let updatedInfo = updatedFunds[holding.fundCode] {
                newHoldings[index].fundName = updatedInfo.fundName
                newHoldings[index].navReturn1m = updatedInfo.navReturn1m
                newHoldings[index].navReturn3m = updatedInfo.navReturn3m
                newHoldings[index].navReturn6m = updatedInfo.navReturn6m
                newHoldings[index].navReturn1y = updatedInfo.navReturn1y
                newHoldings[index].isValid = updatedInfo.isValid
            }
        }
    
        dataManager.holdings = newHoldings
        dataManager.saveData()
    }
}

// 独立的基金卡片视图
struct FundHoldingCardLabel: View {
    var fund: FundHolding
    var selectedSortKey: SortKey
    var getColumnValue: (FundHolding, String?) -> String
    
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
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(fund.fundCode)
                    .font(.caption.monospaced())
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
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
                    let valueString = getColumnValue(fund, selectedSortKey.keyPathString)
                    let numberValue = Double(valueString.replacingOccurrences(of: "%", with: ""))
                    Text(valueString)
                        .font(.headline)
                        .foregroundColor(colorForValue(numberValue))
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// 辅助函数
private func combinedClientAndReturnText(funds: [FundHolding], getHoldingReturn: (FundHolding) -> Double?, sortOrder: SortOrder) -> Text {
    let sortedFunds: [FundHolding]
    if sortOrder == .ascending {
        sortedFunds = funds.sorted {
            let return1 = getHoldingReturn($0) ?? -Double.infinity
            let return2 = getHoldingReturn($1) ?? -Double.infinity
            return return1 < return2
        }
    } else { // descending
        sortedFunds = funds.sorted {
            let return1 = getHoldingReturn($0) ?? -Double.infinity
            let return2 = getHoldingReturn($1) ?? -Double.infinity
            return return1 > return2
        }
    }
    
    var combinedText: Text = Text("")
    
    guard !sortedFunds.isEmpty else {
        return Text("")
    }

    for (index, holding) in sortedFunds.enumerated() {
        var clientText = Text(holding.clientName)
        if let holdingReturn = getHoldingReturn(holding) {
            clientText = clientText + Text("(\(holdingReturn.formattedPercentage))")
                .foregroundColor(colorForValue(holdingReturn))
        }
    
        if index > 0 {
            combinedText = combinedText + Text("、")
        }
    
        combinedText = combinedText + clientText
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

// 修正：getColumnValue 函数，使其与新的 keyPathString 对应
private func getColumnValue(for fund: FundHolding, keyPath: String?) -> String {
    guard let keyPath = keyPath else { return "/" }
    switch keyPath {
    case "syl_1y": return fund.navReturn1m?.formattedPercentage ?? "/"
    case "syl_3y": return fund.navReturn3m?.formattedPercentage ?? "/"
    case "syl_6y": return fund.navReturn6m?.formattedPercentage ?? "/"
    case "syl_1n": return fund.navReturn1y?.formattedPercentage ?? "/"
    default: return ""
    }
}
