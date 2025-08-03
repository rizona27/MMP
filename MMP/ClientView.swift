import SwiftUI

// 新增 String 扩展用于生成莫兰迪色
extension String {
    func morandiColor() -> Color {
        // 使用简单的哈希算法生成一个相对稳定的颜色
        var hash = 0
        for char in self.unicodeScalars {
            hash = (hash << 5) &+ (hash - hash) + Int(char.value)
        }
        
        // 调整色相，使其在相对柔和的范围内
        let hue = Double(abs(hash) % 256) / 256.0
        // 调整饱和度：从 0.4 到 0.7，更明亮活泼
        let saturation = 0.4 + (Double(abs(hash) % 30) / 100.0) // 0.4 到 0.7
        // 调整亮度：从 0.7 到 0.9，更明亮
        let brightness = 0.7 + (Double(abs(hash) % 20) / 100.0) // 0.7 到 0.9

        return Color(hue: hue, saturation: saturation, brightness: brightness).opacity(0.8) // 略微降低透明度，与 ManageHoldingsView 保持一致
    }
}

struct ClientView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @State private var searchText = ""
    @State private var isRefreshing = false

    // 用于跟踪哪些客户分组是展开的 (存储客户的唯一标识，即客户名称)
    @State private var expandedClients: Set<String> = []
    // 新增：用于控制全部展开/全部折叠的状态
    @State private var isAllExpanded: Bool = false // 暂时保留，但逻辑会根据 expandedClients 变化

    // 新增：控制快速定位栏的透明度
    @State private var quickNavBarVisibleOpacity: Double = 0.5
    // 用于控制透明度重置任务
    @State private var opacityResetTask: Task<Void, Never>? = nil

    // 从 AppStorage 读取快速定位栏的开关状态
    @AppStorage("isQuickNavBarEnabled") private var isQuickNavBarEnabled: Bool = true
    
    // MARK: - Lazy Loading State
    @State private var loadedGroupedClientCount: Int = 10 // 默认加载10个客户组
    @State private var loadedSearchResultCount: Int = 10 // 默认加载10个搜索结果基金
    
    // 自定义排序器，用于按拼音排序 (保留，用于客户名称的 A-Z 排序)
    private func localizedStandardCompare(_ s1: String, _ s2: String, ascending: Bool) -> Bool {
        if ascending {
            return s1.localizedStandardCompare(s2) == .orderedAscending
        } else {
            return s1.localizedStandardCompare(s2) == .orderedDescending
        }
    }

    // 计算属性：获取所有被置顶的基金
    var pinnedHoldings: [FundHolding] {
        dataManager.holdings.filter { $0.isPinned }
            .sorted { (h1, h2) -> Bool in
                // 置顶基金按置顶时间倒序排列（最新的在最上面）
                (h1.pinnedTimestamp ?? .distantPast) > (h2.pinnedTimestamp ?? .distantPast)
            }
    }

    // 计算属性：按客户名称分组后的数据
    var groupedHoldingsByClientName: [ClientGroup] {
        // 所有基金都参与分组，无论是否置顶
        let allHoldings = dataManager.holdings

        // 仅按客户名称进行分组
        let groupedDictionary = Dictionary(grouping: allHoldings) { holding in
            // 客户名称相同即视为同一客户
            holding.clientName
        }
        
        // 将字典转换为 ClientGroup 数组
        var clientGroups: [ClientGroup] = groupedDictionary.map { (clientName, holdings) in
            // 计算每个客户的总市值
            let totalAUM = holdings.reduce(0.0) { accumulatedResult, holding in
                accumulatedResult + holding.totalValue
            }
            // 客户号现在是该客户组中第一个持仓的客户号（作为代表）
            let representativeClientID = holdings.first?.clientID ?? ""
            
            return ClientGroup(
                id: clientName, // 使用客户名称作为ID
                clientName: clientName,
                clientID: representativeClientID, // 存储一个代表性的客户号
                totalAUM: totalAUM,
                holdings: holdings, // 客户组内的持仓
                isPinned: false, // 常规客户组，isPinned 为 false
                pinnedTimestamp: nil // 常规客户组，pinnedTimestamp 为 nil
            )
        }
        
        // 对客户分组进行排序 (按客户名称拼音 A-Z 升序)
        clientGroups.sort { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }
        
        // 客户组内的基金持仓排序：置顶基金优先，然后按置顶时间倒序，最后按购买日期升序
        for i in 0..<clientGroups.count {
            clientGroups[i].holdings.sort { (h1, h2) -> Bool in
                if h1.isPinned && !h2.isPinned { return true } // h1 置顶且 h2 未置顶，h1 优先
                if !h1.isPinned && h2.isPinned { return false } // h1 未置顶且 h2 置顶，h2 优先
                
                // 如果都是置顶的，按置顶时间倒序排序 (最新的置顶在前面)
                if h1.isPinned && h2.isPinned {
                    return (h1.pinnedTimestamp ?? .distantPast) > (h2.pinnedTimestamp ?? .distantPast)
                }
                
                // 默认按购买日期升序
                return h1.purchaseDate < h2.purchaseDate
            }
        }

        return clientGroups
    }

    // 新增计算属性：用于按首字母分组，以支持快速定位条
    var sectionedClientGroups: [Character: [ClientGroup]] {
        var sections: [Character: [ClientGroup]] = [:]

        // 添加置顶基金到 '★' 分区
        if !pinnedHoldings.isEmpty {
            let pinnedClientGroup = ClientGroup(
                id: "Pinned", // 特殊ID
                clientName: "置顶区域", // 特殊名称，已修改
                clientID: "",
                totalAUM: pinnedHoldings.reduce(0.0) { $0 + $1.totalValue },
                holdings: pinnedHoldings, // 包含所有置顶基金
                isPinned: true, // 置顶组，isPinned 为 true
                pinnedTimestamp: pinnedHoldings.compactMap { $0.pinnedTimestamp }.max() // 置顶组的最新置顶时间
            )
            sections["★", default: []].append(pinnedClientGroup)
        }

        // 添加普通客户分组
        let allGroups = groupedHoldingsByClientName
        for group in allGroups {
            let firstChar = group.clientName.first?.uppercased().first ?? "#"
            sections[firstChar, default: []].append(group)
        }
        return sections
    }

    // 新增计算属性：用于快速定位条的标题
    var sortedSectionKeys: [Character] {
        sectionedClientGroups.keys.sorted { (char1, char2) -> Bool in
            // 特殊处理，让 '★' 排在最前面，'#' 排在最后
            if char1 == "★" { return true }
            if char2 == "★" { return false }
            if char1 == "#" { return false }
            if char2 == "#" { return true }
            return String(char1).localizedStandardCompare(String(char2)) == .orderedAscending // 确保按拼音排序
        }
    }

    // MARK: - Private Helper Views for Body Refactoring

    // 搜索结果列表视图
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
                // 对搜索结果进行排序：置顶优先，然后按购买日期升序
                ForEach(searchResults.sorted(by: { (h1, h2) -> Bool in
                    if h1.isPinned && !h2.isPinned { return true }
                    if !h1.isPinned && h2.isPinned { return false }
                    
                    if h1.isPinned && h2.isPinned {
                        return (h1.pinnedTimestamp ?? .distantPast) > (h2.pinnedTimestamp ?? .distantPast)
                    }
                    return h1.purchaseDate < h2.purchaseDate
                }).prefix(loadedSearchResultCount)) { holding in // <-- Lazy loading for search results
                    HoldingRow(holding: holding, hideClientInfo: false) // 搜索结果列表显示客户信息
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16)) // 调整间距为1
                        .listRowSeparator(.hidden)
                        .onAppear {
                            // 当最后一个可见项出现时，加载更多搜索结果
                            if holding.id == searchResults.prefix(loadedSearchResultCount).last?.id && loadedSearchResultCount < searchResults.count {
                                loadedSearchResultCount += 10
                                fundService.addLog("ClientView: 加载更多搜索结果。当前数量: \(loadedSearchResultCount)")
                            }
                        }
                }
            }
        }
        .listStyle(.plain) // 保持 plain 样式
        .refreshable { // 下拉刷新功能
            await refreshAllFundInfo()
        }
        .padding(.bottom, 20) // 添加底部内边距，防止与导航栏重叠
    }

    // 置顶区域视图
    private func pinnedHoldingsSection() -> some View {
        // Section Header 使用 EmptyView，但 ID 保留用于快速定位
        Section(header: EmptyView().id("★")) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedClients.contains("Pinned") },
                    set: { isExpanded in
                        if isExpanded {
                            expandedClients.insert("Pinned")
                        } else {
                            expandedClients.remove("Pinned")
                        }
                    }
                )
            ) {
                // 展开后显示的内容
                ForEach(pinnedHoldings) { holding in
                    HoldingRow(holding: holding, hideClientInfo: false) // 在置顶区域显示客户信息
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) { // 调整 VStack 内部间距
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.white) // 将图标颜色改为白色
                        Text("置顶区域")
                            .font(.headline)
                            .foregroundColor(.white) // 将文字颜色改为白色
                    }
                    .padding(.vertical, 8) // 恢复一些垂直内边距，让标题区域有一定高度
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading) // 确保背景覆盖整个宽度
                    .background(
                        // 置顶区颜色为天蓝到白色渐变
                        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.white]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    ) // 应用渐变背景
                    .clipShape(RoundedRectangle(cornerRadius: 10)) // 明确裁剪
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2) // 添加阴影
                    
                    // 市值部分不着色
                    HStack {
                        Text("基金总市值: \(pinnedHoldings.reduce(0.0) { $0 + $1.totalValue }, specifier: "%.2f")元")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("持有基金数: \(pinnedHoldings.count)支")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16) // 保持对齐
                }
                .padding(.vertical, 0) // 将整体垂直内边距控制在这里，创建“几像素”间隔
            }
            // 关键调整：将 top 和 bottom 间距增加到 6
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden) // 隐藏DisclosureGroup的默认分隔线
        }
    }

    // 单个客户分组视图
    private func clientGroupSection(clientGroup: ClientGroup, sectionKey: Character) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedClients.contains(clientGroup.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedClients.insert(clientGroup.id)
                    } else {
                        expandedClients.remove(clientGroup.id)
                    }
                }
            )
        ) {
            // 展开后显示的内容 (客户名下的基金列表)
            ForEach(clientGroup.holdings.prefix(loadedGroupedClientCount)) { holding in
                HoldingRow(holding: holding, hideClientInfo: true) // 在客户分组内隐藏客户信息
                    .environmentObject(dataManager)
                    .environmentObject(fundService)
                    .onAppear {
                        if holding.id == clientGroup.holdings.prefix(loadedGroupedClientCount).last?.id && loadedGroupedClientCount < clientGroup.holdings.count {
                            loadedGroupedClientCount += 10
                            fundService.addLog("ClientView: 加载更多客户分组。当前数量: \(loadedGroupedClientCount)")
                        }
                    }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) { // 调整 VStack 内部间距
                // 只将名字和客户号部分着色，并添加渐变
                HStack {
                    Text(clientGroup.clientName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(clientGroup.id.morandiColor().textColorBasedOnLuminance()) // <--- 修改点
                    if !clientGroup.clientID.isEmpty {
                        Text("(\(clientGroup.clientID))")
                            .font(.subheadline)
                            .foregroundColor(clientGroup.id.morandiColor().textColorBasedOnLuminance().opacity(0.8)) // <--- 修改点
                    }
                }
                .padding(.vertical, 8) // 恢复一些垂直内边距，让标题区域有一定高度
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading) // 确保背景覆盖整个宽度
                .background(
                    LinearGradient(gradient: Gradient(colors: [clientGroup.id.morandiColor(), Color.white]), startPoint: .topLeading, endPoint: .bottomTrailing)
                ) // 应用渐变背景
                .clipShape(RoundedRectangle(cornerRadius: 10)) // 明确裁剪
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2) // 添加阴影
                
                // 市值部分不着色
                HStack {
                    Text("总市值: \(clientGroup.totalAUM, specifier: "%.2f")元")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("持仓数: \(clientGroup.holdings.count)支")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16) // 保持对齐
            }
            .padding(.vertical, 0) // 将整体垂直内边距控制在这里，创建“几像素”间隔
        }
        // 关键调整：将 top 和 bottom 间距增加到 6
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
    }

    // 分组客户列表视图 (包括置顶分栏)
    private func groupedClientsListView() -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .leading) { // 使用 ZStack 来放置快速定位条
                // 快速定位条 (作为 ZStack 的直接子视图，位于最左侧)
                if isQuickNavBarEnabled && !sortedSectionKeys.isEmpty && searchText.isEmpty { // 根据开关状态显示
                    VStack(spacing: 2) {
                        ForEach(sortedSectionKeys, id: \.self) { titleChar in
                            Button(action: {
                                withAnimation {
                                    proxy.scrollTo(titleChar, anchor: .top)
                                    
                                    let targetId: String
                                    if titleChar == "★" {
                                        targetId = "Pinned"
                                    } else {
                                        // 找到该首字母下的第一个客户组
                                        guard let firstClientInGroup = sectionedClientGroups[titleChar]?.sorted(by: { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }).first else { return }
                                        targetId = firstClientInGroup.id
                                    }
                                    
                                    if expandedClients.contains(targetId) {
                                        // 如果已展开，则折叠该组
                                        expandedClients.remove(targetId)
                                    } else {
                                        // 如果未展开，则展开该组并折叠其他所有组
                                        expandedClients.removeAll()
                                        expandedClients.insert(targetId)
                                    }
                                    
                                    // 取消任何现有的任务
                                    opacityResetTask?.cancel()
                                    
                                    // 立即设置为完全不透明
                                    quickNavBarVisibleOpacity = 1.0
                                    
                                    // 启动一个新的任务，在延迟后恢复透明度
                                    opacityResetTask = Task {
                                        do {
                                            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 秒
                                            withAnimation(.easeOut(duration: 0.5)) {
                                                quickNavBarVisibleOpacity = 0.5
                                            }
                                        } catch {
                                            // 任务被取消，不做任何事情
                                        }
                                    }
                                }
                            }) {
                                Text(String(titleChar))
                                    .font(.caption) // 字体放大
                                    .fontWeight(.bold)
                                    .frame(width: 24, height: 24) // 设置固定大小的触摸区域
                                    .background(Color.gray.opacity(0.2)) // 调整背景颜色
                                    .cornerRadius(8) // 调整圆角
                                    .foregroundColor(.primary.opacity(quickNavBarVisibleOpacity))
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 2)
                    .background(Color.clear)
                    .offset(x: 0) // 保持 x: 0，使其紧贴 ZStack 的左侧
                    .zIndex(1) // 确保它在 List 上层显示
                }

                // List 内容 (根据开关状态调整左侧内边距)
                List {
                    if groupedHoldingsByClientName.isEmpty && pinnedHoldings.isEmpty {
                        Text("当前没有持仓数据。")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        // 置顶基金分栏
                        if !pinnedHoldings.isEmpty {
                            pinnedHoldingsSection() // 调用新的私有方法
                        }

                        // 普通客户分组
                        // 确保这里的排序也使用了 localizedStandardCompare 以支持拼音
                        ForEach(sortedSectionKeys.filter { $0 != "★" }, id: \.self) { sectionKey in
                            Section(header: EmptyView()) {
                                let clientsForSection = sectionedClientGroups[sectionKey]?.sorted(by: { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }) ?? []
                                ForEach(clientsForSection.prefix(loadedGroupedClientCount)) { clientGroup in
                                    clientGroupSection(clientGroup: clientGroup, sectionKey: sectionKey)
                                        .onAppear {
                                            if clientGroup.id == clientsForSection.prefix(loadedGroupedClientCount).last?.id && loadedGroupedClientCount < clientsForSection.count {
                                                loadedGroupedClientCount += 10
                                                fundService.addLog("ClientView: 加载更多客户分组。当前数量: \(loadedGroupedClientCount)")
                                            }
                                        }
                                }
                            }
                            .id(sectionKey)
                            // .listRowInsets 和 .listRowSeparator 已经应用在 clientGroupSection 内部，这里不再需要
                        }
                    }
                }
                .listStyle(.plain) // 保持 plain 样式
                .refreshable {
                    await refreshAllFundInfo()
                }
                // 根据开关状态调整左侧内边距
                .padding(.leading, isQuickNavBarEnabled ? 40 : 16) // 快速定位栏开启时为 40，关闭时为 16 (默认水平边距)
                .padding(.bottom, 20) // 添加底部内边距，防止与导航栏重叠
            }
            .id(isQuickNavBarEnabled) // **关键修复：将 id 修饰符添加到 ZStack 外部，强制 ZStack 及其内容重新渲染**
        }
    }

    // MARK: - Main Body
    var body: some View {
        VStack {
            // 搜索栏和折叠/展开按钮
            HStack {
                SearchBar(text: $searchText, placeholder: "搜索客户、基金代码、基金名称...")
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75) // 搜索栏缩短到3/4
                    .padding(.vertical, 8)
                    .padding(.leading) // 左侧内边距

                // 折叠/展开图标按钮
                Button(action: {
                    withAnimation {
                        // 如果有任何一个分栏是展开的，则执行“折叠所有”操作
                        if !expandedClients.isEmpty {
                            expandedClients.removeAll()
                        } else {
                            // 如果所有分栏都已折叠，则执行“展开所有”操作
                            var allClientIdsToExpand: Set<String> = []
                            for clientGroup in groupedHoldingsByClientName {
                                allClientIdsToExpand.insert(clientGroup.id)
                            }
                            if !pinnedHoldings.isEmpty {
                                allClientIdsToExpand.insert("Pinned")
                            }
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

            // 主内容区域：根据搜索框内容显示不同的列表
            if !searchText.isEmpty {
                searchResultsListView()
            } else {
                groupedClientsListView()
            }
        }
        .navigationTitle("客户持仓")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea()) // 设置整个视图的背景色
        // 监听 searchText 变化，重置加载数量并折叠所有分组
        .onChange(of: searchText) { oldValue, newValue in
            loadedSearchResultCount = 10
            loadedGroupedClientCount = 10
            if newValue.isEmpty {
                expandedClients.removeAll()
            }
        }
        // 监听 expandedClients 变化，更新 isAllExpanded 状态
        // 实际上，isAllExpanded 不再直接控制按钮，而是expandedClients.isEmpty
        .onChange(of: expandedClients) { oldValue, newValue in
            // 这个 onChange 不再用于控制按钮的 isAllExpanded 状态，但可以保留用于调试或其他逻辑
            var allPossibleClientIds = Set(groupedHoldingsByClientName.map { $0.id })
            if !pinnedHoldings.isEmpty {
                allPossibleClientIds.insert("Pinned")
            }
            isAllExpanded = newValue.isSuperset(of: allPossibleClientIds) && newValue.count == allPossibleClientIds.count
        }
        // 新增：监听 isQuickNavBarEnabled 变化，重置快速定位栏透明度
        .onChange(of: isQuickNavBarEnabled) { oldValue, newValue in
            if newValue { // 如果开关被打开
                opacityResetTask?.cancel() // 取消任何现有任务
                quickNavBarVisibleOpacity = 1.0 // 立即设置为完全不透明
                opacityResetTask = Task { // 启动新的任务，在延迟后恢复透明度
                    do {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 秒
                        withAnimation(.easeOut(duration: 0.5)) {
                            quickNavBarVisibleOpacity = 0.5
                        }
                    } catch {
                        // 任务被取消，不做任何事情
                    }
                }
            } else { // 如果开关被关闭
                opacityResetTask?.cancel() // 取消任何现有任务
                quickNavBarVisibleOpacity = 0.0 // 立即将透明度设置为0，使其完全消失
            }
        }
    }
    
    // 刷新所有基金信息的方法 (不变)
    private func refreshAllFundInfo() async {
        isRefreshing = true
        fundService.addLog("ClientView: 开始刷新所有基金信息...")
        await withTaskGroup(of: FundHolding.self) { group in
            for holding in dataManager.holdings {
                group.addTask {
                    let fetchedInfo = await fundService.fetchFundInfo(code: holding.fundCode)
                    var updatedHolding = holding
                    updatedHolding.fundName = fetchedInfo.fundName
                    updatedHolding.currentNav = fetchedInfo.currentNav
                    updatedHolding.navDate = fetchedInfo.navDate
                    updatedHolding.isValid = fetchedInfo.isValid
                    return updatedHolding
                }
            }
            
            var refreshedHoldings: [FundHolding] = []
            for await updatedHolding in group {
                refreshedHoldings.append(updatedHolding)
            }
            
            // 在主线程更新 dataManager
            DispatchQueue.main.async {
                for updatedHolding in refreshedHoldings {
                    dataManager.updateHolding(updatedHolding)
                }
                dataManager.saveData() // 保存数据
            }
            fundService.addLog("ClientView: 所有基金信息刷新完成。")
        }
        isRefreshing = false
    }
}

// 定义一个新的结构体来表示客户分组，以便在 ForEach 中使用
// 注意：此结构体应在单独的文件中定义一次，此处仅为示例
struct ClientGroup: Identifiable {
    let id: String // 唯一标识符，现在是客户名称
    let clientName: String
    let clientID: String // 存储一个代表性的客户号
    let totalAUM: Double // 该客户的总资产管理规模（即基金总市值）
    var holdings: [FundHolding] // 该客户名下的基金持仓
    var isPinned: Bool // 新增：客户组是否被置顶（根据其持仓推断）
    var pinnedTimestamp: Date? // 新增：客户组的置顶时间戳（根据其持仓推断）
}

// SearchBar 组件 (保持不变)
// 注意：此结构体应在单独的文件中定义一次，此处仅为示例
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    
    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .padding(8)
                .padding(.horizontal, 24)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                        
                        if !text.isEmpty {
                            Button(action: {
                                self.text = ""
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
        }
    }
}

// 扩展 Sequence，用于去重 (保留)
extension Sequence where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
