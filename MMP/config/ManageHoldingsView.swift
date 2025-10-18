import SwiftUI

struct ClientGroupForManagement: Identifiable {
    let id: String
    let clientName: String
    var holdings: [FundHolding]
}

struct ManageHoldingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss
    
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedHolding: FundHolding? = nil
    @State private var isShowingRenameAlert: Bool = false
    @State private var clientToRename: ClientGroupForManagement? = nil
    @State private var newClientName: String = ""
    @State private var isShowingDeleteAlert: Bool = false
    @State private var clientToDelete: ClientGroupForManagement? = nil
    @State private var expandedClient: String? = nil

    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled: Bool = false

    private var groupedHoldings: [ClientGroupForManagement] {
        let groupedDictionary = Dictionary(grouping: dataManager.holdings) { holding in
            holding.clientName
        }

        var clientGroups: [ClientGroupForManagement] = groupedDictionary.map { (clientName, holdings) in
            return ClientGroupForManagement(id: clientName, clientName: clientName, holdings: holdings)
        }

        clientGroups.sort { $0.clientName < $1.clientName }
        
        return clientGroups
    }

    var sectionedClientGroups: [Character: [ClientGroupForManagement]] {
        var sections: [Character: [ClientGroupForManagement]] = [:]
        
        let allGroups = groupedHoldings
        for group in allGroups {
            let firstChar = group.clientName.first?.uppercased().first ?? "#"
            sections[firstChar, default: []].append(group)
        }
        return sections
    }

    var sortedSectionKeys: [Character] {
        sectionedClientGroups.keys.sorted { (char1, char2) -> Bool in
            if char1 == "#" { return false }
            if char2 == "#" { return true }
            return String(char1).localizedStandardCompare(String(char2)) == .orderedAscending
        }
    }

    var body: some View {
        NavigationView {
            contentView
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                }
        }
        .navigationViewStyle(.stack) 
        .sheet(item: $selectedHolding) { holdingToEdit in
            EditHoldingView(holding: holdingToEdit) { updatedHolding in
                dataManager.updateHolding(updatedHolding)
                Task { @MainActor in
                    let fetchedInfo = await fundService.fetchFundInfo(code: updatedHolding.fundCode)
                    var refreshedHolding = updatedHolding
                    refreshedHolding.fundName = fetchedInfo.fundName
                    refreshedHolding.currentNav = fetchedInfo.currentNav
                    refreshedHolding.navDate = fetchedInfo.navDate
                    refreshedHolding.isValid = fetchedInfo.isValid
                    dataManager.updateHolding(refreshedHolding)
                }
            }
            .environmentObject(dataManager)
            .environmentObject(fundService)
        }
        .alert("修改客户姓名", isPresented: $isShowingRenameAlert) {
            TextField("新客户姓名", text: $newClientName)
            Button("确定", action: renameClient)
            Button("取消", role: .cancel) {
                newClientName = ""
                clientToRename = nil
            }
        } message: {
            if let client = clientToRename {
                Text("将客户 \"\(client.clientName)\" 下的所有持仓姓名修改为:")
            } else {
                Text("无法找到要修改的客户。")
            }
        }
        .alert("删除客户持仓", isPresented: $isShowingDeleteAlert) {
            Button("确定删除", role: .destructive, action: confirmDeleteClientHoldings)
            Button("取消", role: .cancel) {
                clientToDelete = nil
            }
        } message: {
            if let client = clientToDelete {
                Text("您确定要删除客户 \"\(client.clientName)\" 名下的所有基金持仓吗？此操作无法撤销。")
            } else {
                Text("无法找到要删除的客户。")
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if groupedHoldings.isEmpty {
            VStack {
                Spacer()
                Text("当前没有持仓数据。")
                    .foregroundColor(.gray)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(sortedSectionKeys, id: \.self) { sectionKey in
                    Section(header: EmptyView()) {
                        let clientsForSection = sectionedClientGroups[sectionKey]?.sorted(by: { $0.clientName < $1.clientName }) ?? []
                        ForEach(clientsForSection) { clientGroup in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedClient == clientGroup.id },
                                    set: { isExpanded in
                                        withAnimation {
                                            if isExpanded {
                                                expandedClient = clientGroup.id
                                            } else {
                                                expandedClient = nil
                                            }
                                        }
                                    }
                                )
                            ) {
                                ForEach(clientGroup.holdings) { holding in
                                    HoldingRowForManagement(holding: holding) {
                                        selectedHolding = holding
                                    }
                                }
                                .onDelete { indexSet in
                                    deleteHoldings(in: clientGroup, at: indexSet)
                                }
                            } label: {
                                headerView(for: clientGroup)
                            }
                            .id(clientGroup.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
    
    private func refreshAllFundInfo() async {
        let uniqueFundCodes = Set(dataManager.holdings.map { $0.fundCode })
        
        for code in uniqueFundCodes {
            let fetchedInfo = await fundService.fetchFundInfo(code: code)
            dataManager.holdings = dataManager.holdings.map { holding in
                var updatedHolding = holding
                if holding.fundCode == code {
                    updatedHolding.fundName = fetchedInfo.fundName
                    updatedHolding.currentNav = fetchedInfo.currentNav
                    updatedHolding.navDate = fetchedInfo.navDate
                    updatedHolding.isValid = fetchedInfo.isValid
                }
                return updatedHolding
            }
        }
        dataManager.saveData()
        fundService.addLog("ManageHoldingsView: 所有基金信息已刷新。", type: .info)
    }

    private func renameClient() {
        guard let oldClientName = clientToRename?.clientName, !newClientName.isEmpty else { return }
        
        if oldClientName == newClientName { return }
        
        dataManager.holdings = dataManager.holdings.map { holding in
            var updatedHolding = holding
            if holding.clientName == oldClientName {
                updatedHolding.clientName = newClientName
            }
            return updatedHolding
        }
        
        dataManager.saveData()
        fundService.addLog("ManageHoldingsView: 客户 '\(oldClientName)' 已批量修改为 '\(newClientName)'。", type: .info)
        
        newClientName = ""
        clientToRename = nil
    }

    private func confirmDeleteClientHoldings() {
        guard let client = clientToDelete else { return }
        
        let holdingsToDeleteCount = dataManager.holdings.filter { $0.clientName == client.clientName }.count
        dataManager.holdings.removeAll { $0.clientName == client.clientName }
        
        dataManager.saveData()
        fundService.addLog("ManageHoldingsView: 已批量删除客户 '\(client.clientName)' 名下的 \(holdingsToDeleteCount) 个持仓。", type: .info)
        
        clientToDelete = nil
        isShowingDeleteAlert = false
    }

    private func deleteHoldings(in clientGroup: ClientGroupForManagement, at offsets: IndexSet) {
        let holdingsToDeleteIDs = offsets.map { clientGroup.holdings[$0].id }
        
        dataManager.holdings.removeAll { holding in
            holdingsToDeleteIDs.contains(holding.id)
        }
        dataManager.saveData()
        fundService.addLog("ManageHoldingsView: 从客户 \(clientGroup.clientName) 下删除了 \(holdingsToDeleteIDs.count) 个持仓。", type: .info)
    }

    private func headerView(for clientGroup: ClientGroupForManagement) -> some View {
        let baseColor = clientGroup.clientName.morandiColor()
        let isExpanded = expandedClient == clientGroup.id
        let displayClientName = isPrivacyModeEnabled ? processClientName(clientGroup.clientName) : clientGroup.clientName
        
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isExpanded {
                            expandedClient = nil
                        } else {
                            expandedClient = clientGroup.id
                        }
                    }
                }) {
                    HStack(alignment: .center, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("**\(displayClientName)**")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        
                        Spacer()
                        
                        Button("批量改名") {
                            clientToRename = clientGroup
                            newClientName = clientGroup.clientName
                            isShowingRenameAlert = true
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.blue)
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                        
                        Button("批量删除") {
                            clientToDelete = clientGroup
                            isShowingDeleteAlert = true
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(colorScheme == .dark ? Color.red.opacity(0.8) : Color.red)
                        .buttonStyle(.plain)
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
        }
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
}

struct HoldingRowForManagement: View {
    let holding: FundHolding
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(holding.fundName) (\(holding.fundCode))")
                    .font(.headline)
                Text("购买金额: \(holding.purchaseAmount, specifier: "%.2f")元")
                    .font(.caption)
                Text("购买份额: \(holding.purchaseShares, specifier: "%.2f")份")
                    .font(.caption)
                Text("购买日期: \(holding.purchaseDate, formatter: DateFormatter.shortDate)")
                    .font(.caption)
                if !holding.remarks.isEmpty {
                    Text("备注: \(holding.remarks)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 16)
            Spacer()
            Button(action: onEdit) {
                Text("编辑")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
}
