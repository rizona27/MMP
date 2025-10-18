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

class ToastQueueManager: ObservableObject {
    @Published var toasts: [ToastItem] = []
    private var activeToastIds: Set<String> = []
    
    struct ToastItem: Identifiable {
        let id = UUID()
        let message: String
        let type: ToastType
        var showTime: Double
    }
    
    enum ToastType {
        case copy, report, refresh, outdated
    }
    
    func addToast(_ message: String, type: ToastType, showTime: Double = 1.5) {
        // 检查是否已经存在相同的Toast消息
        let toastId = "\(message)-\(type)"
        guard !activeToastIds.contains(toastId) else { return }
        
        let toast = ToastItem(message: message, type: type, showTime: showTime)
        
        // 使用动画添加Toast
        withAnimation(.easeInOut(duration: 0.3)) {
            toasts.append(toast)
        }
        activeToastIds.insert(toastId)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + showTime) { [weak self] in
            self?.removeToast(toast.id)
            self?.activeToastIds.remove(toastId)
        }
    }
    
    func removeToast(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.3)) {
            toasts.removeAll { $0.id == id }
        }
    }
    
    func removeAll() {
        withAnimation(.easeInOut(duration: 0.3)) {
            toasts.removeAll()
        }
        activeToastIds.removeAll()
    }
}

struct ClientView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @StateObject private var toastQueue = ToastQueueManager()
    @State private var isRefreshing = false
    
    @Environment(\.colorScheme) var colorScheme

    @State private var expandedClients: Set<String> = []
    
    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled: Bool = false
    
    @State private var loadedGroupedClientCount: Int = 10
    
    @State private var searchText = ""
    @State private var loadedSearchResultCount: Int = 10

    @State private var refreshID = UUID()

    @State private var refreshProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentRefreshingClientName: String = ""
    @State private var currentRefreshingClientID: String = ""
    
    @State private var swipedHoldingStates: [UUID: SwipeState] = [:]
    
    private let maxConcurrentRequests = 3

    private let calendar = Calendar.current

    private struct SwipeState {
        var isSwiped: Bool = false
        var dragOffset: CGFloat = 0
    }

    private static let dateFormatterYY_MM_DD: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM-dd"
        return formatter
    }()

    private static let dateFormatterMM_DD: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    private var previousWorkday: Date {
        let today = Date()
        var date = calendar.startOfDay(for: today)

        while true {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            let weekday = calendar.component(.weekday, from: date)
            if weekday >= 2 && weekday <= 6 {
                return date
            }
        }
    }
    
    private var hasLatestNavDate: Bool {
        if dataManager.holdings.isEmpty || dataManager.holdings.allSatisfy({ !$0.isValid }) {
            return false
        }
        
        let previousWorkdayStart = previousWorkday
        return dataManager.holdings.contains { holding in
            holding.isValid && calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
    }
    
    private var outdatedClients: [String] {
        let previousWorkdayStart = previousWorkday
        let outdatedHoldings = dataManager.holdings.filter { holding in
            holding.isValid && !calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
        return Array(Set(outdatedHoldings.map { $0.clientName }))
    }

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
            let previousWorkdayString = formatter.string(from: previousWorkday)
            return "待更新: \(previousWorkdayString)"
        }
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
                clientName: "置顶分栏",
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
        let displayHolding: FundHolding = {
            if isPrivacyModeEnabled {
                var modifiedHolding = holding
                modifiedHolding.clientName = processClientName(holding.clientName)
                return modifiedHolding
            } else {
                return holding
            }
        }()
        
        return HoldingRow(holding: displayHolding, hideClientInfo: hideClientInfo,
                         onCopyClientID: { message in
            let toastMessage = "客户号(\(holding.clientID))\n已经复制到剪贴板"
            toastQueue.addToast(toastMessage, type: .copy)
        }, onGenerateReport: { holding in
            // 检查是否已获取有效净值数据
            if !holding.isValid || holding.currentNav <= 0.0001 {
                toastQueue.addToast("更新数据后可用", type: .outdated, showTime: 2)
                return
            }
            
            let reportContent = generateReportContent(for: holding)
            UIPasteboard.general.string = reportContent
            let toastMessage = "\(reportContent)"
            toastQueue.addToast(toastMessage, type: .report, showTime: 3)
        })
            .environmentObject(dataManager)
            .environmentObject(fundService)
    }
    
    private func processClientName(_ name: String) -> String {
        if name.count <= 1 {
            return name
        } else if name.count == 2 {
            return String(name.prefix(1)) + "*"
        } else {
            return String(name.prefix(1)) + "*" + String(name.suffix(1))
        }
    }
    
    private func generateReportContent(for holding: FundHolding) -> String {
        let profit = dataManager.calculateProfit(for: holding)
        let holdingDays = calculateHoldingDays(for: holding)
        let purchaseAmountFormatted = formatPurchaseAmount(holding.purchaseAmount)
        let formattedCurrentNav = String(format: "%.4f", holding.currentNav)
        let formattedAbsoluteProfit = String(format: "%.2f", profit.absolute)
        let formattedAnnualizedProfit = String(format: "%.2f", profit.annualized)
        let absoluteReturnPercentage = holding.purchaseAmount > 0 ? (profit.absolute / holding.purchaseAmount) * 100 : 0
        let formattedAbsoluteReturnPercentage = String(format: "%.2f", absoluteReturnPercentage)

        let navDateString = Self.dateFormatterMM_DD.string(from: holding.navDate)

        return """
        \(holding.fundName) | \(holding.fundCode)
        ├ 购买日期:\(Self.dateFormatterYY_MM_DD.string(from: holding.purchaseDate))
        ├ 持有天数:\(holdingDays)天
        ├ 购买金额:\(purchaseAmountFormatted)
        ├ 最新净值:\(formattedCurrentNav) | \(navDateString)
        ├ 收益:\(profit.absolute > 0 ? "+" : "")\(formattedAbsoluteProfit)
        ├ 收益率:\(formattedAnnualizedProfit)%(年化)
        └ 收益率:\(formattedAbsoluteReturnPercentage)%(绝对)
        """
    }
    
    private func calculateHoldingDays(for holding: FundHolding) -> Int {
        let endDate = holding.navDate
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: holding.purchaseDate), to: calendar.startOfDay(for: endDate))
        return (components.day ?? 0) + 1
    }
    
    private func formatPurchaseAmount(_ amount: Double) -> String {
        var formattedString: String
        if amount >= 10000 && amount.truncatingRemainder(dividingBy: 10000) == 0 {
            formattedString = String(format: "%.0f", amount / 10000.0) + "万"
        } else if amount >= 10000 {
            formattedString = String(format: "%.2f", amount / 10000.0) + "万"
        } else {
            formattedString = String(format: "%.2f", amount) + "元"
        }
        return formattedString
    }
    
    private func swipeToPinView(for holding: FundHolding, hideClientInfo: Bool) -> some View {
        let swipeStateBinding = Binding(
            get: { self.swipedHoldingStates[holding.id, default: SwipeState()] },
            set: { self.swipedHoldingStates[holding.id] = $0 }
        )
        
        return ZStack(alignment: .leading) {
            if swipeStateBinding.wrappedValue.isSwiped {
                HStack {
                    Button(action: {
                        togglePin(for: holding)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            swipeStateBinding.wrappedValue = SwipeState(isSwiped: false, dragOffset: 0)
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: holding.isPinned ? "pin.slash.fill" : "pin.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            
                            if holding.isPinned {
                                VStack(spacing: 0) {
                                    Text("取")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("消")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("置")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("顶")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .lineLimit(1)
                            } else {
                                Text("置\n顶")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                        .frame(width: 50)
                        .frame(maxHeight: .infinity)
                        .background(holding.isPinned ? Color.orange : Color.blue)
                        .cornerRadius(6)
                    }
                    .padding(.leading, 8)
                    
                    Spacer()
                }
            }
            
            holdingRowView(for: holding, hideClientInfo: hideClientInfo)
                .offset(x: swipeStateBinding.wrappedValue.isSwiped ? swipeStateBinding.wrappedValue.dragOffset : 0)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if value.translation.width > 0 {
                                let newOffset = min(value.translation.width, 60)
                                swipeStateBinding.wrappedValue = SwipeState(isSwiped: true, dragOffset: newOffset)
                            }
                        }
                        .onEnded { value in
                            if value.translation.width > 40 {
                                togglePin(for: holding)
                            }
                            
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                swipeStateBinding.wrappedValue = SwipeState(isSwiped: false, dragOffset: 0)
                            }
                        }
                )
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: swipeStateBinding.wrappedValue.isSwiped)
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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(searchResults.prefix(loadedSearchResultCount)) { holding in
                            swipeToPinView(for: holding, hideClientInfo: false)
                                .onAppear {
                                    if holding.id == searchResults.prefix(loadedSearchResultCount).last?.id && loadedSearchResultCount < searchResults.count {
                                        loadedSearchResultCount += 10
                                        fundService.addLog("ClientView: 加载更多搜索结果。当前数量: \(loadedSearchResultCount)", type: .info)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
        .padding(.bottom, 0)
        .allowsHitTesting(!isRefreshing)
    }

    private func clientGroupItemView(clientGroup: ClientGroup) -> some View {
        let baseColor = clientGroup.id.morandiColor()
        let isExpanded = expandedClients.contains(clientGroup.id)
        
        return VStack(spacing: 0) {
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
                    HStack(alignment: .center, spacing: 4) {
                        let clientName = isPrivacyModeEnabled ? processClientName(clientGroup.clientName) : clientGroup.clientName
                        
                        HStack(spacing: 6) {
                            Text("**\(clientName)**")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if !clientGroup.clientID.isEmpty {
                                Text("(\(clientGroup.clientID))")
                                    .font(.system(size: 11))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Text("持仓数:")
                                .font(.system(size: 11))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                            Text("\(clientGroup.holdings.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .italic()
                                .foregroundColor(colorForHoldingCount(clientGroup.holdings.count))
                            Text("支")
                                .font(.system(size: 11))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 6)
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
            }
            
            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(clientGroup.holdings.prefix(loadedGroupedClientCount)) { holding in
                        swipeToPinView(for: holding, hideClientInfo: true)
                            .onAppear {
                                if holding.id == clientGroup.holdings.prefix(loadedGroupedClientCount).last?.id && loadedGroupedClientCount < clientGroup.holdings.count {
                                    loadedGroupedClientCount += 10
                                    fundService.addLog("ClientView: 加载更多客户分组。当前数量: \(loadedGroupedClientCount)", type: .info)
                                }
                            }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    private func pinnedSectionView() -> some View {
        let isExpanded = expandedClients.contains("Pinned")
        
        return VStack(spacing: 0) {
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
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        Text("置顶分栏")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Text("置顶数:")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(pinnedHoldings.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .italic()
                                .foregroundColor(colorForHoldingCount(pinnedHoldings.count))
                            Text("支")
                                .font(.system(size: 11))
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
            }
            
            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(pinnedHoldings) { holding in
                        swipeToPinView(for: holding, hideClientInfo: false)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
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
            DispatchQueue.main.async {
                dataManager.holdings[index].isPinned.toggle()
                dataManager.holdings[index].pinnedTimestamp = isPinned ? nil : Date()
                dataManager.saveData()
                refreshID = UUID()
                fundService.addLog("ClientView: 基金 \(holding.fundCode) 切换置顶状态: \(!isPinned)", type: .info)
                
                // 如果取消置顶后置顶区域为空，则自动折叠
                if isPinned && self.pinnedHoldings.isEmpty {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.expandedClients.remove("Pinned")
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
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
                    
                        if isRefreshing {
                            HStack(spacing: 6) {
                                if !currentRefreshingClientName.isEmpty {
                                    let displayClientName = isPrivacyModeEnabled ? processClientName(currentRefreshingClientName) : currentRefreshingClientName
                                    Text("\(displayClientName)")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                if !currentRefreshingClientID.isEmpty {
                                    Text("[\(currentRefreshingClientID)]")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                
                                Text("\(refreshProgress.current)/\(refreshProgress.total)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 8)
                        } else {
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
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    
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
                                .buttonStyle(PlainButtonStyle())
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
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        if !pinnedHoldings.isEmpty {
                                            pinnedSectionView()
                                        }
                                        
                                        ForEach(sortedSectionKeys.filter { $0 != "★" }, id: \.self) { sectionKey in
                                            let clientsForSection = sectionedClientGroups[sectionKey]?.sorted(by: { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }) ?? []
                                            ForEach(clientsForSection) { clientGroup in
                                                clientGroupItemView(clientGroup: clientGroup)
                                            }
                                        }
                                    }
                                    .padding(.bottom, 20)
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(!isRefreshing)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .allowsHitTesting(!isRefreshing)
                
                // Toast显示区域 - 使用与SummaryView完全相同的效果
                if !toastQueue.toasts.isEmpty {
                    VStack {
                        Spacer()
                        
                        ForEach(toastQueue.toasts) { toast in
                            if toast.type == .report {
                                VStack(spacing: 4) {
                                    ScrollView {
                                        Text(toast.message)
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                            .padding(.horizontal, 4)
                                    }
                                    .frame(maxHeight: 150)
                                    
                                    Text("以上报告已复制到剪贴板")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 2)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            } else {
                                ToastView(message: toast.message, isShowing: .constant(true))
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(998)
                }
                
                if isRefreshing {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                        .allowsHitTesting(true)
                        .zIndex(999)

                    VStack {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            
                            Text("更新中...")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                        )
                        .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1000)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .onAppear {
            if !hasLatestNavDate && !dataManager.holdings.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    toastQueue.addToast("非最新数据，建议更新", type: .outdated)
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
            NotificationCenter.default.post(name: Notification.Name("RefreshLockEnabled"), object: nil)
        }
        
        fundService.addLog("ClientView: 开始刷新所有基金信息...", type: .info)

        let totalCount = dataManager.holdings.count
        
        if totalCount == 0 {
            await MainActor.run {
                completeRefresh()
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
            completeRefresh()
            
            let stats = (success: self.refreshProgress.current, fail: totalCount - self.refreshProgress.current)
            NotificationCenter.default.post(name: Notification.Name("RefreshCompleted"), object: nil, userInfo: ["stats": stats])

            NotificationCenter.default.post(name: Notification.Name("HoldingsDataUpdated"), object: nil)
            fundService.addLog("ClientView: 所有基金信息刷新完成。", type: .info)
        }
    }
    
    private func completeRefresh() {
        self.isRefreshing = false
        self.currentRefreshingClientName = ""
        self.currentRefreshingClientID = ""
        
        NotificationCenter.default.post(name: Notification.Name("RefreshLockDisabled"), object: nil)
        
        toastQueue.addToast("更新完成", type: .refresh)
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
