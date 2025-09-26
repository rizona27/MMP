import SwiftUI
import UIKit

struct HoldingRow: View {
    @EnvironmentObject var dataManager: DataManager
    let holding: FundHolding
    let hideClientInfo: Bool

    @State private var showCopyConfirm = false
    @State private var copiedText = ""

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

    var holdingDays: Int {
        let endDate = holding.navDate
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: holding.purchaseDate), to: calendar.startOfDay(for: endDate))
        return (components.day ?? 0) + 1
    }

    var absoluteReturnPercentage: Double {
        guard holding.purchaseAmount > 0 else { return 0.0 }
        let profit = dataManager.calculateProfit(for: holding)
        return (profit.absolute / holding.purchaseAmount) * 100
    }

    var body: some View {
        let profit = dataManager.calculateProfit(for: holding)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(holding.fundName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                Text("(\(holding.fundCode))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .onLongPressGesture {
                        UIPasteboard.general.string = holding.fundCode
                        copiedText = "基金代码已复制: \(holding.fundCode)"
                        showCopyConfirm = true
                    }

                if holding.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.leading, 4)
                }

                Spacer()
                Text(formattedNavValueAndDate)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if !hideClientInfo {
                HStack {
                    Text("客户: \(holding.clientName)")
                        .font(.subheadline)
                    if !holding.clientID.isEmpty {
                        Text("(\(holding.clientID))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            
            Spacer().frame(height: 8)

            HStack {
                Text("购买金额: \(purchaseAmountFormatted)")
                    .font(.caption)
                Text("份额: \(holding.purchaseShares, specifier: "%.2f")份")
                    .font(.caption)
                Spacer()
            }

            HStack {
                Text("收益: ")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text("\(profit.absolute > 0 ? "+" : "")\(profit.absolute, specifier: "%.2f")元")
                    .font(.subheadline)
                    .foregroundColor(profit.absolute > 0 ? .red : (profit.absolute < 0 ? .green : .primary))
                
                Spacer()
            }
            
            HStack {
                Text("收益率: ")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Group {
                    Text("\(absoluteReturnPercentage, specifier: "%.2f")%")
                        .font(.subheadline)
                        .foregroundColor(absoluteReturnPercentage > 0 ? .red : (absoluteReturnPercentage < 0 ? .green : .primary))
                    + Text("[绝对]")
                        .font(.caption)
                        .foregroundColor(absoluteReturnPercentage > 0 ? .red : (absoluteReturnPercentage < 0 ? .green : .primary))
                    
                    Text(" | ")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(profit.annualized, specifier: "%.2f")%")
                        .font(.subheadline)
                        .foregroundColor(profit.annualized > 0 ? .red : (profit.annualized < 0 ? .green : .primary))
                    + Text("[年化]")
                        .font(.caption)
                        .foregroundColor(profit.annualized > 0 ? .red : (profit.annualized < 0 ? .green : .primary))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Spacer()
            }

            HStack {
                Text("购买日期: ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(Self.dateFormatterYY_MM_DD.string(from: holding.purchaseDate))
                    .font(.caption)
                
                Spacer()
                
                Text("持有天数: ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(holdingDays)天")
                    .font(.caption)
            }
            .padding(.top, 4)

            HStack {
                Button("报告") {
                    UIPasteboard.general.string = reportContent
                    copiedText = "报告已复制到剪贴板"
                    showCopyConfirm = true
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Button(action: {
                    if !holding.clientID.isEmpty {
                        UIPasteboard.general.string = holding.clientID
                        copiedText = "客户号已复制到剪贴板: \(holding.clientID)"
                        showCopyConfirm = true
                    }
                }) {
                    Text("复制客户号")
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(holding.clientID.isEmpty ? .gray : .accentColor)
                .disabled(holding.clientID.isEmpty)
                .padding(.leading, 8)
                
                if !holding.remarks.isEmpty {
                    Text("备注: \(holding.remarks)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 8)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
        .alert(isPresented: $showCopyConfirm) {
            Alert(title: Text(copiedText), dismissButton: .default(Text("好的")))
        }
        .swipeActions(edge: .leading) {
            Button {
                dataManager.togglePinStatus(forHoldingId: holding.id)
            } label: {
                Label(holding.isPinned ? "取消置顶" : "置顶", systemImage: holding.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(holding.isPinned ? .orange : .blue)
        }
    }
    
    private var formattedNavValueAndDate: String {
        let navValue = String(format: "%.4f", holding.currentNav)
        let navDate = Self.dateFormatterMM_DD.string(from: holding.navDate)
        return "\(navValue)(\(navDate))"
    }

    private var purchaseAmountFormatted: String {
        var formattedString: String
        if holding.purchaseAmount >= 10000 && holding.purchaseAmount.truncatingRemainder(dividingBy: 10000) == 0 {
            formattedString = String(format: "%.0f", holding.purchaseAmount / 10000.0) + "万"
        } else if holding.purchaseAmount >= 10000 {
            formattedString = String(format: "%.2f", holding.purchaseAmount / 10000.0) + "万"
        } else {
            formattedString = String(format: "%.2f", holding.purchaseAmount) + "元"
        }
        return formattedString
    }

    private var reportContent: String {
        let profit = dataManager.calculateProfit(for: holding)
        let purchaseAmountFormatted = self.purchaseAmountFormatted
        let formattedCurrentNav = String(format: "%.4f", holding.currentNav)
        let formattedAbsoluteProfit = String(format: "%.2f", profit.absolute)
        let formattedAnnualizedProfit = String(format: "%.2f", profit.annualized)
        let formattedAbsoluteReturnPercentage = String(format: "%.2f", self.absoluteReturnPercentage)

        let navDateString = Self.dateFormatterMM_DD.string(from: holding.navDate)

        return """
        \(holding.fundName) | \(holding.fundCode)
        ├ 购买日期:\(HoldingRow.dateFormatterYY_MM_DD.string(from: holding.purchaseDate))
        ├ 持有天数:\(holdingDays)天
        ├ 购买金额:\(purchaseAmountFormatted)
        ├ 最新净值:\(formattedCurrentNav) | \(navDateString)
        ├ 收益:\(profit.absolute > 0 ? "+" : "")\(formattedAbsoluteProfit)
        ├ 收益率:\(formattedAnnualizedProfit)%(年化)
        └ 收益率:\(formattedAbsoluteReturnPercentage)%(绝对)
        """
    }
}

extension Double {
    func formattedWithSign() -> String {
        if self > 0 {
            return "+\(self)"
        } else {
            return "\(self)"
        }
    }
}
