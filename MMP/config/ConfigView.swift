import SwiftUI
import UniformTypeIdentifiers

// MARK: - 新增通用的卡片视图
struct CustomCardView<Content: View>: View {
    var title: String?
    var description: String?
    var imageName: String?
    var backgroundColor: Color = .white
    var contentForegroundColor: Color = .primary
    var action: (() -> Void)? = nil
    
    // 新增属性用于可选的 Toggle
    var toggleBinding: Binding<Bool>? = nil
    var toggleTint: Color = .accentColor

    @ViewBuilder let content: (Color) -> Content // 内部内容现在接收一个 Color 参数

    var body: some View {
        let cardContent = VStack(alignment: .leading, spacing: 8) {
            HStack { // 将图标、标题和可选的 Toggle 放在同一行
                if let imageName = imageName {
                    Image(systemName: imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundColor(contentForegroundColor)
                }

                if let title = title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(contentForegroundColor)
                }

                Spacer() // 将 Toggle 推到右边

                if let toggleBinding = toggleBinding {
                    Toggle(isOn: toggleBinding) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .tint(toggleTint)
                }
            }

            // 只有在没有 Toggle 且 description 存在时才显示 description
            if let description = description, toggleBinding == nil {
                Text(description)
                    .font(.caption)
                    .foregroundColor(contentForegroundColor.opacity(0.7))
                    .lineLimit(2)
            }
            
            content(contentForegroundColor) // 将 contentForegroundColor 传递给 content 闭包
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading) // 统一卡片大小
        .background(backgroundColor)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)

        if let action = action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            cardContent
        }
    }
}

// MARK: - 新增管理持仓的子菜单视图
struct ManageHoldingsMenuView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss

    @State private var showingAddSheet = false
    @State private var showingManageHoldingsSheet = false
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section {
                        CustomCardView(
                            title: "新增持仓",
                            description: "手动添加新的基金持仓记录",
                            imageName: "plus.circle.fill",
                            backgroundColor: Color.green.opacity(0.1),
                            contentForegroundColor: .green
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingAddSheet = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .scaleEffect(0.85) // 缩小卡片

                        CustomCardView(
                            title: "编辑持仓",
                            description: "管理现有基金持仓，包括修改和删除",
                            imageName: "pencil.circle.fill",
                            backgroundColor: Color.blue.opacity(0.1),
                            contentForegroundColor: .blue
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingManageHoldingsSheet = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .scaleEffect(0.85) // 缩小卡片

                        // Spacer().frame(height: 30) // 移除此行以减小间距

                        CustomCardView(
                            title: "清空所有持仓",
                            description: "删除所有基金持仓数据，此操作不可撤销",
                            imageName: "trash.circle.fill",
                            backgroundColor: Color.red.opacity(0.1),
                            contentForegroundColor: .red
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingClearConfirmation = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .scaleEffect(0.85) // 缩小卡片
                    }
                }
                .listStyle(.plain)
                .padding(.top, 20)
            }
            .navigationTitle("")
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
            .sheet(isPresented: $showingAddSheet) {
                AddHoldingView()
                    .environmentObject(dataManager)
                    .environmentObject(fundService)
            }
            .sheet(isPresented: $showingManageHoldingsSheet) {
                ManageHoldingsView()
                    .environmentObject(dataManager)
                    .environmentObject(fundService)
            }
            .confirmationDialog("确认清空所有持仓数据？",
                                isPresented: $showingClearConfirmation,
                                titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    dataManager.holdings.removeAll()
                    dataManager.saveData()
                    fundService.addLog("ManageHoldingsMenuView: 所有持仓数据已清除。", type: .info)
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此操作不可撤销，您确定要清除所有持仓数据吗？")
            }
        }
    }
}

// MARK: - 主题模式选择视图
// 此处引用 MMPApp.swift 中已定义的 ThemeMode 枚举
struct ThemeModeView: View {
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    
    var body: some View {
        CustomCardView(
            title: "主题模式",
            description: nil,
            imageName: "paintbrush.fill",
            backgroundColor: Color.teal.opacity(0.1),
            contentForegroundColor: .teal
        ) { fgColor in
            Picker("主题", selection: $themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .background(Color.white.opacity(0.5))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - CSV导出文档
struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var message: String
    
    init(message: String) {
        self.message = message
    }
    
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadCorruptFile)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: message.data(using: .utf8)!)
    }
}

// MARK: - 数组安全访问扩展
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct ConfigView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss

    @State private var showingManageHoldingsMenuSheet = false
    @State private var showingAPILogSheet = false
    @State private var showingAboutSheet = false
    @State private var showingManageFavoritesSheet = false
    @State private var isImporting = false // 导入状态
    @State private var isExporting = false // 导出状态
    @State private var document: CSVExportDocument? // 导出文档
    
    @AppStorage("isQuickNavBarEnabled") private var isQuickNavBarEnabled: Bool = true
    
    @State private var showToast = false
    @State private var toastMessage = ""
    
    private func showToast(message: String) {
        toastMessage = message
        showToast = true
    }

    func onAppear() {
        // ...
    }
    
    func onDisappear() {
        // ...
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 8) { // 减小 VStack 的间距
                        // 第一行：管理持仓和管理收藏夹
                        HStack(spacing: 8) { // 减小 HStack 的间距
                            // 管理持仓卡片
                            CustomCardView(
                                title: "管理持仓",
                                description: "新增、编辑或清空持仓数据",
                                imageName: "folder.fill",
                                backgroundColor: Color.blue.opacity(0.1),
                                contentForegroundColor: .blue,
                                action: {
                                    showingManageHoldingsMenuSheet = true
                                }
                            ) { _ in EmptyView() }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(0.9) // 缩小卡片
                                    
                            // 管理收藏夹卡片
                            CustomCardView(
                                title: "管理收藏夹",
                                description: "添加、编辑和删除常用链接",
                                imageName: "heart.circle.fill",
                                backgroundColor: Color.red.opacity(0.1),
                                contentForegroundColor: .red,
                                action: {
                                    showingManageFavoritesSheet = true
                                }
                            ) { _ in EmptyView() }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(0.9) // 缩小卡片
                        }
                        .padding(.horizontal, 8) // 减小水平边距
                                
                        // 第二行：导入数据和导出数据
                        HStack(spacing: 8) { // 减小 HStack 的间距
                            // 导入数据卡片
                            CustomCardView(
                                title: "导入数据",
                                description: "从CSV文件导入持仓数据",
                                imageName: "square.and.arrow.down.fill",
                                backgroundColor: Color.orange.opacity(0.1),
                                contentForegroundColor: .orange,
                                action: {
                                    isImporting = true
                                }
                            ) { _ in EmptyView() }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(0.9) // 缩小卡片
                                    
                            // 导出数据卡片
                            CustomCardView(
                                title: "导出数据",
                                description: "导出持仓数据到CSV文件",
                                imageName: "square.and.arrow.up.fill",
                                backgroundColor: Color.orange.opacity(0.1),
                                contentForegroundColor: .orange,
                                action: {
                                    exportHoldingsToCSV()
                                    isExporting = true
                                }
                            ) { _ in EmptyView() }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(0.9) // 缩小卡片
                        }
                        .padding(.horizontal, 8) // 减小水平边距
                                
                        // 第三行：快速定位和API日志
                        HStack(spacing: 8) { // 减小 HStack 的间距
                            // 快速定位卡片
                            CustomCardView(
                                title: "定位栏",
                                description: nil,
                                imageName: "slider.horizontal.3",
                                backgroundColor: Color.purple.opacity(0.1),
                                contentForegroundColor: .purple,
                                action: nil,
                                toggleBinding: $isQuickNavBarEnabled
                            ) { fgColor in
                                Text("启用或禁用快速定位栏")
                                    .font(.caption)
                                    .foregroundColor(fgColor.opacity(0.7))
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(0.9) // 缩小卡片
                                    
                            // API日志卡片
                            CustomCardView(
                                title: "日志查询",
                                description: "API请求与响应日志",
                                imageName: "doc.text.magnifyingglass",
                                backgroundColor: Color.cyan.opacity(0.1),
                                contentForegroundColor: .cyan,
                                action: {
                                    showingAPILogSheet = true
                                }
                            ) { _ in EmptyView() }
                            .frame(maxWidth: .infinity)
                            .scaleEffect(0.9) // 缩小卡片
                        }
                        .padding(.horizontal, 8) // 减小水平边距
                                
                        // 第四行：主题模式
                        ThemeModeView()
                            .padding(.horizontal, 8) // 减小水平边距
                            .scaleEffect(0.9)
                            
                        // 第五行：关于
                        CustomCardView(
                            title: "关于",
                            description: "查看程序版本信息及相关说明",
                            imageName: "info.circle.fill",
                            backgroundColor: Color.gray.opacity(0.1),
                            contentForegroundColor: .secondary,
                            action: {
                                showingAboutSheet = true
                            }
                        ) { _ in EmptyView() }
                        .padding(.horizontal, 8) // 减小水平边距
                        .scaleEffect(0.9) // 缩小卡片
                    }
                    .padding(.vertical, 8) // 减小垂直边距
                }
                .navigationTitle("")
                .navigationBarHidden(true)
                .onAppear(perform: onAppear)
                .onDisappear(perform: onDisappear)
                // 文件导入导出处理器
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.commaSeparatedText],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImport(result: result)
                }
                .fileExporter(
                    isPresented: $isExporting,
                    document: document,
                    contentType: .commaSeparatedText,
                    defaultFilename: "\(Date().formatted(Date.FormatStyle().month().day()))数据导出.csv"
                ) { result in
                    handleFileExport(result: result)
                }
                .sheet(isPresented: $showingManageHoldingsMenuSheet) {
                    ManageHoldingsMenuView()
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                }
                .sheet(isPresented: $showingManageFavoritesSheet) {
                    ManageFavoritesView()
                        .environmentObject(dataManager)
                }
                .sheet(isPresented: $showingAPILogSheet) {
                    APILogView()
                        .environmentObject(fundService)
                }
                .sheet(isPresented: $showingAboutSheet) {
                    AboutView()
                }
                    
                // 新增的 Toast 视图
                ToastView(message: toastMessage, isShowing: $showToast)
            }
        }
    }
    
    // MARK: - 导出持仓数据为CSV
    private func exportHoldingsToCSV() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var csvString = "客户姓名,基金代码,购买金额,购买份额,购买日期,客户号,备注\n"
        
        for holding in dataManager.holdings {
            let formattedDate = dateFormatter.string(from: holding.purchaseDate)
            let amountStr = String(format: "%.2f", holding.purchaseAmount)
            let sharesStr = String(format: "%.2f", holding.purchaseShares)
            
            csvString += "\(holding.clientName),\(holding.fundCode),\(amountStr),\(sharesStr),\(formattedDate),\(holding.clientID),\(holding.remarks)\n"
        }
        
        document = CSVExportDocument(message: csvString)
    }
    
    // MARK: - 处理文件导出结果
    private func handleFileExport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            fundService.addLog("导出成功: \(url.lastPathComponent)", type: .success)
            self.showToast(message: "导出成功")
        case .failure(let error):
            fundService.addLog("导出失败: \(error.localizedDescription)", type: .error)
            self.showToast(message: "导出失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 处理文件导入
    private func handleFileImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            // --- 核心改动：请求和释放文件访问权限 ---
            guard url.startAccessingSecurityScopedResource() else {
                self.showToast(message: "导入失败：无法获取文件访问权限。")
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            // ------------------------------------
            
            let data = try String(contentsOf: url, encoding: .utf8)
            let lines = data.components(separatedBy: "\n")
            guard lines.count > 1 else {
                self.showToast(message: "导入失败：CSV文件为空或只有标题行。")
                return
            }
            
            // 解析CSV头部
            let headers = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            // 定义列名映射
            let columnMapping: [String: [String]] = [
                "客户姓名": ["客户姓名", "姓名"],
                "基金代码": ["基金代码", "代码"],
                "购买金额": ["购买金额", "持仓成本（元）", "持仓成本", "成本"],
                "购买份额": ["购买份额", "当前份额", "份额"],
                "购买日期": ["购买日期", "最早购买日期", "日期"],
                "客户号": ["客户号", "核心客户号"],
                "备注": ["备注"]
            ]
            
            // 查找列索引
            var columnIndices = [String: Int]()
            var missingRequiredHeaders: [String] = []

            for (key, aliases) in columnMapping {
                var found = false
                for alias in aliases {
                    if let index = headers.firstIndex(where: { $0.contains(alias) }) {
                        columnIndices[key] = index
                        found = true
                        break
                    }
                }
                // 检查必要列是否找到
                if !found && ["基金代码", "购买金额", "购买份额", "客户号"].contains(key) {
                    missingRequiredHeaders.append(key)
                }
            }

            // 检查所有必要列是否都已找到
            if !missingRequiredHeaders.isEmpty {
                let missingColumnsString = missingRequiredHeaders.joined(separator: ", ")
                self.showToast(message: "导入失败：缺少必要的列 (\(missingColumnsString))")
                return
            }
            
            // 解析数据行
            var importedCount = 0
            for i in 1..<lines.count {
                let values = lines[i].components(separatedBy: ",")
                // 确保数据行有足够的列
                guard values.count >= headers.count else { continue }
                
                // 数据清洗
                guard let fundCodeIndex = columnIndices["基金代码"],
                        let fundCode = values[safe: fundCodeIndex]?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
                let cleanedFundCode = fundCode.padding(toLength: 6, withPad: "0", startingAt: 0)
                
                guard let amountIndex = columnIndices["购买金额"],
                        let amountStr = values[safe: amountIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
                        let amount = Double(amountStr) else { continue }
                let cleanedAmount = (amount * 100).rounded() / 100
                
                guard let sharesIndex = columnIndices["购买份额"],
                        let sharesStr = values[safe: sharesIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
                        let shares = Double(sharesStr) else { continue }
                let cleanedShares = (shares * 100).rounded() / 100
                
                var purchaseDate = Date()
                if let dateIndex = columnIndices["购买日期"],
                    let dateStr = values[safe: dateIndex]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    if let date = dateFormatter.date(from: dateStr) {
                        purchaseDate = date
                    }
                }
                
                guard let clientIDIndex = columnIndices["客户号"],
                        let clientID = values[safe: clientIDIndex]?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
                let cleanedClientID = clientID.padding(toLength: 12, withPad: "0", startingAt: 0)

                // --- 关键修改：处理客户姓名 ---
                var clientName: String
                if let clientNameIndex = columnIndices["客户姓名"],
                    let nameFromCSV = values[safe: clientNameIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !nameFromCSV.isEmpty {
                    clientName = nameFromCSV
                } else {
                    clientName = cleanedClientID // 如果没有客户姓名，则使用客户号作为姓名
                }

                // --- 关键修改：处理备注 ---
                let remarks = columnIndices["备注"].flatMap { values[safe: $0]?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                
                // 创建新持仓记录
                let newHolding = FundHolding(
                    clientName: clientName,
                    clientID: cleanedClientID,
                    fundCode: cleanedFundCode,
                    purchaseAmount: cleanedAmount,
                    purchaseShares: cleanedShares,
                    purchaseDate: purchaseDate,
                    remarks: remarks
                )
                
                // 添加到数据管理器
                dataManager.holdings.append(newHolding)
                importedCount += 1
                
                // 记录导入详情
                fundService.addLog("导入记录: \(clientName)-\(cleanedFundCode) 金额: \(cleanedAmount) 份额: \(cleanedShares)", type: .info)
            }
            
            // 保存数据并记录结果
            dataManager.saveData()
            fundService.addLog("导入完成: 成功导入 \(importedCount) 条记录", type: .success)
            self.showToast(message: "导入成功：\(importedCount) 条记录。")
            
        } catch {
            fundService.addLog("导入失败: \(error.localizedDescription)", type: .error)
            self.showToast(message: "导入失败: \(error.localizedDescription)")
        }
    }
}
