import SwiftUI
import Foundation

struct TopPerformersView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    @State private var isFilterExpanded: Bool = false
    
    @State private var fundCodeFilterInput: String = ""
    @State private var minAmountInput: String = ""
    @State private var maxAmountInput: String = ""
    @State private var minDaysInput: String = ""
    @State private var maxDaysInput: String = ""
    @State private var varprofitInput: String = ""
    @State private var maxProfitInput: String = ""

    @State private var appliedFundCodeFilter: String = ""
    @State private var appliedMinAmount: String = ""
    @State private var appliedMaxAmount: String = ""
    @State private var appliedMinDays: String = ""
    @State private var appliedMaxDays: String = ""
    @State private var appliedMinProfit: String = ""
    @State private var appliedMaxProfit: String = ""
    
    @State private var showingToast = false
    @State private var toastMessage: String = ""
    @State private var isLoading = false
    @State private var precomputedHoldings: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)] = []
    
    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled: Bool = false
    
    @State private var selectedSortKey: SortKey = .none
    @State private var sortOrder: SortOrder = .descending

    @State private var cachedSortedHoldings: [String: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)]] = [:]

    private var dataChangeListener: some View {
        Text("")
            .onChange(of: dataManager.holdings) {
                refreshData()
            }
    }

    enum SortKey: String, CaseIterable, Identifiable {
        case none = "无排序"
        case amount = "金额"
        case profit = "收益"
        case yield = "收益率"
        case days = "天数"

        var id: String { self.rawValue }
        
        var next: SortKey {
            switch self {
            case .none: return .amount
            case .amount: return .profit
            case .profit: return .yield
            case .yield: return .days
            case .days: return .none
            }
        }
        
        var color: Color {
            switch self {
            case .none: return .primary
            case .amount: return .blue
            case .profit: return .purple
            case .yield: return .orange
            case .days: return .red
            }
        }
    }
    
    enum SortOrder: String, CaseIterable, Identifiable {
        case ascending = "升序"
        case descending = "降序"

        var id: String { self.rawValue }
    }
    
    private func sortButtonIconName() -> String {
        switch selectedSortKey {
        case .none: return "line.3.horizontal.decrease.circle"
        case .amount: return "dollarsign.circle"
        case .profit: return "chart.line.uptrend.xyaxis"
        case .yield: return "percent"
        case .days: return "calendar"
        }
    }
    
    private func refreshData() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var computedData: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)] = []
            for holding in dataManager.holdings where holding.currentNav > 0 && holding.purchaseAmount > 0 {
                let profit = dataManager.calculateProfit(for: holding)
                let daysHeld = daysBetween(start: holding.purchaseDate, end: Date())
                computedData.append((holding: holding, profit: profit, daysHeld: daysHeld))
            }
            computedData.sort { $0.holding.fundCode < $1.holding.fundCode }
            DispatchQueue.main.async {
                self.precomputedHoldings = computedData
                self.isLoading = false
                self.cachedSortedHoldings.removeAll()
                
                let count = computedData.count
                self.toastMessage = "已加载 \(count) 条记录"
                withAnimation { self.showingToast = true }
            }
        }
    }
    
    private func applyFilters() {
        appliedFundCodeFilter = fundCodeFilterInput
        appliedMinAmount = minAmountInput
        appliedMaxAmount = maxAmountInput
        appliedMinDays = minDaysInput
        appliedMaxDays = maxDaysInput
        appliedMinProfit = varprofitInput
        appliedMaxProfit = maxProfitInput
        hideKeyboard()
        
        let filteredCount = filteredAndSortedHoldings.count
        toastMessage = "已筛选出 \(filteredCount) 条记录"
        withAnimation { showingToast = true }
    }
    
    private func resetFilters() {
        fundCodeFilterInput = ""
        minAmountInput = ""
        maxAmountInput = ""
        minDaysInput = ""
        maxDaysInput = ""
        varprofitInput = ""
        maxProfitInput = ""
        
        appliedFundCodeFilter = ""
        appliedMinAmount = ""
        appliedMaxAmount = ""
        appliedMinDays = ""
        appliedMaxDays = ""
        appliedMinProfit = ""
        appliedMaxProfit = ""
        
        hideKeyboard()
        toastMessage = "筛选条件已重置"
        withAnimation { showingToast = true }
    }
    
    private var zeroProfitIndex: Int? {
        guard selectedSortKey == .yield || selectedSortKey == .profit else {
            return nil
        }
        return filteredAndSortedHoldings.firstIndex(where: { $0.profit.annualized < 0 })
    }

    private var filteredAndSortedHoldings: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)] {
        let cacheKey = "\(appliedFundCodeFilter)_\(appliedMinAmount)_\(appliedMaxAmount)_\(appliedMinDays)_\(appliedMaxDays)_\(appliedMinProfit)_\(appliedMaxProfit)_\(selectedSortKey.rawValue)_\(sortOrder.rawValue)"
        
        if let cached = cachedSortedHoldings[cacheKey] {
            return cached
        }
        
        let minAmount = Double(appliedMinAmount).map { $0 * 10000 }
        let maxAmount = Double(appliedMaxAmount).map { $0 * 10000 }
        let minDays = Int(appliedMinDays)
        let maxDays = Int(appliedMaxDays)
        let minProfit = Double(appliedMinProfit)
        let maxProfit = Double(appliedMaxProfit)

        var results: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)] = []
        
        for item in precomputedHoldings {
            let holding = item.holding
            let profit = item.profit
            let daysHeld = item.daysHeld
            let annualizedProfit = profit.annualized
            let purchaseAmount = holding.purchaseAmount

            if !appliedFundCodeFilter.isEmpty && !holding.fundCode.localizedCaseInsensitiveContains(appliedFundCodeFilter) && !holding.fundName.localizedCaseInsensitiveContains(appliedFundCodeFilter) {
                continue
            }
            if let min = minAmount, purchaseAmount < min { continue }
            if let max = maxAmount, purchaseAmount > max { continue }
            if let min = minDays, daysHeld < min { continue }
            if let max = maxDays, daysHeld > max { continue }
            if let min = minProfit, annualizedProfit < min { continue }
            if let max = maxProfit, annualizedProfit > max { continue }
            results.append((holding: holding, profit: profit, daysHeld: daysHeld))
        }
        
        let sortedResults = sortHoldings(results)
        
        cachedSortedHoldings[cacheKey] = sortedResults
        
        if cachedSortedHoldings.count > 20 {
            let keysToRemove = Array(cachedSortedHoldings.keys.prefix(10))
            for key in keysToRemove {
                cachedSortedHoldings.removeValue(forKey: key)
            }
        }
        
        return sortedResults
    }
    
    private func sortHoldings(_ holdings: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)]) -> [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)] {
        guard selectedSortKey != .none else {
            return holdings.sorted { $0.holding.fundCode < $1.holding.fundCode }
        }
        
        return holdings.sorted { (item1, item2) in
            let value1 = getSortValue(for: item1)
            let value2 = getSortValue(for: item2)
            
            if sortOrder == .ascending {
                return value1 < value2
            } else {
                return value1 > value2
            }
        }
    }
    
    private func getSortValue(for item: (holding: FundHolding, profit: ProfitResult, daysHeld: Int)) -> Double {
        switch selectedSortKey {
        case .amount:
            return item.holding.purchaseAmount
        case .profit:
            return item.profit.absolute
        case .yield:
            return item.profit.annualized
        case .days:
            return Double(item.daysHeld)
        case .none:
            return 0
        }
    }
    
    private func shouldShowDivider(at index: Int) -> Bool {
        guard let zeroIndex = zeroProfitIndex else { return false }
        return index == zeroIndex - 1
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .center) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                    }
                
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width - 4
                    let numberWidth: CGFloat = totalWidth * 0.08
                    let codeNameWidth: CGFloat = totalWidth * 0.22
                    let amountWidth: CGFloat = totalWidth * 0.12
                    let profitWidth: CGFloat = totalWidth * 0.12
                    let daysWidth: CGFloat = totalWidth * 0.10
                    let rateWidth: CGFloat = totalWidth * 0.16
                    let clientWidth: CGFloat = totalWidth * 0.20
                    
                    VStack(alignment: .leading, spacing: 0) {
                        if isFilterExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    FilterFieldView(title: "代码/名称", placeholder: "输入代码或名称", text: $fundCodeFilterInput)
                                    FilterRangeFieldView(
                                        title: "金额(万)",
                                        minPlaceholder: "最低",
                                        maxPlaceholder: "最高",
                                        minText: $minAmountInput,
                                        maxText: $maxAmountInput,
                                        keyboardType: .decimalPad
                                    )
                                }
                                HStack(spacing: 12) {
                                    FilterRangeFieldView(
                                        title: "持有天数",
                                        minPlaceholder: "最低",
                                        maxPlaceholder: "最高",
                                        minText: $minDaysInput,
                                        maxText: $maxDaysInput,
                                        keyboardType: .numberPad
                                    )
                                    FilterRangeFieldView(
                                        title: "收益率(%)",
                                        minPlaceholder: "最低",
                                        maxPlaceholder: "最高",
                                        minText: $varprofitInput,
                                        maxText: $maxProfitInput,
                                        keyboardType: .numbersAndPunctuation
                                    )
                                }
                            }
                            .padding(.vertical, 12)
                            .transition(.opacity.combined(with: .scale))
                        }
                        
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .center, spacing: 0) {
                                Group {
                                    Text("#")
                                        .frame(width: numberWidth, alignment: .center)
                                    Divider().background(Color.secondary)
                                    Text("代码/名称")
                                        .frame(width: codeNameWidth, alignment: .center)
                                    Divider().background(Color.secondary)
                                    Text("金额(万)")
                                        .frame(width: amountWidth, alignment: .center)
                                    Divider().background(Color.secondary)
                                    Text("收益(万)")
                                        .frame(width: profitWidth, alignment: .center)
                                    Divider().background(Color.secondary)
                                    Text("天数")
                                        .frame(width: daysWidth, alignment: .center)
                                    Divider().background(Color.secondary)
                                    Text("收益率(%)")
                                        .frame(width: rateWidth, alignment: .center)
                                    Divider().background(Color.secondary)
                                    Text("客户")
                                        .frame(width: clientWidth, alignment: .leading)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 6)
                            }
                            .background(Color(.systemGray5))
                            .frame(height: 32)

                            if precomputedHoldings.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("当前没有数据")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(filteredAndSortedHoldings.enumerated()), id: \.element.holding.id) { index, item in
                                            HoldingRowView(
                                                index: index,
                                                item: item,
                                                numberWidth: numberWidth,
                                                codeNameWidth: codeNameWidth,
                                                amountWidth: amountWidth,
                                                profitWidth: profitWidth,
                                                daysWidth: daysWidth,
                                                rateWidth: rateWidth,
                                                clientWidth: clientWidth,
                                                isPrivacyModeEnabled: isPrivacyModeEnabled,
                                                showDivider: shouldShowDivider(at: index)
                                            )
                                        }
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isFilterExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isFilterExpanded ? "rectangle.and.text.magnifyingglass" : "magnifyingglass")
                                    .font(.system(size: 16))
                                    .foregroundColor(isFilterExpanded ? .blue : .accentColor)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        Circle()
                                            .fill(isFilterExpanded ? Color.blue.opacity(0.15) : Color.accentColor.opacity(0.15))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(isFilterExpanded ? Color.blue.opacity(0.3) : Color.accentColor.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            
                            HStack(spacing: 6) {
                                Button(action: {
                                    withAnimation {
                                        selectedSortKey = selectedSortKey.next
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: sortButtonIconName())
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(selectedSortKey == .none ? .primary : selectedSortKey.color)
                                        if selectedSortKey != .none {
                                            Text(selectedSortKey.rawValue)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(selectedSortKey.color)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 30)
                                    .background(
                                        Capsule()
                                            .fill(selectedSortKey == .none ? Color.gray.opacity(0.1) : selectedSortKey.color.opacity(0.15))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedSortKey == .none ? Color.gray.opacity(0.3) : selectedSortKey.color.opacity(0.3), lineWidth: 1)
                                    )
                                }

                                if selectedSortKey != .none {
                                    Button(action: {
                                        withAnimation {
                                            sortOrder = (sortOrder == .ascending) ? .descending : .ascending
                                        }
                                    }) {
                                        Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 22, height: 22)
                                            .background(selectedSortKey.color)
                                            .clipShape(Circle())
                                            .shadow(color: selectedSortKey.color.opacity(0.3), radius: 2, x: 0, y: 1)
                                    }
                                }
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isFilterExpanded {
                            HStack(spacing: 10) {
                                Button {
                                    resetFilters()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise.circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(.orange)
                                        .frame(width: 30, height: 30)
                                        .background(
                                            Circle()
                                                .fill(Color.orange.opacity(0.15))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                
                                Button {
                                    applyFilters()
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(.green)
                                        .frame(width: 30, height: 30)
                                        .background(
                                            Circle()
                                                .fill(Color.green.opacity(0.15))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                }
                
                if isLoading {
                    ProgressView("加载中...")
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
                
                if showingToast {
                    ToastView(message: toastMessage, isShowing: $showingToast)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .zIndex(1)
                }
            }
        }
        .onAppear {
            if precomputedHoldings.isEmpty {
                refreshData()
            }
        }
        .onDisappear {
            withAnimation {
                isFilterExpanded = false
            }
        }
        .onChange(of: selectedSortKey) {
            cachedSortedHoldings.removeAll()
        }
        .onChange(of: sortOrder) {
            cachedSortedHoldings.removeAll()
        }
        .refreshable {
            refreshData()
        }
        .background(dataChangeListener)
    }
    
    struct FilterFieldView: View {
        var title: String
        var placeholder: String
        @Binding var text: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField(placeholder, text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 14))
            }
        }
    }

    struct FilterRangeFieldView: View {
        var title: String
        var minPlaceholder: String
        var maxPlaceholder: String
        @Binding var minText: String
        @Binding var maxText: String
        var keyboardType: UIKeyboardType

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField(minPlaceholder, text: $minText)
                        .keyboardType(keyboardType)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 14))
                    Text("-")
                    TextField(maxPlaceholder, text: $maxText)
                        .keyboardType(keyboardType)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 14))
                }
            }
        }
    }
}

struct HoldingRowView: View {
    let index: Int
    let item: (holding: FundHolding, profit: ProfitResult, daysHeld: Int)
    let numberWidth: CGFloat
    let codeNameWidth: CGFloat
    let amountWidth: CGFloat
    let profitWidth: CGFloat
    let daysWidth: CGFloat
    let rateWidth: CGFloat
    let clientWidth: CGFloat
    let isPrivacyModeEnabled: Bool
    let showDivider: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if showDivider {
                Divider()
                    .background(Color.secondary)
                    .frame(height: 2)
            }
            
            HStack(alignment: .center, spacing: 0) {
                Group {
                    Text("\(index + 1).")
                        .frame(width: numberWidth, alignment: .center)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Divider().background(Color.secondary)
                    VStack(alignment: .center, spacing: 2) {
                        Text(item.holding.fundCode)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.tail)
                        Text(item.holding.fundName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.tail)
                    }
                    .frame(width: codeNameWidth, alignment: .center)
                    Divider().background(Color.secondary)
                    Text(formatAmountInTenThousands(item.holding.purchaseAmount))
                        .font(.system(size: 12))
                        .frame(width: amountWidth, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Divider().background(Color.secondary)
                    Text(formatAmountInTenThousands(item.profit.absolute))
                        .font(.system(size: 12))
                        .foregroundColor(item.profit.absolute >= 0 ? .red : .green)
                        .frame(width: profitWidth, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Divider().background(Color.secondary)
                    Text(String(item.daysHeld))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: daysWidth, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Divider().background(Color.secondary)
                    Text(String(format: "%.2f", item.profit.annualized))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(item.profit.annualized >= 0 ? .red : .green)
                        .frame(width: rateWidth, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Divider().background(Color.secondary)
                    Text(isPrivacyModeEnabled ? processClientName(item.holding.clientName) : item.holding.clientName)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .frame(width: clientWidth, alignment: .leading)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private func daysBetween(start: Date, end: Date) -> Int {
    let calendar = Calendar.current
    let startDate = calendar.startOfDay(for: start)
    let endDate = calendar.startOfDay(for: end)
    let components = calendar.dateComponents([.day], from: startDate, to: endDate)
    return components.day ?? 0
}

private func formatAmountInTenThousands(_ amount: Double) -> String {
    let tenThousand = amount / 10000.0
    return String(format: "%.2f", tenThousand)
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
