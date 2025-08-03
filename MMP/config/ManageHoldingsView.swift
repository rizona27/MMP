import SwiftUI

// MARK: - 新增：用于表示客户分组的数据结构，便于UI使用
struct ClientGroupForManagement: Identifiable {
    let id: String // 客户姓名作为唯一标识符
    let clientName: String
    var holdings: [FundHolding] // 该客户名下的所有持仓
}

struct ManageHoldingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss
    
    // 用于编辑单个持仓
    @State private var selectedHolding: FundHolding? = nil
    
    // 用于批量修改客户姓名
    @State private var isShowingRenameAlert: Bool = false
    @State private var clientToRename: ClientGroupForManagement? = nil
    @State private var newClientName: String = ""
    
    // 新增: 用于批量删除客户持仓
    @State private var isShowingDeleteAlert: Bool = false
    @State private var clientToDelete: ClientGroupForManagement? = nil
    
    // 更改：用于搜索，与 ClientView 保持一致
    @State private var searchText = ""
    // 新增：用于搜索结果的懒加载
    @State private var loadedSearchResultCount: Int = 10
    
    // 关键修复：用于跟踪哪些客户分组是展开的
    @State private var expandedClients: Set<String> = []

    // 新增: 用于控制快速定位栏的透明度
    @State private var quickNavBarVisibleOpacity: Double = 0.5
    // 用于控制透明度重置任务
    @State private var opacityResetTask: Task<Void, Never>? = nil
    
    // 从 AppStorage 读取快速定位栏的开关状态
    @AppStorage("isQuickNavBarEnabled") private var isQuickNavBarEnabled: Bool = true
    
    // 计算属性：按客户姓名分组后的数据，不进行搜索过滤
    private var groupedHoldings: [ClientGroupForManagement] {
        let groupedDictionary = Dictionary(grouping: dataManager.holdings) { holding in
            holding.clientName
        }
        
        // 将字典转换为 ClientGroupForManagement 数组
        var clientGroups: [ClientGroupForManagement] = groupedDictionary.map { (clientName, holdings) in
            return ClientGroupForManagement(id: clientName, clientName: clientName, holdings: holdings)
        }
        
        // 按客户名称排序
        clientGroups.sort { $0.clientName < $1.clientName }
        
        return clientGroups
    }

    // 计算属性：用于按首字母分组，以支持快速定位条
    var sectionedClientGroups: [Character: [ClientGroupForManagement]] {
        var sections: [Character: [ClientGroupForManagement]] = [:]
        
        let allGroups = groupedHoldings // 注意这里使用未过滤的 groupedHoldings
        for group in allGroups {
            let firstChar = group.clientName.first?.uppercased().first ?? "#"
            sections[firstChar, default: []].append(group)
        }
        return sections
    }

    // 计算属性：用于快速定位条的标题
    var sortedSectionKeys: [Character] {
        sectionedClientGroups.keys.sorted { (char1, char2) -> Bool in
            // 特殊处理，让 '#' 排在最后
            if char1 == "#" { return false }
            if char2 == "#" { return true }
            return String(char1).localizedStandardCompare(String(char2)) == .orderedAscending // 确保按拼音排序
        }
    }
    
    // MARK: - 搜索结果列表视图
    private func searchResultsListView() -> some View {
        List {
            // 筛选出符合搜索条件的单个基金
            let searchResults = dataManager.holdings.filter {
                $0.clientName.localizedCaseInsensitiveContains(searchText) ||
                $0.fundCode.localizedCaseInsensitiveContains(searchText) ||
                $0.fundName.localizedCaseInsensitiveContains(searchText) ||
                $0.clientID.localizedCaseInsensitiveContains(searchText) ||
                $0.remarks.localizedCaseInsensitiveContains(searchText)
            }
            
            if searchResults.isEmpty {
                Text("没有找到符合条件的基金。")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(searchResults.prefix(loadedSearchResultCount)) { holding in
                    HoldingRowForManagement(holding: holding) {
                        selectedHolding = holding
                    }
                    .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation {
                                // 直接从 dataManager.holdings 中移除
                                dataManager.holdings.removeAll { $0.id == holding.id }
                                dataManager.saveData() // 保存数据
                            }
                        } label: {
                            Image(systemName: "trash.fill")
                        }
                        .tint(.red)
                        
                        Button {
                            selectedHolding = holding
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .tint(.blue)
                    }
                    .onAppear {
                        if holding.id == searchResults.prefix(loadedSearchResultCount).last?.id && loadedSearchResultCount < searchResults.count {
                            loadedSearchResultCount += 10
                            fundService.addLog("ManageHoldingsView: 加载更多搜索结果。当前数量: \(loadedSearchResultCount)")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .padding(.horizontal, -16) // 移除水平内边距以使列表内容靠边
    }
    
    // MARK: - 主视图内容
    var body: some View {
        // 使用 NavigationStack 来管理导航
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏和折叠/展开按钮
                HStack {
                    SearchBar(text: $searchText, placeholder: "搜索客户、基金代码、基金名称...")
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.75) // 搜索栏缩短到3/4
                        .padding(.vertical, 8)
                        .padding(.leading) // 左侧内边距

                    // 折叠/展开图标按钮 (与 ClientView 相同)
                    Button(action: {
                        withAnimation {
                            // 如果有任何一个分栏是展开的，则执行“折叠所有”操作
                            if !expandedClients.isEmpty {
                                expandedClients.removeAll()
                            } else {
                                // 如果所有分栏都已折叠，则执行“展开所有”操作
                                let allClientIdsToExpand = Set(groupedHoldings.map { $0.id })
                                expandedClients = allClientIdsToExpand
                            }
                        }
                    }) {
                        // 按钮图标根据是否有展开的分栏来决定
                        Image(systemName: expandedClients.isEmpty ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.trailing) // 右侧内边距
                }
                .padding(.bottom, 5) // 在按钮下方增加一点间距

                // 核心逻辑：根据搜索文本显示不同的列表
                if !searchText.isEmpty {
                    searchResultsListView() // 显示单个基金的搜索结果列表
                } else {
                    // 原有的按客户分组的列表视图
                    if groupedHoldings.isEmpty {
                        VStack {
                            Spacer()
                            Text("当前没有持仓数据。")
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ZStack(alignment: .leading) {
                                List {
                                    ForEach(sortedSectionKeys, id: \.self) { sectionKey in
                                        Section(header: EmptyView()) {
                                            let clientsForSection = sectionedClientGroups[sectionKey]?.sorted(by: { $0.clientName < $1.clientName }) ?? []
                                            ForEach(clientsForSection) { clientGroup in
                                                // 关键修复：这里的 isExpanded 绑定了 expandedClients，并使用了 Toggle 逻辑
                                                DisclosureGroup(
                                                    isExpanded: Binding(
                                                        get: { expandedClients.contains(clientGroup.id) },
                                                        set: { isExpanded in
                                                            withAnimation {
                                                                if isExpanded {
                                                                    expandedClients.insert(clientGroup.id)
                                                                } else {
                                                                    expandedClients.remove(clientGroup.id)
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
                                                    headerView(for: clientGroup) // 调用 headerView
                                                }
                                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                                .listRowSeparator(.hidden)
                                            }
                                        }
                                        .id(sectionKey)
                                    }
                                }
                                .listStyle(.plain)
                                .padding(.leading, isQuickNavBarEnabled ? 40 : 16)
                                .refreshable {
                                    await refreshAllFundInfo()
                                }
                                
                                if isQuickNavBarEnabled && !sortedSectionKeys.isEmpty && searchText.isEmpty {
                                    VStack(spacing: 2) {
                                        ForEach(sortedSectionKeys, id: \.self) { titleChar in
                                            Button(action: {
                                                withAnimation {
                                                    proxy.scrollTo(titleChar, anchor: .top)
                                                    
                                                    // 修复：快速定位条现在只会滚动并展开/折叠目标组，不会影响其他组
                                                    guard let firstClientInGroup = sectionedClientGroups[titleChar]?.sorted(by: { $0.clientName < $1.clientName }).first else { return }
                                                    
                                                    if expandedClients.contains(firstClientInGroup.id) {
                                                        expandedClients.remove(firstClientInGroup.id)
                                                    } else {
                                                        expandedClients.insert(firstClientInGroup.id)
                                                    }
                                                    
                                                    opacityResetTask?.cancel()
                                                    quickNavBarVisibleOpacity = 1.0
                                                    opacityResetTask = Task {
                                                        do {
                                                            try await Task.sleep(nanoseconds: 1_500_000_000)
                                                            withAnimation(.easeOut(duration: 0.5)) {
                                                                quickNavBarVisibleOpacity = 0.5
                                                            }
                                                        } catch {}
                                                    }
                                                }
                                            }) {
                                                Text(String(titleChar))
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                    .frame(width: 24, height: 24)
                                                    .background(Color.gray.opacity(0.2))
                                                    .cornerRadius(8)
                                                    .foregroundColor(.primary.opacity(quickNavBarVisibleOpacity))
                                            }
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 2)
                                    .background(Color.clear)
                                    .offset(x: 0)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("管理持仓") // 添加导航栏标题
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        } // NavigationStack 结束
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
        .onChange(of: searchText) { oldValue, newValue in
            // 搜索时折叠所有分组并重置懒加载数量
            expandedClients.removeAll()
            loadedSearchResultCount = 10
        }
    }
    
    // 刷新所有基金信息的方法 (不变)
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
        fundService.addLog("ManageHoldingsView: 所有基金信息已刷新。")
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
        fundService.addLog("ManageHoldingsView: 客户 '\(oldClientName)' 已批量修改为 '\(newClientName)'。")
        
        newClientName = ""
        clientToRename = nil
    }

    private func confirmDeleteClientHoldings() {
        guard let client = clientToDelete else { return }
        
        let holdingsToDeleteCount = dataManager.holdings.filter { $0.clientName == client.clientName }.count
        dataManager.holdings.removeAll { $0.clientName == client.clientName }
        
        dataManager.saveData()
        fundService.addLog("ManageHoldingsView: 已批量删除客户 '\(client.clientName)' 名下的 \(holdingsToDeleteCount) 个持仓。")
        
        clientToDelete = nil
        isShowingDeleteAlert = false
    }

    private func deleteHoldings(in clientGroup: ClientGroupForManagement, at offsets: IndexSet) {
        let holdingsToDeleteIDs = offsets.map { clientGroup.holdings[$0].id }
        
        dataManager.holdings.removeAll { holding in
            holdingsToDeleteIDs.contains(holding.id)
        }
        dataManager.saveData()
        fundService.addLog("ManageHoldingsView: 从客户 \(clientGroup.clientName) 下删除了 \(holdingsToDeleteIDs.count) 个持仓。")
    }

    // MARK: - 自定义 Section Header 视图，包含批量编辑按钮 (与 ClientView 样式类似)
    private func headerView(for clientGroup: ClientGroupForManagement) -> some View {
        HStack {
            Text(clientGroup.clientName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(clientGroup.clientName.morandiColor().textColorBasedOnLuminance()) // <--- 修改点
            
            Spacer()
            
            // 批量改名按钮 (改为蓝色)
            Button("批量改名") {
                clientToRename = clientGroup
                newClientName = clientGroup.clientName
                isShowingRenameAlert = true
            }
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.blue) // 批量改名按钮文字颜色改为蓝色
            .buttonStyle(.plain)
            .padding(.trailing, 10) // 添加右侧间距
            
            // 新增: 批量删除按钮 (红色)
            Button("批量删除") {
                clientToDelete = clientGroup
                isShowingDeleteAlert = true
            }
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.red) // 批量删除按钮文字颜色为红色
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8) // 恢复一些垂直内边距，让标题区域有一定高度
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading) // 确保背景覆盖整个宽度
        .background(
            // 使用莫兰迪色渐变
            LinearGradient(gradient: Gradient(colors: [clientGroup.clientName.morandiColor(), Color.white]), startPoint: .topLeading, endPoint: .bottomTrailing)
        ) // 应用渐变背景
        .clipShape(RoundedRectangle(cornerRadius: 10)) // 明确裁剪
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2) // 添加阴影
    }
}

// MARK: - 专门用于 ManageHoldingsView 的简化版 HoldingRow
struct HoldingRowForManagement: View {
    let holding: FundHolding
    let onEdit: () -> Void // 用于触发编辑的闭包

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(holding.fundName) (\(holding.fundCode))")
                    .font(.headline)
                Text("客户: \(holding.clientName) (\(holding.clientID))") // 显示客户姓名和客户号
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("购买金额: \(holding.purchaseAmount, specifier: "%.2f")元")
                    .font(.caption)
                Text("购买份额: \(holding.purchaseShares, specifier: "%.4f")份")
                    .font(.caption)
                Text("购买日期: \(holding.purchaseDate, formatter: DateFormatter.shortDate)") // 这里使用 shortDate
                    .font(.caption)
                if !holding.remarks.isEmpty { // 检查备注是否为空
                    Text("备注: \(holding.remarks)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            // 修正: 将编辑按钮移动到右边
            Button(action: onEdit) {
                Text("编辑")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless) // 确保按钮样式不会覆盖前景颜色
            .padding(.leading, 10) // 添加一些左侧间距
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16) // 新增：添加水平内边距
        // 添加卡片样式
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
    }
}

// MARK: - DateFormatter 扩展 (放置在这里，确保 ManageHoldingsView 可以访问)
extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN") // 根据需要调整
        return formatter
    }()
}
