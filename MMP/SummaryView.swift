import SwiftUI
import Foundation

// MARK: - 通用辅助视图和扩展

extension Double {
    // 将Double转换为带百分号的字符串，保留两位小数
    var formattedPercentage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self / 100)) ?? "\(self)%"
    }
}

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

enum SortOrder: String, CaseIterable, Identifiable {
    case ascending = "升序"
    case descending = "降序"

    var id: String { self.rawValue }
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
        return self.luminance() > 0.5 ? .black : .white
    }
}

extension Color {
    func morandiColor() -> Color {
        let colors: [Color] = [
            Color(red: 0.8, green: 0.85, blue: 0.85),
            Color(red: 0.75, green: 0.8, blue: 0.9),
            Color(red: 0.9, green: 0.8, blue: 0.8),
            Color(red: 0.8, green: 0.9, blue: 0.8),
            Color(red: 0.9, green: 0.85, blue: 0.75)
        ]
        let index = Int(self.hashValue) % colors.count
        return colors[abs(index)]
    }
}

extension Date {
    func isOlderThan(minutes: Int) -> Bool {
        let calendar = Calendar.current
        let expirationDate = calendar.date(byAdding: .minute, value: minutes, to: self) ?? Date()
        return expirationDate < Date()
    }
}

// MARK: - SummaryView
struct SummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService

    @State private var isRefreshing = false
    @State private var unrecognizedFunds: [FundHolding] = []
    @State private var showingToast = false

    @State private var selectedSortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending
    
    @State private var expandedFundCodes: Set<String> = []

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
    
    // MARK: - 新增移除未识别基金的方法
    private func removeUnrecognizedFund(fund: FundHolding) {
        if let index = unrecognizedFunds.firstIndex(where: { $0.fundCode == fund.fundCode }) {
            unrecognizedFunds.remove(at: index)
            saveUnrecognizedFunds()
        }
    }

    // 将recognizedFunds改为一个分组后的字典
    private var recognizedFunds: [String: [FundHolding]] {
        let unrecognizedFundCodes = Set(unrecognizedFunds.map { $0.fundCode })
        let filteredFunds = dataManager.holdings.filter { holding in
            !unrecognizedFundCodes.contains(holding.fundCode)
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

    // 重新定义排序逻辑，现在排序的是基金代码
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
    
    // 使用新的 totalValue 计算持有收益率
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
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
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
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
                
                List {
                    if dataManager.holdings.isEmpty && unrecognizedFunds.isEmpty {
                        Text("当前没有基金持仓数据")
                            .foregroundColor(.gray)
                    } else {
                        // 遍历排序后的基金代码
                        ForEach(sortedFundCodes, id: \.self) { fundCode in
                            if let funds = recognizedFunds[fundCode], let _ = funds.first {
                                FundHoldingCard(
                                    funds: funds,
                                    isExpanded: Binding(
                                        get: { expandedFundCodes.contains(fundCode) },
                                        set: { isExpanded in
                                            if isExpanded {
                                                expandedFundCodes.insert(fundCode)
                                            } else {
                                                expandedFundCodes.remove(fundCode)
                                            }
                                        }
                                    ),
                                    selectedSortKey: selectedSortKey,
                                    getHoldingReturn: getHoldingReturn
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .refreshable {
                    await refreshFundReturns()
                }

                // MARK: - 更新后的未识别基金模块
                if !unrecognizedFunds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("未能识别基金:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // 使用 ForEach 遍历并添加移除按钮
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(unrecognizedFunds, id: \.fundCode) { fund in
                                    HStack(spacing: 4) {
                                        Text(fund.fundCode)
                                            .font(.caption.monospaced())
                                            .foregroundColor(.secondary)
                                        
                                        Button(action: {
                                            withAnimation {
                                                removeUnrecognizedFund(fund: fund)
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                // 加载已保存的未识别基金
                unrecognizedFunds = persistentUnrecognizedFunds
            }
            
            ToastView(message: "刷新成功！", isShowing: $showingToast)
                .padding(.bottom, unrecognizedFunds.isEmpty ? 80 : 160)
        }
    }
    
    // MARK: - 操作方法

    private func refreshFundReturns() async {
        isRefreshing = true
        fundService.addLog("开始刷新基金收益率数据...")

        let originalHoldings = dataManager.holdings

        var updatedHoldings: [FundHolding] = []
        var newlyUnrecognizedFunds: [FundHolding] = []

        for var holding in originalHoldings {
            let updatedFund = await fundService.fetchFundInfo(code: holding.fundCode)
            
            holding.fundName = updatedFund.fundName
            holding.currentNav = updatedFund.currentNav
            holding.navDate = updatedFund.navDate
            holding.isValid = updatedFund.isValid
            holding.navReturn1m = updatedFund.navReturn1m
            holding.navReturn3m = updatedFund.navReturn3m
            holding.navReturn6m = updatedFund.navReturn6m
            holding.navReturn1y = updatedFund.navReturn1y
            
            if holding.isValid {
                updatedHoldings.append(holding)
            } else {
                newlyUnrecognizedFunds.append(holding)
            }
        }
        
        await MainActor.run {
            dataManager.holdings = updatedHoldings
            
            let currentUnrecognizedCodes = Set(unrecognizedFunds.map { $0.fundCode })
            for fund in newlyUnrecognizedFunds {
                if !currentUnrecognizedCodes.contains(fund.fundCode) {
                    unrecognizedFunds.append(fund)
                }
            }
            
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

// 独立的基金卡片视图
struct FundHoldingCard: View {
    var funds: [FundHolding]
    @Binding var isExpanded: Bool
    var selectedSortKey: SortKey
    var getHoldingReturn: (FundHolding) -> Double?
    
    private var fund: FundHolding {
        funds.first!
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
    
    private func combinedClientAndReturnText() -> Text {
        let sortedFunds = funds.sorted { $0.clientName < $1.clientName }
        var combinedText: Text = Text("")
        
        for (index, holding) in sortedFunds.enumerated() {
            if index > 0 {
                combinedText = combinedText + Text("、")
            }
            combinedText = combinedText + Text(holding.clientName)
            
            if let holdingReturn = getHoldingReturn(holding) {
                combinedText = combinedText + Text("(\(holdingReturn.formattedPercentage))")
                    .foregroundColor(colorForValue(holdingReturn))
            }
        }
        return combinedText
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        gradient: Gradient(colors: [baseColor, .white]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                if selectedSortKey != .none {
                    VStack(alignment: .trailing) {
                        let valueString = getColumnValue(for: fund, keyPath: selectedSortKey.keyPathString)
                        let numberValue = Double(valueString.replacingOccurrences(of: "%", with: ""))
                        Text(valueString)
                            .font(.headline)
                            .foregroundColor(colorForValue(numberValue))
                    }
                    .padding(.horizontal, 16)
                }
                
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("近1月:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(fund.navReturn1m?.formattedPercentage ?? "/")
                                .font(.subheadline)
                                .foregroundColor(colorForValue(fund.navReturn1m))
                            Text("近3月:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(fund.navReturn3m?.formattedPercentage ?? "/")
                                .font(.subheadline)
                                .foregroundColor(colorForValue(fund.navReturn3m))
                        }
                        GridRow {
                            Text("近6月:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(fund.navReturn6m?.formattedPercentage ?? "/")
                                .font(.subheadline)
                                .foregroundColor(colorForValue(fund.navReturn6m))
                            Text("近1年:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(fund.navReturn1y?.formattedPercentage ?? "/")
                                .font(.subheadline)
                                .foregroundColor(colorForValue(fund.navReturn1y))
                        }
                    }
                    .padding(.top, 8)
                    
                    Divider()
                    
                    HStack(alignment: .top) {
                        Text("持有客户:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        combinedClientAndReturnText()
                            .font(.subheadline)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
