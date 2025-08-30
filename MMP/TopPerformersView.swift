import SwiftUI
import Foundation

// MARK: - 通用辅助视图和函数
func daysBetween(start: Date, end: Date) -> Int {
    let calendar = Calendar.current
    let startDate = calendar.startOfDay(for: start)
    let endDate = calendar.startOfDay(for: end)
    let components = calendar.dateComponents([.day], from: startDate, to: endDate)
    return components.day ?? 0
}

func formatAmountInTenThousands(_ amount: Double) -> String {
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

// MARK: - 主视图

struct TopPerformersView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

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
    
    // MARK: - 隐私模式变量
    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled: Bool = false
    
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
        filteredAndSortedHoldings.firstIndex(where: { $0.profit.annualized < 0 })
    }

    private var filteredAndSortedHoldings: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)] {
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
        return results.sorted { $0.profit.annualized > $1.profit.annualized }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
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

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(filteredAndSortedHoldings.indices, id: \.self) { index in
                                        let item = filteredAndSortedHoldings[index]
                                        
                                        if index == zeroProfitIndex {
                                            Divider().background(Color.secondary).frame(height: 2)
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
                                                        .lineLimit(1).minimumScaleFactor(0.8).truncationMode(.tail)
                                                    Text(item.holding.fundName)
                                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                                        .lineLimit(1).minimumScaleFactor(0.8).truncationMode(.tail)
                                                }
                                                .frame(width: codeNameWidth, alignment: .center)
                                                Divider().background(Color.secondary)
                                                Text(formatAmountInTenThousands(item.holding.purchaseAmount))
                                                    .font(.system(size: 12)).frame(width: amountWidth, alignment: .center)
                                                    .lineLimit(1).minimumScaleFactor(0.8)
                                                Divider().background(Color.secondary)
                                                Text(formatAmountInTenThousands(item.profit.absolute))
                                                    .font(.system(size: 12)).foregroundColor(item.profit.absolute >= 0 ? .red : .green)
                                                    .frame(width: profitWidth, alignment: .center)
                                                    .lineLimit(1).minimumScaleFactor(0.8)
                                                Divider().background(Color.secondary)
                                                Text(String(item.daysHeld))
                                                    .font(.system(size: 12)).foregroundColor(.secondary)
                                                    .frame(width: daysWidth, alignment: .center)
                                                    .lineLimit(1).minimumScaleFactor(0.8)
                                                Divider().background(Color.secondary)
                                                Text(String(format: "%.2f", item.profit.annualized))
                                                    .font(.system(size: 12, weight: .bold)).foregroundColor(item.profit.annualized >= 0 ? .red : .green)
                                                    .frame(width: rateWidth, alignment: .center)
                                                    .lineLimit(1).minimumScaleFactor(0.8)
                                                Divider().background(Color.secondary)
                                                Text(isPrivacyModeEnabled ? processClientName(item.holding.clientName) : item.holding.clientName)
                                                    .font(.system(size: 11)).lineLimit(2).minimumScaleFactor(0.8).truncationMode(.tail)
                                                    .frame(width: clientWidth, alignment: .leading)
                                            }
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onTapGesture {
                    self.hideKeyboard()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            resetFilters()
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            applyFilters()
                        } label: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                }
                
                if isLoading {
                    ProgressView("加载中...")
                        .padding().background(Color.white.opacity(0.8)).cornerRadius(10).shadow(radius: 10)
                }
                
                ToastView(message: toastMessage, isShowing: $showingToast).padding(.bottom, 80)
            }
        }
        .onAppear {
            isLoading = true
            DispatchQueue.global(qos: .userInitiated).async {
                var computedData: [(holding: FundHolding, profit: ProfitResult, daysHeld: Int)] = []
                for holding in dataManager.holdings where holding.currentNav > 0 && holding.purchaseAmount > 0 {
                    let profit = dataManager.calculateProfit(for: holding)
                    let daysHeld = daysBetween(start: holding.purchaseDate, end: Date())
                    computedData.append((holding: holding, profit: profit, daysHeld: daysHeld))
                }
                computedData.sort { $0.profit.annualized > $1.profit.annualized }
                DispatchQueue.main.async {
                    self.precomputedHoldings = computedData
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - 筛选器视图
    struct FilterFieldView: View {
        var title: String
        var placeholder: String
        @Binding var text: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12)).foregroundColor(.secondary)
                TextField(placeholder, text: $text).textFieldStyle(RoundedBorderTextFieldStyle()).font(.system(size: 14))
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
                Text(title).font(.system(size: 12)).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField(minPlaceholder, text: $minText)
                        .keyboardType(keyboardType).textFieldStyle(RoundedBorderTextFieldStyle()).font(.system(size: 14))
                    Text("-")
                    TextField(maxPlaceholder, text: $maxText)
                        .keyboardType(keyboardType).textFieldStyle(RoundedBorderTextFieldStyle()).font(.system(size: 14))
                }
            }
        }
    }
}
