import SwiftUI

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

    // 筛选条件的状态变量
    @State private var fundCodeFilter: String = ""
    @State private var minAmountInput: String = ""
    @State private var maxAmountInput: String = ""
    @State private var minDaysInput: String = ""
    @State private var maxDaysInput: String = ""
    @State private var minProfitInput: String = ""
    @State private var maxProfitInput: String = ""

    private var zeroProfitIndex: Int? {
        filteredAndSortedHoldings.firstIndex(where: { $0.profit.annualized < 0 })
    }

    private var filteredAndSortedHoldings: [(holding: FundHolding, profit: ProfitResult)] {
        let minAmount = Double(minAmountInput).map { $0 * 10000 }
        let maxAmount = Double(maxAmountInput).map { $0 * 10000 }
        let minDays = Int(minDaysInput)
        let maxDays = Int(maxDaysInput)
        let minProfit = Double(minProfitInput)
        let maxProfit = Double(maxProfitInput)

        var results: [(holding: FundHolding, profit: ProfitResult)] = []
        for holding in dataManager.holdings where holding.currentNav > 0 && holding.purchaseAmount > 0 {
            let profit = dataManager.calculateProfit(for: holding)
            let item = (holding: holding, profit: profit)
            let annualizedProfit = item.profit.annualized
            let purchaseAmount = item.holding.purchaseAmount
            let daysHeld = daysBetween(start: item.holding.purchaseDate, end: Date())

            if !fundCodeFilter.isEmpty && !item.holding.fundCode.localizedCaseInsensitiveContains(fundCodeFilter) && !item.holding.fundName.localizedCaseInsensitiveContains(fundCodeFilter) {
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
            results.append(item)
        }
        return results.sorted { $0.profit.annualized > $1.profit.annualized }
    }

    var body: some View {
        NavigationView {
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
                    // 筛选条件输入区域 - 重新排版
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            FilterFieldView(title: "代码/名称", placeholder: "输入代码或名称", text: $fundCodeFilter)
                            FilterRangeFieldView(title: "金额(万)", minPlaceholder: "最低", maxPlaceholder: "最高", minText: $minAmountInput, maxText: $maxAmountInput, keyboardType: .decimalPad)
                        }
                        HStack(spacing: 12) {
                            FilterRangeFieldView(title: "持有天数", minPlaceholder: "最低", maxPlaceholder: "最高", minText: $minDaysInput, maxText: $maxDaysInput, keyboardType: .numberPad)
                            // 修改收益率筛选的键盘类型为 numbersAndPunctuation，支持输入负号
                            FilterRangeFieldView(title: "收益率(%)", minPlaceholder: "最低", maxPlaceholder: "最高", minText: $minProfitInput, maxText: $maxProfitInput, keyboardType: .numbersAndPunctuation)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color(.systemGray6))

                    // 列表头 - 优化高度
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
                    .frame(height: 32) // 固定表头高度
                    
                    // 排名列表主体
                    List {
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
                                        Text(item.holding.fundName)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
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
                                    // 客户 - 修改截断逻辑为4个汉字
                                    Text(item.holding.clientName)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: clientWidth, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 6)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                .onTapGesture {
                    self.hideKeyboard()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                }
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
