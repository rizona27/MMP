import SwiftUI
import Foundation

enum SortKey: String, CaseIterable, Identifiable {
    case none = "无排序"
    case navReturn1m = "近1月"
    case navReturn3m = "近3月"
    case navReturn6m = "近6月"
    case navReturn1y = "近1年"

    var id: String { self.rawValue }
    var keyPathString: String? {
        switch self {
        case .navReturn1m: return "syl_1y"
        case .navReturn3m: return "syl_3y"
        case .navReturn6m: return "syl_6y"
        case .navReturn1y: return "syl_1n"
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

struct SummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled: Bool = false

    @State private var isRefreshing = false
    private var unrecognizedFunds: [FundHolding] {
        let uniqueFundCodes = Set(dataManager.holdings.filter { !$0.isValid }.map { $0.fundCode })
        return dataManager.holdings.filter { uniqueFundCodes.contains($0.fundCode) }
    }
    
    @State private var showingToast = false
    @State private var isRefreshingAllUnrecognizedFunds = false
    
    @State private var selectedSortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending
    
    @State private var expandedFundCodes: Set<String> = []
    
    @State private var refreshProgressText: String = ""
    @State private var refreshStats: (success: Int, fail: Int) = (0, 0)
    @State private var failedFunds: [String] = []
    
    @State private var allExpanded = false
    @State private var refreshID = UUID()
    
    // 新增状态变量
    @State private var searchText = ""
    @State private var currentRefreshingFundName: String = ""
    @State private var currentRefreshingFundCode: String = ""
    @State private var showingNavDateToast = false
    @State private var navDateToastMessage = ""
    
    // 双击检测相关状态 - 移除，避免手势冲突
    @State private var showOutdatedFundsList = false

    private let calendar = Calendar.current
    private let maxConcurrentRequests = 3
    
    // 获取前一个工作日
    private var previousWorkday: Date {
        let today = Date()
        var date = calendar.startOfDay(for: today)
        
        // 循环找到前一个工作日（周一到周五）
        while true {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            let weekday = calendar.component(.weekday, from: date)
            // 1: Sunday, 7: Saturday, 2-6: Monday to Friday
            if weekday >= 2 && weekday <= 6 {
                return date
            }
        }
    }
    
    // 检查是否有基金净值日期符合前一个工作日
    private var hasLatestNavDate: Bool {
        // 如果没有持仓数据，或者所有基金都是无效的，返回false
        if dataManager.holdings.isEmpty || dataManager.holdings.allSatisfy({ !$0.isValid }) {
            return false
        }
        
        let previousWorkdayStart = previousWorkday
        return dataManager.holdings.contains { holding in
            holding.isValid && calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
    }
    
    // 获取不是最新净值的基金列表
    private var outdatedFunds: [FundHolding] {
        let previousWorkdayStart = previousWorkday
        return dataManager.holdings.filter { holding in
            holding.isValid && !calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
    }
    
    // 获取不是最新净值的基金代码列表
    private var outdatedFundCodes: [String] {
        Array(Set(outdatedFunds.map { $0.fundCode }))
    }
    
    // 获取最新净值日期
    private var latestNavDate: Date? {
        dataManager.holdings
            .filter { $0.isValid && $0.navDate <= Date() }
            .map { $0.navDate }
            .max()
    }
    
    private var latestNavDateString: String {
        guard let latestDate = latestNavDate else {
            return "暂无数据"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        let dateString = formatter.string(from: latestDate)
        
        if hasLatestNavDate {
            return "最新日期: \(dateString)"
        } else {
            // 显示前一个工作日的日期
            let previousWorkdayString = formatter.string(from: previousWorkday)
            return "待更新: \(previousWorkdayString)"
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

    // 搜索筛选后的持仓
    private var filteredHoldings: [FundHolding] {
        if searchText.isEmpty {
            return dataManager.holdings
        } else {
            return dataManager.holdings.filter { holding in
                holding.fundName.localizedCaseInsensitiveContains(searchText) ||
                holding.fundCode.localizedCaseInsensitiveContains(searchText) ||
                holding.clientName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var allGroupedFunds: [String: [FundHolding]] {
        var groupedFunds: [String: [FundHolding]] = [:]
        for holding in filteredHoldings {
            if groupedFunds[holding.fundCode] == nil {
                groupedFunds[holding.fundCode] = []
            }
            groupedFunds[holding.fundCode]?.append(holding)
        }
        return groupedFunds
    }

    private var sortedFundCodes: [String] {
        let codes = allGroupedFunds.keys.sorted()
    
        if selectedSortKey == .none {
            return codes.sorted()
        }
    
        let sortedCodes = codes.sorted { (code1, code2) in
            guard let funds1 = allGroupedFunds[code1]?.first,
                  let funds2 = allGroupedFunds[code2]?.first else {
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
    
    // 截取基金名称（最多6个字符）
    private func truncatedFundName(_ name: String) -> String {
        if name.count <= 6 {
            return name
        } else {
            return String(name.prefix(6)) + "..."
        }
    }
    
    // 显示不是最新净值的基金列表
    private func showOutdatedFundsToast() {
        let outdatedFundsList = outdatedFunds.map { "\($0.fundName)[\($0.fundCode)]" }
        
        if outdatedFundsList.isEmpty {
            // 如果列表为空，不显示Toast
            return
        } else {
            // 最多显示5个，超过用...表示
            let displayList: [String]
            if outdatedFundsList.count > 5 {
                displayList = Array(outdatedFundsList.prefix(5)) + ["..."]
            } else {
                displayList = outdatedFundsList
            }
            
            navDateToastMessage = "以下信息待更新:\n" + displayList.joined(separator: "\n")
            showingNavDateToast = true
        }
    }
    
    // 处理净值待更新区域的点击事件 - 简化为单击
    private func handleNavDateTap() {
        // 如果是"暂无净值数据"，不显示Toast
        guard latestNavDateString != "暂无数据" else { return }
        
        // 单击显示Toast
        showOutdatedFundsToast()
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: {
                            toggleAllCards()
                        }) {
                            Image(systemName: areAnyCardsExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 18))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .cornerRadius(8)
                    
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
                            .background(Color.clear)
                            .cornerRadius(8)
                        }

                        if selectedSortKey != .none {
                            Button(action: {
                                withAnimation {
                                    sortOrder = (sortOrder == .ascending) ? .descending : .ascending
                                }
                            }) {
                                Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.accentColor)
                                    .clipShape(Circle())
                            }
                        }
                    
                        Spacer()
                    
                        // 修改刷新进度显示
                        if isRefreshing {
                            if !currentRefreshingFundName.isEmpty {
                                HStack(spacing: 6) {
                                    Text(truncatedFundName(currentRefreshingFundName))
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                    Text("\(refreshStats.success + refreshStats.fail)/\(allFundCodesCount)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.trailing, 8)
                            }
                        } else {
                            // 非刷新状态显示最新净值日期
                            if hasLatestNavDate {
                                Text(latestNavDateString)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                            } else {
                                Button(action: {
                                    handleNavDateTap()
                                }) {
                                    Text(latestNavDateString)
                                        .font(.system(size: 14))
                                        .foregroundColor(latestNavDateString == "暂无数据" ? .secondary : .orange)
                                        .padding(.trailing, 8)
                                }
                                .disabled(latestNavDateString == "暂无数据")
                            }
                        }
                    
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
                                    .font(.system(size: 18))
                            }
                        }
                        .disabled(isRefreshing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    
                    // 搜索栏 - 调整样式和间距
                    if !dataManager.holdings.isEmpty {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("输入客户名、基金代码、基金名称...", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGroupedBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                
                    VStack(spacing: 0) {
                        if dataManager.holdings.isEmpty {
                            Text("当前没有数据")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        } else if filteredHoldings.isEmpty && !searchText.isEmpty {
                            Text("未找到符合条件的内容")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        } else {
                            List {
                                ForEach(sortedFundCodes, id: \.self) { fundCode in
                                    if let funds = allGroupedFunds[fundCode], let firstFund = funds.first {
                                        // 修复问题1和2：使用自定义展开收起，只显示外部蓝色箭头，隐藏内部灰色箭头
                                        VStack(spacing: 0) {
                                            Button(action: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    if expandedFundCodes.contains(fundCode) {
                                                        expandedFundCodes.remove(fundCode)
                                                    } else {
                                                        expandedFundCodes.insert(fundCode)
                                                    }
                                                }
                                            }) {
                                                HStack(alignment: .center) {
                                                    FundHoldingCardLabel(
                                                        fund: firstFund,
                                                        selectedSortKey: selectedSortKey,
                                                        getColumnValue: { fund, keyPath in
                                                            getColumnValue(for: fund, keyPath: keyPath)
                                                        },
                                                        isExpanded: expandedFundCodes.contains(fundCode),
                                                        showArrow: false // 隐藏内部灰色箭头
                                                    )
                                                    
                                                    // 添加外部蓝色箭头
                                                    Image(systemName: expandedFundCodes.contains(fundCode) ? "chevron.down" : "chevron.right")
                                                        .font(.system(size: 16, weight: .medium))
                                                        .foregroundColor(.accentColor)
                                                        .padding(.trailing, 8)
                                                }
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            if expandedFundCodes.contains(fundCode) {
                                                VStack(alignment: .leading, spacing: 12) {
                                                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                                        GridRow {
                                                            Text("近1月:")
                                                                .font(.subheadline)
                                                                .foregroundColor(.secondary)
                                                            Text(firstFund.navReturn1m?.formattedPercentage ?? "/")
                                                                .font(.subheadline)
                                                                .foregroundColor(colorForValue(firstFund.navReturn1m))
                                                            Text("近3月:")
                                                                .font(.subheadline)
                                                                .foregroundColor(.secondary)
                                                            Text(firstFund.navReturn3m?.formattedPercentage ?? "/")
                                                                .font(.subheadline)
                                                                .foregroundColor(colorForValue(firstFund.navReturn3m))
                                                        }
                                                        GridRow {
                                                            Text("近6月:")
                                                                .font(.subheadline)
                                                                .foregroundColor(.secondary)
                                                            Text(firstFund.navReturn6m?.formattedPercentage ?? "/")
                                                                .font(.subheadline)
                                                                .foregroundColor(colorForValue(firstFund.navReturn6m))
                                                            Text("近1年:")
                                                                .font(.subheadline)
                                                                .foregroundColor(.secondary)
                                                            Text(firstFund.navReturn1y?.formattedPercentage ?? "/")
                                                                .font(.subheadline)
                                                                .foregroundColor(colorForValue(firstFund.navReturn1y))
                                                        }
                                                    }
                                                    
                                                    Divider()
                                                    
                                                    HStack(alignment: .top) {
                                                        Text("持有客户:")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                            .fixedSize(horizontal: true, vertical: false)
                    
                                                        combinedClientAndReturnText(funds: funds, getHoldingReturn: getHoldingReturn, sortOrder: sortOrder, isPrivacyModeEnabled: isPrivacyModeEnabled)
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
                                                .padding(.top, 8)
                                            }
                                        }
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                        .listRowBackground(Color.clear)
                                    }
                                }
                            }
                            .listStyle(PlainListStyle())
                            .id(refreshID)
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
                }
                .background(Color(.systemGroupedBackground))
                .navigationBarHidden(true)
                .onTapGesture {
                    // 点击屏幕其他位置收起键盘
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            
                // 刷新完成 Toast - 调整到列表框体位置
                if showingToast {
                    VStack {
                        Spacer()
                            .frame(height: 180) // 调整这个值使Toast显示在列表框体位置
                        ToastView(message: "刷新完成！成功: \(refreshStats.success), 失败: \(refreshStats.fail)", isShowing: $showingToast)
                        Spacer()
                    }
                }
                
                // 净值待更新基金列表 Toast - 调整到列表框体位置
                if showingNavDateToast {
                    VStack {
                        Spacer()
                            .frame(height: 180) // 调整这个值使Toast显示在列表框体位置
                        ToastView(message: navDateToastMessage, isShowing: $showingNavDateToast)
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            // 首次打开时检查是否需要自动更新
            if !hasLatestNavDate && !dataManager.holdings.isEmpty {
                // 显示净值待更新提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showOutdatedFundsToast()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HoldingsDataUpdated"))) { _ in
            refreshID = UUID()
        }
    }
    
    // 计算所有基金代码数量
    private var allFundCodesCount: Int {
        Set(dataManager.holdings.map { $0.fundCode }).count
    }
    
    // 刷新不是最新净值的基金
    private func refreshOutdatedFunds() async {
        // 检查是否有需要刷新的基金
        let fundCodesToRefresh = outdatedFundCodes
        let totalCount = fundCodesToRefresh.count
        
        if totalCount == 0 {
            await MainActor.run {
                fundService.addLog("没有需要刷新的基金。", type: .info)
                // 不再显示"所有基金都已是最新净值"的Toast
            }
            return
        }
        
        await MainActor.run {
            isRefreshing = true
            refreshStats = (0, 0)
            failedFunds.removeAll()
            currentRefreshingFundName = ""
            currentRefreshingFundCode = ""
            fundService.addLog("开始刷新不是最新净值的基金...", type: .info)
        }

        var updatedFunds: [String: FundHolding] = [:]

        await withTaskGroup(of: (String, FundHolding?).self) { group in
            var iterator = fundCodesToRefresh.makeIterator()
            var activeTasks = 0
            
            while activeTasks < maxConcurrentRequests, let code = iterator.next() {
                group.addTask {
                    await fetchFundWithRetry(code: code)
                }
                activeTasks += 1
            }

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

        await MainActor.run {
            updateHoldingsWithNewData(updatedFunds: updatedFunds)
    
            isRefreshing = false
            currentRefreshingFundName = ""
            currentRefreshingFundCode = ""
            fundService.addLog("不是最新净值的基金刷新完成。成功: \(refreshStats.success), 失败: \(refreshStats.fail)", type: .info)
            withAnimation {
                showingToast = true
            }
            
            NotificationCenter.default.post(name: Notification.Name("HoldingsDataUpdated"), object: nil)
        }
    }
    
    private func refreshAllFunds() async {
        await MainActor.run {
            isRefreshing = true
            refreshStats = (0, 0)
            failedFunds.removeAll()
            currentRefreshingFundName = ""
            currentRefreshingFundCode = ""
            fundService.addLog("开始全局刷新所有基金数据...", type: .info)
        }

        let allFundCodes = Array(Set(dataManager.holdings.map { $0.fundCode }))
        let totalCount = allFundCodes.count
    
        if totalCount == 0 {
            await MainActor.run {
                isRefreshing = false
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
            
            while activeTasks < maxConcurrentRequests, let code = iterator.next() {
                group.addTask {
                    await fetchFundWithRetry(code: code)
                }
                activeTasks += 1
            }

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

        await MainActor.run {
            updateHoldingsWithNewData(updatedFunds: updatedFunds)
    
            isRefreshing = false
            currentRefreshingFundName = ""
            currentRefreshingFundCode = ""
            fundService.addLog("所有基金刷新完成。成功: \(refreshStats.success), 失败: \(refreshStats.fail)", type: .info)
            withAnimation {
                showingToast = true
            }
            
            NotificationCenter.default.post(name: Notification.Name("HoldingsDataUpdated"), object: nil)
        }
    }

    private func fetchFundWithRetry(code: String) async -> (String, FundHolding?) {
        var retryCount = 0
        var fetchedFundDetails: (fundName: String, returns: (navReturn1m: Double?, navReturn3m: Double?, navReturn6m: Double?, navReturn1y: Double?))?

        while retryCount < 5 {
            fetchedFundDetails = await fundService.fetchFundDetailsFromEastmoney(code: code)
            
            if let details = fetchedFundDetails {
                let hasValidName = details.fundName != "N/A"
                let hasValidReturnData = details.returns.navReturn1m != nil || details.returns.navReturn3m != nil || details.returns.navReturn6m != nil || details.returns.navReturn1y != nil

                if hasValidName {
                    var holding = FundHolding.invalid(fundCode: code)
                    holding.fundName = details.fundName
                    holding.navReturn1m = details.returns.navReturn1m
                    holding.navReturn3m = details.returns.navReturn3m
                    holding.navReturn6m = details.returns.navReturn6m
                    holding.navReturn1y = details.returns.navReturn1y
                    holding.isValid = hasValidReturnData
                    
                    return (code, holding)
                } else {
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
    
    private func processFundResult(result: (String, FundHolding?), updatedFunds: inout [String: FundHolding], totalCount: Int) async {
        let (code, fundInfo) = result
    
        await MainActor.run {
            // 更新当前刷新基金信息
            if let fundInfo = fundInfo {
                currentRefreshingFundName = fundInfo.fundName
                currentRefreshingFundCode = code
            }
            
            if let fundInfo = fundInfo {
                let hasValidName = fundInfo.fundName != "N/A"
                let hasValidReturnData = fundInfo.navReturn1m != nil || fundInfo.navReturn3m != nil || fundInfo.navReturn6m != nil || fundInfo.navReturn1y != nil
            
                if hasValidName {
                    updatedFunds[code] = fundInfo
                    if hasValidReturnData {
                         refreshStats.success += 1
                         fundService.addLog("基金 \(code) 刷新成功", type: .success)
                    } else {
                        refreshStats.success += 1
                        fundService.addLog("基金 \(code) 成功获取名称，但无收益率数据", type: .info)
                    }
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
        }
    }

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

struct FundHoldingCardLabel: View {
    var fund: FundHolding
    var selectedSortKey: SortKey
    var getColumnValue: (FundHolding, String?) -> String
    var isExpanded: Bool
    var showArrow: Bool = true // 新增参数控制是否显示箭头
    
    @Environment(\.colorScheme) var colorScheme
    
    private var identifier: String {
        "\(fund.fundCode)-\(fund.fundName)-\(fund.navReturn1m ?? 0)-\(fund.navReturn3m ?? 0)-\(fund.navReturn6m ?? 0)-\(fund.navReturn1y ?? 0)"
    }
    
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
                
                // 根据参数决定是否显示箭头
                if showArrow {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
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
        .id(identifier)
        .contentShape(Rectangle()) // 确保整个区域可点击
    }
}

private func combinedClientAndReturnText(funds: [FundHolding], getHoldingReturn: (FundHolding) -> Double?, sortOrder: SortOrder, isPrivacyModeEnabled: Bool) -> Text {
    let sortedFunds: [FundHolding]
    if sortOrder == .ascending {
        sortedFunds = funds.sorted {
            let return1 = getHoldingReturn($0) ?? -Double.infinity
            let return2 = getHoldingReturn($1) ?? -Double.infinity
            return return1 < return2
        }
    } else {
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
        let clientName = isPrivacyModeEnabled ? processClientName(holding.clientName) : holding.clientName
        var clientText = Text(clientName)
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
