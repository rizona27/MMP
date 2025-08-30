import SwiftUI
import Foundation

extension String {
    func morandiColor() -> Color {
        var hash = 0
        for char in self.unicodeScalars {
            hash = (hash << 5) &+ (hash - hash) + Int(char.value)
        }
        
        let hue = Double(abs(hash) % 256) / 256.0
        let saturation = 0.4 + (Double(abs(hash) % 30) / 100.0)
        let brightness = 0.7 + (Double(abs(hash) % 20) / 100.0)

        return Color(hue: hue, saturation: saturation, brightness: brightness).opacity(0.8)
    }
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
        return self.luminance() > 0.6 ? .black : .white
    }
}

extension Double {
    var formattedPercentage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self / 100)) ?? "\(self)%"
    }
}

extension Date {
    func isOlderThan(minutes: Int) -> Bool {
        let calendar = Calendar.current
        let expirationDate = calendar.date(byAdding: .minute, value: minutes, to: self) ?? Date()
        return expirationDate < Date()
    }
}

struct ClientGroup: Identifiable {
    let id: String
    let clientName: String
    let clientID: String
    let totalAUM: Double
    var holdings: [FundHolding]
    var isPinned: Bool
    var pinnedTimestamp: Date?
}

// MARK: - ClientView
struct ClientView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @State private var isRefreshing = false
    
    @Environment(\.colorScheme) var colorScheme

    @State private var expandedClients: Set<String> = []
    
    @AppStorage("isQuickNavBarEnabled") private var isQuickNavBarEnabled: Bool = true
    
    @State private var loadedGroupedClientCount: Int = 10
    
    @State private var searchText = ""
    @State private var loadedSearchResultCount: Int = 10
    
    @State private var scrollViewProxy: ScrollViewProxy?
    
    private func localizedStandardCompare(_ s1: String, _ s2: String, ascending: Bool) -> Bool {
        if ascending {
            return s1.localizedStandardCompare(s2) == .orderedAscending
        } else {
            return s1.localizedStandardCompare(s2) == .orderedDescending
        }
    }

    var pinnedHoldings: [FundHolding] {
        dataManager.holdings.filter { $0.isPinned }
            .sorted { (h1, h2) -> Bool in
                (h1.pinnedTimestamp ?? .distantPast) > (h2.pinnedTimestamp ?? .distantPast)
            }
    }

    var groupedHoldingsByClientName: [ClientGroup] {
        let allHoldings = dataManager.holdings

        let groupedDictionary = Dictionary(grouping: allHoldings) { holding in
            holding.clientName
        }
        
        var clientGroups: [ClientGroup] = groupedDictionary.map { (clientName, holdings) in
            let totalAUM = holdings.reduce(0.0) { accumulatedResult, holding in
                accumulatedResult + holding.totalValue
            }
            let representativeClientID = holdings.first?.clientID ?? ""
            
            return ClientGroup(
                id: clientName,
                clientName: clientName,
                clientID: representativeClientID,
                totalAUM: totalAUM,
                holdings: holdings,
                isPinned: false,
                pinnedTimestamp: nil
            )
        }
        
        clientGroups.sort { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }
        
        for i in 0..<clientGroups.count {
            clientGroups[i].holdings.sort { (h1, h2) -> Bool in
                if h1.isPinned && !h2.isPinned { return true }
                if !h1.isPinned && h2.isPinned { return false }
                
                if h1.isPinned && h2.isPinned {
                    return (h1.pinnedTimestamp ?? .distantPast) > (h2.pinnedTimestamp ?? .distantPast)
                }
                
                return h1.purchaseDate < h2.purchaseDate
            }
        }

        return clientGroups
    }

    var sectionedClientGroups: [Character: [ClientGroup]] {
        var sections: [Character: [ClientGroup]] = [:]

        if !pinnedHoldings.isEmpty {
            let pinnedClientGroup = ClientGroup(
                id: "Pinned",
                clientName: "置顶区域",
                clientID: "",
                totalAUM: pinnedHoldings.reduce(0.0) { $0 + $1.totalValue },
                holdings: pinnedHoldings,
                isPinned: true,
                pinnedTimestamp: pinnedHoldings.compactMap { $0.pinnedTimestamp }.max()
            )
            sections["★", default: []].append(pinnedClientGroup)
        }

        let allGroups = groupedHoldingsByClientName
        for group in allGroups {
            let firstChar = group.clientName.first?.uppercased().first ?? "#"
            sections[firstChar, default: []].append(group)
        }
        return sections
    }

    var sortedSectionKeys: [Character] {
        sectionedClientGroups.keys.sorted { (char1, char2) -> Bool in
            if char1 == "★" { return true }
            if char2 == "★" { return false }
            if char1 == "#" { return false }
            if char2 == "#" { return true }
            return String(char1).localizedStandardCompare(String(char2)) == .orderedAscending
        }
    }

    var areAnyCardsExpanded: Bool {
        !expandedClients.isEmpty
    }

    private func searchResultsListView() -> some View {
        List {
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
                    HoldingRow(holding: holding, hideClientInfo: false)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                        .listRowSeparator(.hidden)
                        .onAppear {
                            if holding.id == searchResults.prefix(loadedSearchResultCount).last?.id && loadedSearchResultCount < searchResults.count {
                                loadedSearchResultCount += 10
                                fundService.addLog("ClientView: 加载更多搜索结果。当前数量: \(loadedSearchResultCount)", type: .info)
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .padding(.bottom, 20)
    }

    private func pinnedHoldingsSection() -> some View {
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
                ForEach(pinnedHoldings) { holding in
                    HoldingRow(holding: holding, hideClientInfo: false)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.white)
                        Text("置顶区域")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.white]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                    
                    HStack {
                        Text("基金总市值: \(pinnedHoldings.reduce(0.0) { $0 + $1.totalValue }, specifier: "%.2f")元")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("持有基金数: \(pinnedHoldings.count)支")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 0)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    private func clientGroupSection(clientGroup: ClientGroup, sectionKey: Character) -> some View {
        let baseColor = clientGroup.id.morandiColor()
        
        return DisclosureGroup(
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
            ForEach(clientGroup.holdings.prefix(loadedGroupedClientCount)) { holding in
                HoldingRow(holding: holding, hideClientInfo: true)
                    .environmentObject(dataManager)
                    .environmentObject(fundService)
                    .onAppear {
                        if holding.id == clientGroup.holdings.prefix(loadedGroupedClientCount).last?.id && loadedGroupedClientCount < clientGroup.holdings.count {
                            loadedGroupedClientCount += 10
                            fundService.addLog("ClientView: 加载更多客户分组。当前数量: \(loadedGroupedClientCount)", type: .info)
                        }
                    }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("**\(clientGroup.clientName)**")
                        .font(.subheadline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !clientGroup.clientID.isEmpty {
                        Text("(\(clientGroup.clientID))")
                            .font(.caption.monospaced())
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    }
                    Spacer()
                    
                    Text("持仓数: \(clientGroup.holdings.count)支")
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                }
                .padding(.vertical, 8)
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
        }
        .id(clientGroup.id)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
    }
    
    private func toggleAllCards() {
        withAnimation {
            if areAnyCardsExpanded {
                expandedClients.removeAll()
            } else {
                var allClientIds = Set(groupedHoldingsByClientName.map { $0.id })
                if !pinnedHoldings.isEmpty {
                    allClientIds.insert("Pinned")
                }
                expandedClients = allClientIds
            }
        }
    }
    
    // MARK: - Main Body
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if !searchText.isEmpty {
                        searchResultsListView()
                    } else {
                        HStack(spacing: 8) {
                            if isQuickNavBarEnabled && !sortedSectionKeys.isEmpty {
                                VStack(spacing: 2) {
                                    ScrollView(.vertical, showsIndicators: false) {
                                        VStack(spacing: 2) {
                                            ForEach(sortedSectionKeys, id: \.self) { titleChar in
                                                Button(action: {
                                                    withAnimation {
                                                        if titleChar == "★" {
                                                            scrollViewProxy?.scrollTo("Pinned", anchor: .top)
                                                        } else if let firstClient = sectionedClientGroups[titleChar]?.first {
                                                            scrollViewProxy?.scrollTo(firstClient.id, anchor: .top)
                                                        }
                                                    }
                                                }) {
                                                    Text(String(titleChar))
                                                        .font(.caption)
                                                        .fontWeight(.bold)
                                                        .frame(width: 24, height: 24)
                                                        .background(Color.gray.opacity(0.2))
                                                        .cornerRadius(8)
                                                        .foregroundColor(.primary)
                                                }
                                                .padding(.vertical, 2)
                                            }
                                        }
                                        .padding(.vertical, 10)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .frame(width: 44, height: geometry.size.height)
                                .background(Color(.systemGroupedBackground))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            
                            if groupedHoldingsByClientName.isEmpty && pinnedHoldings.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("当前没有持仓数据。")
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                VStack {
                                    ScrollViewReader { proxy in
                                        List {
                                            if !pinnedHoldings.isEmpty {
                                                pinnedHoldingsSection()
                                            }
                                            
                                            ForEach(sortedSectionKeys.filter { $0 != "★" }, id: \.self) { sectionKey in
                                                Section(header: EmptyView().id(sectionKey)) {
                                                    let clientsForSection = sectionedClientGroups[sectionKey]?.sorted(by: { localizedStandardCompare($0.clientName, $1.clientName, ascending: true) }) ?? []
                                                    ForEach(clientsForSection) { clientGroup in
                                                        clientGroupSection(clientGroup: clientGroup, sectionKey: sectionKey)
                                                    }
                                                }
                                            }
                                        }
                                        .listStyle(.plain)
                                        .onAppear {
                                            scrollViewProxy = proxy
                                        }
                                    }
                                }
                                .frame(width: geometry.size.width - (isQuickNavBarEnabled ? 44 + 8 : 0) - 4, height: geometry.size.height)
                                .background(Color(.systemGroupedBackground))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索客户、基金代码、基金名称...")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: toggleAllCards) {
                            Image(systemName: areAnyCardsExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Task {
                                await refreshAllFundInfo()
                            }
                        }) {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .disabled(isRefreshing)
                    }
                }
            } 
        }
        .onChange(of: searchText) { _, newValue in
            loadedSearchResultCount = 10
            loadedGroupedClientCount = 10
            if newValue.isEmpty {
                expandedClients.removeAll()
            }
        }
    }
    
    private func refreshAllFundInfo() async {
        isRefreshing = true
        fundService.addLog("ClientView: 开始刷新所有基金信息...", type: .info)
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
            
            DispatchQueue.main.async {
                for updatedHolding in refreshedHoldings {
                    dataManager.updateHolding(updatedHolding)
                }
                dataManager.saveData()
            }
            fundService.addLog("ClientView: 所有基金信息刷新完成。", type: .info)
        }
        isRefreshing = false
    }
}
