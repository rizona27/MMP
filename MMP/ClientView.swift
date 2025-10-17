import SwiftUI
import Foundation

// MARK: - Extensions (保持不变)

extension String {
    func morandiColor() -> Color {
        var hash = 0
        for char in self.unicodeScalars {
            hash = (hash << 5) &+ (hash - hash) + Int(char.value)
        }
        
        let hue = Double(abs(hash) % 256) / 256.0
        let saturation = 0.4 + (Double(abs(hash) % 30) / 100.0)
        let brightness = 0.7 + (Double(abs(hash) % 20) / 100.0)

        return Color(hue: hue, saturation: saturation, brightness: brightness).opacity(0.8)
    }
}

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
        return self.luminance() > 0.6 ? .black : .white
    }
}

extension Double {
    var formattedPercentage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self / 100)) ?? "\(self)%"
    }
}

extension Date {
    func isOlderThan(minutes: Int) -> Bool {
        let calendar = Calendar.current
        let expirationDate = calendar.date(byAdding: .minute, value: minutes, to: self) ?? Date()
        return expirationDate < Date()
    }
}

// MARK: - Structs (保持不变)

struct ClientGroup: Identifiable {
    let id: String
    let clientName: String
    let clientID: String
    let totalAUM: Double
    var holdings: [FundHolding]
    var isPinned: Bool
    var pinnedTimestamp: Date?
}

struct ClientView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @State private var isRefreshing = false
    
    @Environment(\.colorScheme) var colorScheme

    @State private var expandedClients: Set<String> = []
    
    @AppStorage("isQuickNavBarEnabled") private var isQuickNavBarEnabled: Bool = false
    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled: Bool = false
    
    @State private var loadedGroupedClientCount: Int = 10
    
    @State private var searchText = ""
    @State private var loadedSearchResultCount: Int = 10

    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var refreshID = UUID()

    @State private var refreshProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentRefreshingClientName: String = ""
    @State private var currentRefreshingClientID: String = ""
    @State private var showRefreshCompleteToast = false

    private let maxConcurrentRequests = 3

    private let calendar = Calendar.current
    
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
    
    // 获取不是最新净值的客户列表
    private var outdatedClients: [String] {
        let previousWorkdayStart = previousWorkday
        let outdatedHoldings = dataManager.holdings.filter { holding in
            holding.isValid && !calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
        return Array(Set(outdatedHoldings.map { $0.clientName }))
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
    
    @State private var showingNavDateToast = false
    @State private var navDateToastMessage = ""
    @State private var showingOutdatedDataToast = false

    private func localizedStandardCompare(_ s1: String, _ s2: String, ascending: Bool) -> Bool {
        if ascending {
            return s1.localizedStandardCompare(s2) == .orderedAscending
        } else {
            return s1.localizedStandardCompare(s2) == .orderedDescending
        }
    }

    var pinnedHoldings: [FundHolding] {
        dataManager.holdings.filter { $0.isPinned }
            .sorted { (h1, h2) -> Bool in
                (h1.pinnedTimestamp ?? .distantPast) > (h2.pinnedTimestamp ?? .distantPast)
            }
    }

    var groupedHoldingsByClientName: [ClientGroup] {
        let allHoldings = dataManager.holdings

        let groupedDictionary = Dictionary(grouping: allHoldings) { holding in
            holding.clientName
        }
        
        var clientGroups: [ClientGroup] = groupedDictionary.map { (clientName, holdings) in
            let totalAUM = holdings.reduce(0.0) { accumulatedResult, holding in
                accumulatedResult + holding.totalValue
            }
            let representativeClientID = holdings.first?.clientID ?? ""
            
            return ClientGroup(
                id: clientName,
                clientName: clientName,
                clientID: representativeClientID,
                totalAUM: totalAUM,
                holdings: holdings,
                isPinned: false,
                pinnedTimestamp: nil
            )
        }
        
        clientGroups.sort { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }
        
        for i in 0..<clientGroups.count {
            clientGroups[i].holdings.sort { (h1, h2) -> Bool in
                if h1.isPinned && !h2.isPinned { return true }
                if !h1.isPinned && h2.isPinned { return false }
                
                if h1.isPinned && h2.isPinned {
                    return (h1.pinnedTimestamp ?? .distantPast) > (h2.pinnedTimestamp ?? .distantPast)
                }
                
                return h1.purchaseDate < h2.purchaseDate
            }
        }

        return clientGroups
    }

    var sectionedClientGroups: [Character: [ClientGroup]] {
        var sections: [Character: [ClientGroup]] = [:]

        if !pinnedHoldings.isEmpty {
            let pinnedClientGroup = ClientGroup(
                id: "Pinned",
                clientName: "置顶区域",
                clientID: "",
                totalAUM: pinnedHoldings.reduce(0.0) { $0 + $1.totalValue },
                holdings: pinnedHoldings,
                isPinned: true,
                pinnedTimestamp: pinnedHoldings.compactMap { $0.pinnedTimestamp }.max()
            )
            sections["★", default: []].append(pinnedClientGroup)
        }

        let allGroups = groupedHoldingsByClientName
        for group in allGroups {
            let firstChar = group.clientName.first?.uppercased().first ?? "#"
            sections[firstChar, default: []].append(group)
        }
        return sections
    }

    var sortedSectionKeys: [Character] {
        sectionedClientGroups.keys.sorted { (char1, char2) -> Bool in
            if char1 == "★" { return true }
            if char2 == "★" { return false }
            if char1 == "#" { return false }
            if char2 == "#" { return true }
            return String(char1).localizedStandardCompare(String(char2)) == .orderedAscending
        }
    }

    var areAnyCardsExpanded: Bool {
        !expandedClients.isEmpty
    }

    private func holdingRowView(for holding: FundHolding, hideClientInfo: Bool) -> some View {
        var displayHolding = holding
        if isPrivacyModeEnabled {
            // Placeholder: Assuming processClientName exists
            // displayHolding.clientName = processClientName(holding.clientName)
        }
        return HoldingRow(holding: displayHolding, hideClientInfo: hideClientInfo)
            .environmentObject(dataManager)
            .environmentObject(fundService)
    }
    
    private func processClientName(_ name: String) -> String {
        if name.count > 2 {
            return String(name.prefix(1)) + "..." + String(name.suffix(1))
        } else {
            return name
        }
    }
    
    // ** 修正问题 1：统一的带有滑动操作的基金卡片视图 **
    private func holdingRowWithSwipeActions(for holding: FundHolding, hideClientInfo: Bool) -> some View {
        holdingRowView(for: holding, hideClientInfo: hideClientInfo)
            // 统一添加滑动操作
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    togglePin(for: holding)
                } label: {
                    Label(holding.isPinned ? "取消置顶" : "置顶", systemImage: holding.isPinned ? "pin.slash.fill" : "pin.fill")
                }
                .tint(holding.isPinned ? .orange : .blue)
            }
    }

    @ViewBuilder
    private func searchResultsListView() -> some View {
        let searchResults = dataManager.holdings.filter {
            $0.clientName.localizedCaseInsensitiveContains(searchText) ||
            $0.fundCode.localizedCaseInsensitiveContains(searchText) ||
            $0.fundName.localizedCaseInsensitiveContains(searchText) ||
            $0.clientID.localizedCaseInsensitiveContains(searchText) ||
            $0.remarks.localizedCaseInsensitiveContains(searchText)
        }
        
        // ** 修正问题 1：为搜索结果列表添加完整的背景和圆角框体 **
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                VStack {
                    Spacer()
                    Text("未找到符合条件的内容")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(searchResults.prefix(loadedSearchResultCount)) { holding in
                        holdingRowWithSwipeActions(for: holding, hideClientInfo: false)
                            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                            .listRowSeparator(.hidden)
                            .onAppear {
                                if holding.id == searchResults.prefix(loadedSearchResultCount).last?.id && loadedSearchResultCount < searchResults.count {
                                    loadedSearchResultCount += 10
                                    fundService.addLog("ClientView: 加载更多搜索结果。当前数量: \(loadedSearchResultCount)", type: .info)
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 确保占据全部可用空间
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 2)
        .padding(.bottom, 0) // 移除底部padding，让框体延伸到导航栏
        .allowsHitTesting(!isRefreshing)
    }

    // 新的客户组视图 - 使用类似于ManageHoldingsView的展开方式
    private func clientGroupItemView(clientGroup: ClientGroup) -> some View {
        let baseColor = clientGroup.id.morandiColor()
        let isExpanded = expandedClients.contains(clientGroup.id)
        
        return VStack(spacing: 0) {
            // 客户组标题 - 固定不动
            HStack(alignment: .center, spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isExpanded {
                            expandedClients.remove(clientGroup.id)
                        } else {
                            expandedClients.insert(clientGroup.id)
                        }
                    }
                }) {
                    HStack(alignment: .center, spacing: 8) {
                        let clientName = isPrivacyModeEnabled ? processClientName(clientGroup.clientName) : clientGroup.clientName
                        
                        HStack(spacing: 8) {
                            Text("**\(clientName)**")
                                .font(.subheadline)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if !clientGroup.clientID.isEmpty {
                                Text("(\(clientGroup.clientID))")
                                    .font(.caption.monospaced())
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Text("持仓数:")
                                .font(.caption)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                            Text("\(clientGroup.holdings.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .italic()
                                .foregroundColor(colorForHoldingCount(clientGroup.holdings.count))
                            Text("支")
                                .font(.caption)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [baseColor.opacity(0.8), Color.clear]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .background(colorScheme == .dark ? Color(.secondarySystemGroupedBackground) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                
                // 三角箭头放在渐变条外右侧
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isExpanded {
                            expandedClients.remove(clientGroup.id)
                        } else {
                            expandedClients.insert(clientGroup.id)
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
            }
            
            // 基金卡片区域 - 淡入淡出
            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(clientGroup.holdings.prefix(loadedGroupedClientCount)) { holding in
                        // ** 修正问题 2：使用带滑动操作的视图 **
                        holdingRowWithSwipeActions(for: holding, hideClientInfo: true)
                            .onAppear {
                                if holding.id == clientGroup.holdings.prefix(loadedGroupedClientCount).last?.id && loadedGroupedClientCount < clientGroup.holdings.count {
                                    loadedGroupedClientCount += 10
                                    fundService.addLog("ClientView: 加载更多客户分组。当前数量: \(loadedGroupedClientCount)", type: .info)
                                }
                            }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // 置顶区域视图
    private func pinnedSectionView() -> some View {
        let isExpanded = expandedClients.contains("Pinned")
        
        return VStack(spacing: 0) {
            // 置顶区域标题 - 固定不动
            HStack(alignment: .center, spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isExpanded {
                            expandedClients.remove("Pinned")
                        } else {
                            expandedClients.insert("Pinned")
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.white)
                        Text("置顶区域")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Text("持仓数:")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(pinnedHoldings.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .italic()
                                .foregroundColor(.white)
                            Text("支")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.3)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                
                // 三角箭头放在渐变条外右侧
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isExpanded {
                            expandedClients.remove("Pinned")
                        } else {
                            expandedClients.insert("Pinned")
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
            }
            
            // 置顶基金卡片区域 - 淡入淡出
            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(pinnedHoldings) { holding in
                        // ** 修正问题 2：使用带滑动操作的视图 **
                        holdingRowWithSwipeActions(for: holding, hideClientInfo: false)
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // 根据持仓数返回颜色
    private func colorForHoldingCount(_ count: Int) -> Color {
        if count == 1 {
            return .yellow
        } else if count <= 3 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func toggleAllCards() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if areAnyCardsExpanded {
                expandedClients.removeAll()
            } else {
                var allClientIds = Set(groupedHoldingsByClientName.map { $0.id })
                if !pinnedHoldings.isEmpty {
                    allClientIds.insert("Pinned")
                }
                expandedClients = allClientIds
            }
        }
    }
    
    private func togglePin(for holding: FundHolding) {
        if let index = dataManager.holdings.firstIndex(where: { $0.id == holding.id }) {
            let isPinned = dataManager.holdings[index].isPinned
            // 确保更新操作在主线程
            DispatchQueue.main.async {
                dataManager.holdings[index].isPinned.toggle()
                // 如果置顶，设置时间戳；如果取消置顶，设置为 nil
                dataManager.holdings[index].pinnedTimestamp = isPinned ? nil : Date()
                dataManager.saveData()
                refreshID = UUID() // 强制视图刷新以更新排序和 UI
                fundService.addLog("ClientView: 基金 \(holding.fundCode) 切换置顶状态: \(!isPinned)", type: .info)
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // 工具栏
                    HStack {
                        Button(action: {
                            toggleAllCards()
                        }) {
                            Image(systemName: areAnyCardsExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .font(.system(size: 18))
                                .foregroundColor(.accentColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .cornerRadius(8)
                    
                        Button(action: {
                            Task {
                                await refreshAllFundInfo()
                            }
                        }) {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .disabled(isRefreshing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .cornerRadius(8)
                    
                        Spacer()
                    
                        // 右上角文字显示 - 修改为"点击图标刷新"
                        if !isRefreshing {
                            if dataManager.holdings.isEmpty {
                                Text("请导入信息")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                                    .padding(.trailing, 8)
                            } else if hasLatestNavDate {
                                Text(latestNavDateString)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.4))
                                    .padding(.trailing, 8)
                            } else {
                                Text("点击图标刷新")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                                    .padding(.trailing, 8)
                            }
                        }
                        
                        if isRefreshing {
                            HStack(spacing: 6) {
                                if !currentRefreshingClientName.isEmpty {
                                    let displayClientName = isPrivacyModeEnabled ? processClientName(currentRefreshingClientName) : currentRefreshingClientName
                                    Text("\(displayClientName)[\(currentRefreshingClientID)]")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                } else if !currentRefreshingClientID.isEmpty {
                                    Text("[\(currentRefreshingClientID)]")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                
                                Text("\(refreshProgress.current)/\(refreshProgress.total)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    
                    // 搜索栏
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
                    
                    if !searchText.isEmpty {
                        searchResultsListView()
                    } else {
                        VStack(spacing: 0) {
                            if groupedHoldingsByClientName.isEmpty && pinnedHoldings.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("当前没有数据")
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal, 2)
                            } else {
                                HStack(spacing: 8) {
                                    if isQuickNavBarEnabled && !sortedSectionKeys.isEmpty {
                                        VStack(spacing: 2) {
                                            ScrollView(.vertical, showsIndicators: false) {
                                                VStack(spacing: 2) {
                                                    ForEach(sortedSectionKeys, id: \.self) { titleChar in
                                                        Button(action: {
                                                            withAnimation {
                                                                if titleChar == "★" {
                                                                    scrollViewProxy?.scrollTo("Pinned", anchor: .top)
                                                                } else if let firstClient = sectionedClientGroups[titleChar]?.first {
                                                                    scrollViewProxy?.scrollTo(firstClient.id, anchor: .top)
                                                                }
                                                            }
                                                        }) {
                                                            Text(String(titleChar))
                                                                .font(.caption)
                                                                .fontWeight(.bold)
                                                                .frame(width: 24, height: 24)
                                                                .background(Color.gray.opacity(0.2))
                                                                .cornerRadius(8)
                                                                .foregroundColor(.primary)
                                                        }
                                                        .padding(.vertical, 2)
                                                    }
                                                }
                                                .padding(.vertical, 10)
                                            }
                                            .frame(maxHeight: .infinity)
                                        }
                                        .frame(width: 44)
                                        .background(Color(.systemGroupedBackground))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                    
                                    ScrollViewReader { proxy in
                                        ScrollView {
                                            LazyVStack(spacing: 0) {
                                                if !pinnedHoldings.isEmpty {
                                                    pinnedSectionView()
                                                        .id("Pinned")
                                                }
                                                
                                                ForEach(sortedSectionKeys.filter { $0 != "★" }, id: \.self) { sectionKey in
                                                    let clientsForSection = sectionedClientGroups[sectionKey]?.sorted(by: { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }) ?? []
                                                    ForEach(clientsForSection) { clientGroup in
                                                        clientGroupItemView(clientGroup: clientGroup)
                                                            .id(clientGroup.id)
                                                    }
                                                }
                                            }
                                            .padding(.bottom, 20)
                                        }
                                        .onAppear {
                                            scrollViewProxy = proxy
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
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(!isRefreshing)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .allowsHitTesting(!isRefreshing)
                
                // Toast视图 - 添加淡入淡出动画
                VStack {
                    Spacer()
                        .frame(height: 180)
                    
                    if showRefreshCompleteToast {
                        ToastView(message: "更新完成", isShowing: $showRefreshCompleteToast)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    
                    if showingOutdatedDataToast {
                        ToastView(message: "非最新数据，建议更新", isShowing: $showingOutdatedDataToast)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: showRefreshCompleteToast)
                .animation(.easeInOut(duration: 0.3), value: showingOutdatedDataToast)
                
                // 刷新中提示 - 添加淡入淡出动画
                if isRefreshing {
                    Color.black.opacity(0.01)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        Spacer()
                        ToastView(message: "更新中...", isShowing: $isRefreshing)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        Spacer()
                    }
                    .zIndex(999)
                    .animation(.easeInOut(duration: 0.3), value: isRefreshing)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // 在刷新时禁用页面切换（除了ConfigView）
            .onChange(of: isRefreshing) { oldValue, newValue in
                if newValue {
                    // 发送通知，告诉主TabView锁定页面切换
                    NotificationCenter.default.post(name: Notification.Name("RefreshLockEnabled"), object: nil)
                } else {
                    // 发送通知，告诉主TabView解锁页面切换
                    NotificationCenter.default.post(name: Notification.Name("RefreshLockDisabled"), object: nil)
                }
            }
        }
        .onAppear {
            // 页面出现时检查是否需要显示非最新数据提示
            if !hasLatestNavDate && !dataManager.holdings.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingOutdatedDataToast = true
                    }
                    // 1.5秒后自动隐藏
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingOutdatedDataToast = false
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            loadedSearchResultCount = 10
            loadedGroupedClientCount = 10
            if newValue.isEmpty {
                expandedClients.removeAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("QuickNavBarStateChanged"))) { _ in
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HoldingsDataUpdated"))) { _ in
            refreshID = UUID()
        }
    }
    
    private func refreshAllFundInfo() async {
        await MainActor.run {
            isRefreshing = true
            refreshProgress = (0, dataManager.holdings.count)
            currentRefreshingClientName = ""
            currentRefreshingClientID = ""
            NotificationCenter.default.post(name: Notification.Name("RefreshStarted"), object: nil)
        }
        
        fundService.addLog("ClientView: 开始刷新所有基金信息...", type: .info)

        let totalCount = dataManager.holdings.count
        
        if totalCount == 0 {
            await MainActor.run {
                isRefreshing = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    showRefreshCompleteToast = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showRefreshCompleteToast = false
                    }
                }
            }
            return
        }
        
        var updatedHoldings: [UUID: FundHolding] = [:]
        
        await withTaskGroup(of: (UUID, FundHolding?).self) { group in
            var iterator = dataManager.holdings.makeIterator()
            var activeTasks = 0
            
            while activeTasks < maxConcurrentRequests, let holding = iterator.next() {
                group.addTask {
                    await self.fetchHoldingWithRetry(holding: holding)
                }
                activeTasks += 1
            }

            while let result = await group.next() {
                activeTasks -= 1
                await self.processHoldingResult(result: result, updatedHoldings: &updatedHoldings, totalCount: totalCount)
                
                if let nextHolding = iterator.next() {
                    group.addTask {
                        await self.fetchHoldingWithRetry(holding: nextHolding)
                    }
                    activeTasks += 1
                }
            }
        }

        await MainActor.run {
            for (index, holding) in dataManager.holdings.enumerated() {
                if let updatedHolding = updatedHoldings[holding.id] {
                    dataManager.holdings[index] = updatedHolding
                }
            }
            
            dataManager.saveData()
            
            self.isRefreshing = false
            self.currentRefreshingClientName = ""
            self.currentRefreshingClientID = ""
            withAnimation(.easeInOut(duration: 0.3)) {
                self.showRefreshCompleteToast = true
            }

            let stats = (success: self.refreshProgress.current, fail: totalCount - self.refreshProgress.current)
            NotificationCenter.default.post(name: Notification.Name("RefreshCompleted"), object: nil, userInfo: ["stats": stats])

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.showRefreshCompleteToast = false
                }
            }

            NotificationCenter.default.post(name: Notification.Name("HoldingsDataUpdated"), object: nil)
            fundService.addLog("ClientView: 所有基金信息刷新完成。", type: .info)
        }
    }
    
    private func fetchHoldingWithRetry(holding: FundHolding) async -> (UUID, FundHolding?) {
        var retryCount = 0
        
        while retryCount < 3 {
            let fetchedInfo = await fundService.fetchFundInfo(code: holding.fundCode)
            var updatedHolding = holding
            updatedHolding.fundName = fetchedInfo.fundName
            updatedHolding.currentNav = fetchedInfo.currentNav
            updatedHolding.navDate = fetchedInfo.navDate
            updatedHolding.isValid = fetchedInfo.isValid
            
            if fetchedInfo.isValid {
                let fundDetails = await fundService.fetchFundDetailsFromEastmoney(code: holding.fundCode)
                updatedHolding.navReturn1m = fundDetails.returns.navReturn1m
                updatedHolding.navReturn3m = fundDetails.returns.navReturn3m
                updatedHolding.navReturn6m = fundDetails.returns.navReturn6m
                updatedHolding.navReturn1y = fundDetails.returns.navReturn1y
                
                return (holding.id, updatedHolding)
            }
            
            retryCount += 1
            if retryCount < 3 {
                let retryDelay = Double(retryCount) * 0.5
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        
        return (holding.id, nil)
    }
    
    private func processHoldingResult(result: (UUID, FundHolding?), updatedHoldings: inout [UUID: FundHolding], totalCount: Int) async {
        let (holdingId, updatedHolding) = result
        
        await MainActor.run {
            if let updatedHolding = updatedHolding {
                updatedHoldings[holdingId] = updatedHolding
                
                if let originalHolding = dataManager.holdings.first(where: { $0.id == holdingId }) {
                    currentRefreshingClientName = originalHolding.clientName
                    currentRefreshingClientID = originalHolding.clientID
                }
                
                refreshProgress.current = min(refreshProgress.current + 1, totalCount)
                fundService.addLog("基金 \(updatedHolding.fundCode) 刷新成功", type: .success)
            } else {
                refreshProgress.current = min(refreshProgress.current + 1, totalCount)
                if let originalHolding = dataManager.holdings.first(where: { $0.id == holdingId }) {
                    fundService.addLog("基金 \(originalHolding.fundCode) 刷新失败", type: .error)
                }
            }
        }
    }
}
