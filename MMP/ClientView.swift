import SwiftUI
import Foundation

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
    
    // 显示不是最新净值的客户列表
    private func showOutdatedClientsToast() {
        let outdatedClientsList = outdatedClients
        
        if outdatedClientsList.isEmpty {
            // 如果列表为空，不显示Toast
            return
        } else {
            // 最多显示5个，超过用...表示
            let displayList: [String]
            if outdatedClientsList.count > 5 {
                displayList = Array(outdatedClientsList.prefix(5)) + ["..."]
            } else {
                displayList = outdatedClientsList
            }
            
            navDateToastMessage = "以下信息待更新:\n" + displayList.joined(separator: "\n")
            showingNavDateToast = true
        }
    }
    
    // 处理净值待更新区域的点击事件
    private func handleNavDateTap() {
        // 如果是"暂无净值数据"，不显示Toast
        guard latestNavDateString != "暂无数据" else { return }
        
        showOutdatedClientsToast()
    }

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
            displayHolding.clientName = processClientName(holding.clientName)
        }
        return HoldingRow(holding: displayHolding, hideClientInfo: hideClientInfo)
            .environmentObject(dataManager)
            .environmentObject(fundService)
    }

    private func searchResultsListView() -> some View {
        List {
            let searchResults = dataManager.holdings.filter {
                $0.clientName.localizedCaseInsensitiveContains(searchText) ||
                $0.fundCode.localizedCaseInsensitiveContains(searchText) ||
                $0.fundName.localizedCaseInsensitiveContains(searchText) ||
                $0.clientID.localizedCaseInsensitiveContains(searchText) ||
                $0.remarks.localizedCaseInsensitiveContains(searchText)
            }
            
            if searchResults.isEmpty {
                Text("未找到符合条件的内容")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(searchResults.prefix(loadedSearchResultCount)) { holding in
                    holdingRowView(for: holding, hideClientInfo: false)
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
        }
        .listStyle(.plain)
        .padding(.bottom, 20)
    }

    private func pinnedHoldingsSection() -> some View {
        Section(header: EmptyView().id("★")) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedClients.contains("Pinned") },
                    set: { isExpanded in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedClients.insert("Pinned")
                            } else {
                                expandedClients.remove("Pinned")
                            }
                        }
                    }
                )
            ) {
                ForEach(pinnedHoldings) { holding in
                    holdingRowView(for: holding, hideClientInfo: false)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.white)
                        Text("置顶区域")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.white]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                    
                    HStack {
                        Text("基金总市值: \(pinnedHoldings.reduce(0.0) { $0 + $1.totalValue }, specifier: "%.2f")元")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("持有基金数: \(pinnedHoldings.count)支")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 0)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    private func clientGroupSection(clientGroup: ClientGroup, sectionKey: Character) -> some View {
        let baseColor = clientGroup.id.morandiColor()
        
        return DisclosureGroup(
            isExpanded: Binding(
                get: { expandedClients.contains(clientGroup.id) },
                set: { isExpanded in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedClients.insert(clientGroup.id)
                        } else {
                            expandedClients.remove(clientGroup.id)
                        }
                    }
                }
            )
        ) {
            ForEach(clientGroup.holdings.prefix(loadedGroupedClientCount)) { holding in
                holdingRowView(for: holding, hideClientInfo: true)
                    .onAppear {
                        if holding.id == clientGroup.holdings.prefix(loadedGroupedClientCount).last?.id && loadedGroupedClientCount < clientGroup.holdings.count {
                            loadedGroupedClientCount += 10
                            fundService.addLog("ClientView: 加载更多客户分组。当前数量: \(loadedGroupedClientCount)", type: .info)
                        }
                    }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    let clientName = isPrivacyModeEnabled ? processClientName(clientGroup.clientName) : clientGroup.clientName
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
                    Spacer()
                    
                    Text("持仓数: \(clientGroup.holdings.count)支")
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
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
        }
        .id(clientGroup.id)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
    }
    
    private func toggleAllCards() {
        withAnimation {
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

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // 工具栏 - 与SummaryView保持一致的高度和间距
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
                    
                        Spacer()
                    
                        // 新增：显示最新净值日期
                        if !isRefreshing {
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
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    
                    // 搜索栏 - 与SummaryView保持一致的样式和间距
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
                                // 修改：添加白色框体，与SummaryView一致
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
                                    
                                    VStack {
                                        ScrollViewReader { proxy in
                                            List {
                                                if !pinnedHoldings.isEmpty {
                                                    pinnedHoldingsSection()
                                                }
                                                
                                                ForEach(sortedSectionKeys.filter { $0 != "★" }, id: \.self) { sectionKey in
                                                    Section(header: EmptyView().id(sectionKey)) {
                                                        let clientsForSection = sectionedClientGroups[sectionKey]?.sorted(by: { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }) ?? []
                                                        ForEach(clientsForSection) { clientGroup in
                                                            clientGroupSection(clientGroup: clientGroup, sectionKey: sectionKey)
                                                        }
                                                    }
                                                }
                                            }
                                            .listStyle(.plain)
                                            .id(refreshID)
                                            .onAppear {
                                                scrollViewProxy = proxy
                                            }
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
                    }
                }
                .background(Color(.systemGroupedBackground))
                
                // Toast视图 - 调整到列表框体位置
                VStack {
                    Spacer()
                        .frame(height: 180) // 调整这个值使Toast显示在列表框体位置
                    
                    if showRefreshCompleteToast {
                        ToastView(message: "刷新完成", isShowing: $showRefreshCompleteToast)
                    }
                    
                    if showingNavDateToast {
                        ToastView(message: navDateToastMessage, isShowing: $showingNavDateToast)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .onAppear {
            // 首次打开时检查是否需要自动更新
            if !hasLatestNavDate && !dataManager.holdings.isEmpty {
                // 显示净值待更新提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showOutdatedClientsToast()
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
        }
        
        fundService.addLog("ClientView: 开始刷新所有基金信息...", type: .info)

        let totalCount = dataManager.holdings.count
        
        if totalCount == 0 {
            await MainActor.run {
                isRefreshing = false
                showRefreshCompleteToast = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showRefreshCompleteToast = false
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
            // 更新所有持仓数据
            for (index, holding) in dataManager.holdings.enumerated() {
                if let updatedHolding = updatedHoldings[holding.id] {
                    dataManager.holdings[index] = updatedHolding
                }
            }
            
            dataManager.saveData()
            
            self.isRefreshing = false
            self.currentRefreshingClientName = ""
            self.currentRefreshingClientID = ""
            self.showRefreshCompleteToast = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showRefreshCompleteToast = false
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
            
            // 修复问题2：在ClientView刷新时也获取收益率数据
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
                
                // 更新当前刷新显示的客户信息
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
