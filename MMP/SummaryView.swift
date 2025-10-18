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

    @State private var showingToast = false
    @State private var selectedSortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending
    @State private var expandedFundCodes: Set<String> = []
    @State private var refreshID = UUID()
    @State private var searchText = ""
    @State private var showingNavDateToast = false
    @State private var navDateToastMessage = ""
    @State private var hasShownInitialToast = false

    private let calendar = Calendar.current
    
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
    
    private var hasAnyLatestNavDate: Bool {
        if dataManager.holdings.isEmpty || dataManager.holdings.allSatisfy({ !$0.isValid }) {
            return false
        }
        
        let previousWorkdayStart = calendar.startOfDay(for: previousWorkday)
        return dataManager.holdings.contains { holding in
            holding.isValid && calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
    }
    
    private var outdatedFunds: [FundHolding] {
        let previousWorkdayStart = calendar.startOfDay(for: previousWorkday)
        return dataManager.holdings.filter { holding in
            holding.isValid && !calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
    }
    
    private var upToDateFunds: [FundHolding] {
        let previousWorkdayStart = calendar.startOfDay(for: previousWorkday)
        return dataManager.holdings.filter { holding in
            holding.isValid && calendar.isDate(holding.navDate, inSameDayAs: previousWorkdayStart)
        }
    }
    
    private var outdatedFundCodes: [String] {
        Array(Set(outdatedFunds.map { $0.fundCode }))
    }
    
    private var latestNavDate: Date? {
        dataManager.holdings
            .filter { $0.isValid && $0.navDate <= Date() }
            .map { $0.navDate }
            .max()
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
        withAnimation(.easeInOut(duration: 0.3)) {
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
        guard fund.isValid && fund.purchaseAmount > 0 else { return nil }
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
    
    private func fundGroupItemView(fundCode: String, funds: [FundHolding]) -> some View {
        let baseColor = fundCode.morandiColor()
        let isExpanded = expandedFundCodes.contains(fundCode)
        let firstFund = funds.first!
        
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isExpanded {
                            expandedFundCodes.remove(fundCode)
                        } else {
                            expandedFundCodes.insert(fundCode)
                        }
                    }
                }) {
                    HStack(alignment: .center, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("**\(firstFund.fundName)**")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(firstFund.fundCode)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Text("持有人数:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("\(funds.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .italic()
                                .foregroundColor(colorForHoldingCount(funds.count))
                            Text("人")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
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
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                
                if selectedSortKey != .none {
                    VStack(alignment: .trailing) {
                        let valueString = getColumnValue(for: firstFund, keyPath: selectedSortKey.keyPathString)
                        let numberValue = Double(valueString.replacingOccurrences(of: "%", with: ""))
                        Text(valueString)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorForValue(numberValue))
                    }
                    .padding(.trailing, 16)
                    .padding(.leading, 8)
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("近1月:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text(firstFund.navReturn1m?.formattedPercentage ?? "/")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorForValue(firstFund.navReturn1m))
                            Text("近3月:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text(firstFund.navReturn3m?.formattedPercentage ?? "/")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorForValue(firstFund.navReturn3m))
                        }
                        GridRow {
                            Text("近6月:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text(firstFund.navReturn6m?.formattedPercentage ?? "/")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorForValue(firstFund.navReturn6m))
                            Text("近1年:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text(firstFund.navReturn1y?.formattedPercentage ?? "/")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorForValue(firstFund.navReturn1y))
                        }
                    }
                    
                    Divider()
                    
                    HStack(alignment: .top) {
                        Text("持有客户:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: true, vertical: false)

                        combinedClientAndReturnText(funds: funds, getHoldingReturn: getHoldingReturn, sortOrder: sortOrder, isPrivacyModeEnabled: isPrivacyModeEnabled)
                            .font(.system(size: 13))
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                .padding(.top, 8)
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
    
    var body: some View {
        NavigationView {
            ZStack {
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
                    
                        if !dataManager.holdings.isEmpty {
                            Text(statusText)
                                .font(.system(size: 14))
                                .foregroundColor(statusColor)
                                .padding(.trailing, 8)
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
                
                    VStack(spacing: 0) {
                        if dataManager.holdings.isEmpty {
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
                        } else if filteredHoldings.isEmpty && !searchText.isEmpty {
                            VStack {
                                Spacer()
                                Text("未找到符合条件的内容")
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
                                    ForEach(sortedFundCodes, id: \.self) { fundCode in
                                        if let funds = allGroupedFunds[fundCode] {
                                            fundGroupItemView(fundCode: fundCode, funds: funds)
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
                }
                .background(Color(.systemGroupedBackground))
                .navigationBarHidden(true)
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            
                if showingToast || showingNavDateToast {
                    VStack {
                        Spacer()
                        
                        if showingToast {
                            ToastView(message: toastMessage, isShowing: $showingToast)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        
                        if showingNavDateToast {
                            ToastView(message: navDateToastMessage, isShowing: $showingNavDateToast)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(999)
                }
            }
        }
        .onAppear {
            hasShownInitialToast = false
            
            checkAndShowOutdatedToast()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HoldingsDataUpdated"))) { _ in
            refreshID = UUID()
            hasShownInitialToast = false
        }
    }
    
    private var statusText: String {
        guard let latestDate = latestNavDate else {
            return "暂无数据"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        let dateString = formatter.string(from: latestDate)
        
        if hasAnyLatestNavDate {
            return "最新日期: \(dateString)"
        } else {
            let previousWorkdayString = formatter.string(from: previousWorkday)
            return "待更新: \(previousWorkdayString)"
        }
    }
    
    private var statusColor: Color {
        if hasAnyLatestNavDate {
            return Color(red: 0.4, green: 0.8, blue: 0.4)
        } else {
            return .orange
        }
    }
    
    private func checkAndShowOutdatedToast() {
        guard !dataManager.holdings.isEmpty && !outdatedFunds.isEmpty else {
            return
        }

        guard !hasShownInitialToast else {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingToast = true
                hasShownInitialToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingToast = false
                }
            }
        }
    }
    
    private var toastMessage: String {
        let outdatedCount = outdatedFunds.count
        var message = "非最新日期净值：\(outdatedCount)支\n"
        
        var uniqueFunds: [String: String] = [:]
        for fund in outdatedFunds {
            uniqueFunds[fund.fundCode] = fund.fundName
        }
        
        let displayFunds = Array(uniqueFunds.prefix(5))
        for (index, (fundCode, fundName)) in displayFunds.enumerated() {
            let displayName = fundName.count > 6 ? String(fundName.prefix(6)) + "..." : fundName
            message += "\(displayName)[\(fundCode)]"
            if index < displayFunds.count - 1 {
                message += "\n"
            }
        }

        if uniqueFunds.count > 5 {
            message += "\n..."
        }
        
        return message
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
        } else {
            clientText = clientText + Text("(/)")
                .foregroundColor(.gray)
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
