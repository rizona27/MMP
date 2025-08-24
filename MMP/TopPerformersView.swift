import SwiftUI
import Foundation

// MARK: - 通用辅助视图和函数
// 添加一个辅助函数来计算持仓天数
func daysBetween(start: Date, end: Date) -> Int {
    let calendar = Calendar.current
    let startDate = calendar.startOfDay(for: start)
    let endDate = calendar.startOfDay(for: end)
    let components = calendar.dateComponents([.day], from: startDate, to: endDate)
    return components.day ?? 0
}

// 辅助函数：将金额格式化为"XX.XX"万
func formatAmountInTenThousands(_ amount: Double) -> String {
    let tenThousand = amount / 10000.0
    return String(format: "%.2f", tenThousand)
}

// 辅助函数：用于点击空白处收起键盘
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

    // 筛选条件的用户输入状态变量
    @State private var fundCodeFilterInput: String = ""
    @State private var minAmountInput: String = ""
    @State private var maxAmountInput: String = ""
    @State private var minDaysInput: String = ""
    @State private var maxDaysInput: String = ""
    @State private var varprofitInput: String = ""
    @State private var maxProfitInput: String = ""

    // 实际用于筛选的条件变量
    @State private var appliedFundCodeFilter: String = ""
    @State private var appliedMinAmount: String = ""
    @State private var appliedMaxAmount: String = ""
    @State private var appliedMinDays: String = ""
    @State private var appliedMaxDays: String = ""
    @State private var appliedMinProfit: String = ""
    @State private var appliedMaxProfit: String = ""
    
    // 新增：用于控制提示消息的显示和内容
    @State private var showingToast = false
    @State private var toastMessage: String = ""
    
    // 新增：计算缓存
    @State private var profitCalculationCache: [String: ProfitResult] = [:]
    @State private var daysHeldCache: [String: Int] = [:]
    
    // 新增：加载状态
    @State private var isLoading = false
    
    // 筛选按钮点击后执行筛选
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
        withAnimation {
            showingToast = true
        }
    }
    
    // 🌟 新增：重置筛选条件的方法
    private func resetFilters() {
        fundCodeFilterInput = ""
        minAmountInput = ""
        maxAmountInput = ""
        minDaysInput = ""
        maxDaysInput = ""
        varprofitInput = ""
        maxProfitInput = ""
        
        // 同时重置已应用的筛选条件，触发列表刷新
        appliedFundCodeFilter = ""
        appliedMinAmount = ""
        appliedMaxAmount = ""
        appliedMinDays = ""
        appliedMaxDays = ""
        appliedMinProfit = ""
        appliedMaxProfit = ""
        
        hideKeyboard()
        toastMessage = "筛选条件已重置"
        withAnimation {
            showingToast = true
        }
    }
    
    // 计算缓存键
    private func cacheKey(for holding: FundHolding) -> String {
        return "\(holding.fundCode)_\(holding.purchaseDate.timeIntervalSince1970)_\(holding.purchaseAmount)"
    }

    private var zeroProfitIndex: Int? {
        filteredAndSortedHoldings.firstIndex(where: { $0.profit.annualized < 0 })
    }

    private var filteredAndSortedHoldings: [(holding: FundHolding, profit: ProfitResult)] {
        let minAmount = Double(appliedMinAmount).map { $0 * 10000 }
        let maxAmount = Double(appliedMaxAmount).map { $0 * 10000 }
        let minDays = Int(appliedMinDays)
        let maxDays = Int(appliedMaxDays)
        let minProfit = Double(appliedMinProfit)
        let maxProfit = Double(appliedMaxProfit)

        var results: [(holding: FundHolding, profit: ProfitResult)] = []
        
        // 使用缓存优化计算
        for holding in dataManager.holdings where holding.currentNav > 0 && holding.purchaseAmount > 0 {
            let cacheKey = self.cacheKey(for: holding)
            
            // 从缓存获取或计算收益
            let profit: ProfitResult
            if let cachedProfit = profitCalculationCache[cacheKey] {
                profit = cachedProfit
            } else {
                profit = dataManager.calculateProfit(for: holding)
                profitCalculationCache[cacheKey] = profit
            }
            
            // 从缓存获取或计算持有天数
            let daysHeld: Int
            if let cachedDays = daysHeldCache[cacheKey] {
                daysHeld = cachedDays
            } else {
                daysHeld = daysBetween(start: holding.purchaseDate, end: Date())
                daysHeldCache[cacheKey] = daysHeld
            }
            
            let annualizedProfit = profit.annualized
            let purchaseAmount = holding.purchaseAmount

            if !appliedFundCodeFilter.isEmpty && !holding.fundCode.localizedCaseInsensitiveContains(appliedFundCodeFilter) && !holding.fundName.localizedCaseInsensitiveContains(appliedFundCodeFilter) {
                continue
            }
            if let min = minAmount, purchaseAmount < min {
                continue
            }
            if let max = maxAmount, purchaseAmount > max {
                continue
            }
            if let min = minDays, daysHeld < min {
                continue
            }
            if let max = maxDays, daysHeld > max {
                continue
            }
            if let min = minProfit, annualizedProfit < min {
                continue
            }
            if let max = maxProfit, annualizedProfit > max {
                continue
            }
            results.append((holding: holding, profit: profit))
        }
        return results.sorted { $0.profit.annualized > $1.profit.annualized }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    // 优化后的宽度比例，确保总和为 1.0
                    let numberWidth: CGFloat = totalWidth * 0.08
                    let codeNameWidth: CGFloat = totalWidth * 0.20
                    let amountWidth: CGFloat = totalWidth * 0.13
                    let profitWidth: CGFloat = totalWidth * 0.13
                    let daysWidth: CGFloat = totalWidth * 0.11
                    let rateWidth: CGFloat = totalWidth * 0.17
                    let clientWidth: CGFloat = totalWidth * 0.18 // 增大客户列宽度
                    
                    VStack(spacing: 0) {
                        // 筛选条件输入区域
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                FilterFieldView(title: "代码/名称", placeholder: "输入代码或名称", text: $fundCodeFilterInput)
                                FilterRangeFieldView(title: "金额(万)", minPlaceholder: "最低", maxPlaceholder: "最高", minText: $minAmountInput, maxText: $maxAmountInput, keyboardType: .decimalPad)
                            }
                            HStack(spacing: 12) {
                                FilterRangeFieldView(title: "持有天数", minPlaceholder: "最低", maxPlaceholder: "最高", minText: $minDaysInput, maxText: $maxDaysInput, keyboardType: .numberPad)
                                FilterRangeFieldView(title: "收益率(%)", minPlaceholder: "最低", maxPlaceholder: "最高", minText: $varprofitInput, maxText: $maxProfitInput, keyboardType: .numbersAndPunctuation)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(.systemGray6))

                        // 列表头
                        HStack(alignment: .center, spacing: 0) {
                            Group {
                                Text("#")
                                    .frame(width: numberWidth, alignment: .leading)
                                Divider().background(Color.secondary)
                                Text("代码/名称")
                                    .frame(width: codeNameWidth, alignment: .leading)
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
                        
                        // 使用ScrollView + LazyVStack替代List提高性能
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredAndSortedHoldings.indices, id: \.self) { index in
                                    let item = filteredAndSortedHoldings[index]
                                    
                                    if index == zeroProfitIndex {
                                        Divider()
                                            .background(Color.secondary)
                                            .frame(height: 2)
                                            .padding(.horizontal)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 0) {
                                        Group {
                                            // 序号
                                            Text("\(index + 1).")
                                                .frame(width: numberWidth, alignment: .leading)
                                                .font(.system(size: 12, weight: .bold))
                                            Divider().background(Color.secondary)
                                            // 代码/名称
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.holding.fundCode)
                                                    .font(.system(size: 12, weight: .bold))
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                                Text(item.holding.fundName)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                            .frame(width: codeNameWidth, alignment: .leading)
                                            Divider().background(Color.secondary)
                                            // 金额(万)
                                            Text(formatAmountInTenThousands(item.holding.purchaseAmount))
                                                .font(.system(size: 12))
                                                .frame(width: amountWidth, alignment: .center)
                                            Divider().background(Color.secondary)
                                            // 收益(万)
                                            Text(formatAmountInTenThousands(item.profit.absolute))
                                                .font(.system(size: 12))
                                                .foregroundColor(item.profit.absolute >= 0 ? .red : .green)
                                                .frame(width: profitWidth, alignment: .center)
                                            Divider().background(Color.secondary)
                                            // 天数
                                            Text(String(daysBetween(start: item.holding.purchaseDate, end: Date())))
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .frame(width: daysWidth, alignment: .center)
                                            Divider().background(Color.secondary)
                                            // 收益率(%)
                                            Text(String(format: "%.2f", item.profit.annualized))
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(item.profit.annualized >= 0 ? .red : .green)
                                                .frame(width: rateWidth, alignment: .center)
                                            Divider().background(Color.secondary)
                                            // 客户
                                            Text(item.holding.clientName)
                                                .font(.system(size: 11))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                                .frame(width: clientWidth, alignment: .leading)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        self.hideKeyboard()
                    }
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
                
                // 加载指示器
                if isLoading {
                    ProgressView("加载中...")
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
                
                // 使用项目中已存在的 ToastView
                ToastView(message: toastMessage, isShowing: $showingToast)
                    .padding(.bottom, 80)
            }
        }
        .onAppear {
            // 预计算数据
            isLoading = true
            DispatchQueue.global(qos: .userInitiated).async {
                // 预填充缓存
                _ = self.filteredAndSortedHoldings
                
                DispatchQueue.main.async {
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
