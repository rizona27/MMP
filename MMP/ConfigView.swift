import SwiftUI
import UniformTypeIdentifiers

struct CustomCardView<Content: View>: View {
    var title: String?
    var description: String?
    var imageName: String?
    var backgroundColor: Color = .white
    var contentForegroundColor: Color = .primary
    var action: (() -> Void)? = nil
    var toggleBinding: Binding<Bool>? = nil
    var toggleTint: Color = .accentColor
    var hasAnimatedBackground: Bool = false

    @State private var animationProgress: CGFloat = 0.0

    @ViewBuilder let content: (Color) -> Content

    var body: some View {
        let cardContent = VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                if let imageName = imageName {
                    Image(systemName: imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(contentForegroundColor)
                }

                if let title = title {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(contentForegroundColor)
                }

                Spacer()

                if let toggleBinding = toggleBinding {
                    Toggle(isOn: toggleBinding) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .tint(toggleTint)
                }
            }

            if let description = description, toggleBinding == nil {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(contentForegroundColor.opacity(0.7))
                    .lineLimit(2)
            }
            
            content(contentForegroundColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(
            ZStack {
                if hasAnimatedBackground {
                    let gradientColors = [
                        Color(red: 0.7, green: 0.8, blue: 0.9, opacity: 0.7),
                        Color(red: 0.9, green: 0.7, blue: 0.8, opacity: 0.7),
                        Color(red: 0.9, green: 0.8, blue: 0.7, opacity: 0.7),
                        Color(red: 0.7, green: 0.8, blue: 0.9, opacity: 0.7)
                    ]

                    LinearGradient(
                        gradient: Gradient(colors: gradientColors),
                        startPoint: UnitPoint(x: -1 + animationProgress * 2, y: -1 + animationProgress * 2),
                        endPoint: UnitPoint(x: 0 + animationProgress * 2, y: 0 + animationProgress * 2)
                    )
                    .animation(Animation.linear(duration: 8).repeatForever(autoreverses: false), value: animationProgress)
                    .onAppear {
                        animationProgress = 1.0
                    }
                } else {
                    backgroundColor
                }
            }
        )
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

struct FundAPIView: View {
    @AppStorage("selectedFundAPI") private var selectedFundAPI: FundAPI = .eastmoney
    
    var body: some View {
        CustomCardView(
            title: "数据接口",
            description: nil,
            imageName: "network",
            backgroundColor: Color.blue.opacity(0.1),
            contentForegroundColor: .blue
        ) { fgColor in
            Picker("数据接口", selection: $selectedFundAPI) {
                ForEach(FundAPI.allCases) { api in
                    Text(api.rawValue).tag(api)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct ManageHoldingsMenuView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss

    @State private var showingAddSheet = false
    @State private var showingManageHoldingsSheet = false
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    Section {
                        CustomCardView(
                            title: "新增持仓",
                            description: "添加新的基金持仓记录",
                            imageName: "plus.circle.fill",
                            backgroundColor: Color.green.opacity(0.1),
                            contentForegroundColor: .green
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingAddSheet = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .padding(.bottom, 12)

                        CustomCardView(
                            title: "编辑持仓",
                            description: "管理现有持仓，包括修改和删除",
                            imageName: "pencil.circle.fill",
                            backgroundColor: Color.blue.opacity(0.1),
                            contentForegroundColor: .blue
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingManageHoldingsSheet = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .padding(.bottom, 12)

                        CustomCardView(
                            title: "清空持仓",
                            description: "删除所有基金持仓数据，注意：此操作不可撤销",
                            imageName: "trash.circle.fill",
                            backgroundColor: Color.red.opacity(0.1),
                            contentForegroundColor: .red
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingClearConfirmation = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .padding(.top, 24)
                    }
                }
                .listStyle(.plain)
                .padding(.top, 20)
                .padding(.horizontal, 16)
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
                Text("浅色").tag(ThemeMode.light)
                Text("深色").tag(ThemeMode.dark)
                Text("系统").tag(ThemeMode.system)
            }
            .pickerStyle(.segmented)
        }
    }
}

struct PrivacyModeView: View {
    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled: Bool = true
    
    var body: some View {
        CustomCardView(
            title: "隐私模式",
            description: nil,
            imageName: "lock.fill",
            backgroundColor: Color.mint.opacity(0.1),
            contentForegroundColor: .mint
        ) { fgColor in
            Picker("隐私模式", selection: $isPrivacyModeEnabled) {
                Text("开启").tag(true)
                Text("关闭").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }
}

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
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var document: CSVExportDocument?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var gradientAnimationProgress: CGFloat = 0.0

    private func showToast(message: String) {
        toastMessage = message
        showToast = true
    }

    func onAppear() {
        // 确保默认值设置正确
        // 隐私模式默认开启
        UserDefaults.standard.register(defaults: ["isPrivacyModeEnabled": true])
        // 主题模式默认跟随系统
        UserDefaults.standard.register(defaults: ["themeMode": "system"])
        // 数据接口默认使用天天基金
        UserDefaults.standard.register(defaults: ["selectedFundAPI": "eastmoney"])
    }
    
    func onDisappear() {
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
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
                            
                            CustomCardView(
                                title: "导出数据",
                                description: "导出持仓数据到CSV文件",
                                imageName: "square.and.arrow.up.fill",
                                backgroundColor: Color.orange.opacity(0.1),
                                contentForegroundColor: .orange,
                                action: {
                                    exportHoldingsToCSV()
                                }
                            ) { _ in EmptyView() }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 8)
                        
                        HStack(spacing: 12) {
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
                        }
                        .padding(.horizontal, 8)

                        HStack(spacing: 12) {
                            PrivacyModeView()
                                .frame(maxWidth: .infinity)
                            ThemeModeView()
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 8)

                        HStack(spacing: 12) {
                            CustomCardView(
                                title: "关于",
                                description: "程序版本信息和说明",
                                imageName: "info.circle.fill",
                                contentForegroundColor: .white,
                                action: {
                                    showingAboutSheet = true
                                },
                                hasAnimatedBackground: true
                            ) { _ in EmptyView() }
                            .frame(maxWidth: .infinity)
                            
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                        }
                        .padding(.horizontal, 8)

                        FundAPIView()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                        
                        Divider()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        VStack {
                            Text("Happiness around the corner.")
                                .font(.system(size: 16))
                                .italic()
                                .bold(false)
                                .foregroundColor(Color(red: 0.7, green: 0.85, blue: 0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                    .padding(.vertical, 8)
                }
                .navigationTitle("")
                .navigationBarHidden(true)
                .onAppear(perform: onAppear)
                .onDisappear(perform: onDisappear)
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
                .sheet(isPresented: $showingAPILogSheet) {
                    APILogView()
                        .environmentObject(fundService)
                }
                .sheet(isPresented: $showingAboutSheet) {
                    AboutView()
                }
                    
                ToastView(message: toastMessage, isShowing: $showToast)
            }
        }
    }

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
        isExporting = true
    }

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

    private func handleFileImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                self.showToast(message: "导入失败：无法获取文件访问权限。")
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let data = try String(contentsOf: url, encoding: .utf8)
            let lines = data.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard lines.count > 1 else {
                self.showToast(message: "导入失败：CSV文件为空或只有标题行。")
                return
            }
            
            let headers = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            let columnMapping: [String: [String]] = [
                "客户姓名": ["客户姓名", "姓名"],
                "基金代码": ["基金代码", "代码"],
                "购买金额": ["购买金额", "持仓成本（元）", "持仓成本", "成本"],
                "购买份额": ["购买份额", "当前份额", "份额"],
                "购买日期": ["购买日期", "最早购买日期", "日期"],
                "客户号": ["客户号", "核心客户号"],
                "备注": ["备注"]
            ]

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
                if !found && ["基金代码", "购买金额", "购买份额", "客户号"].contains(key) {
                    missingRequiredHeaders.append(key)
                }
            }

            if !missingRequiredHeaders.isEmpty {
                let missingColumnsString = missingRequiredHeaders.joined(separator: ", ")
                self.showToast(message: "导入失败：缺少必要的列 (\(missingColumnsString))")
                return
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let existingHoldingsSet: Set<FundHolding> = Set(dataManager.holdings)

            var importedCount = 0
            for i in 1..<lines.count {
                let values = lines[i].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard values.count >= headers.count else { continue }
                
                guard let fundCodeIndex = columnIndices["基金代码"],
                                     let fundCode = values[safe: fundCodeIndex]?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
                let cleanedFundCode = String(format: "%06d", Int(fundCode) ?? 0)
                
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
                    if let date = dateFormatter.date(from: dateStr) {
                        purchaseDate = date
                    }
                }
                
                guard let clientIDIndex = columnIndices["客户号"],
                                     let clientID = values[safe: clientIDIndex]?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
                let desiredLength = 12
                let currentLength = clientID.count
                var cleanedClientID = clientID

                if currentLength < desiredLength {
                    let numberOfZerosToAdd = desiredLength - currentLength
                    let leadingZeros = String(repeating: "0", count: numberOfZerosToAdd)
                    cleanedClientID = leadingZeros + clientID
                }
                var clientName: String
                if let clientNameIndex = columnIndices["客户姓名"],
                   let nameFromCSV = values[safe: clientNameIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !nameFromCSV.isEmpty {
                    clientName = nameFromCSV
                } else {
                    clientName = cleanedClientID
                }

                let remarks = columnIndices["备注"].flatMap { values[safe: $0]?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                
                let newHolding = FundHolding(
                    clientName: clientName,
                    clientID: cleanedClientID,
                    fundCode: cleanedFundCode,
                    purchaseAmount: cleanedAmount,
                    purchaseShares: cleanedShares,
                    purchaseDate: purchaseDate,
                    remarks: remarks
                )

                if !existingHoldingsSet.contains(newHolding) {
                    dataManager.holdings.append(newHolding)
                    importedCount += 1
                    fundService.addLog("导入记录: \(clientName)-\(cleanedFundCode) 金额: \(cleanedAmount) 份额: \(cleanedShares)", type: .info)
                } else {
                    fundService.addLog("跳过重复记录: \(clientName)-\(cleanedFundCode)", type: .info)
                }
            }
            
            dataManager.saveData()
            fundService.addLog("导入完成: 成功导入 \(importedCount) 条记录", type: .success)
            self.showToast(message: "导入成功：\(importedCount) 条记录。")
            
            NotificationCenter.default.post(name: NSNotification.Name("HoldingsDataUpdated"), object: nil)
            
        } catch {
            fundService.addLog("导入失败: \(error.localizedDescription)", type: .error)
            self.showToast(message: "导入失败: \(error.localizedDescription)")
        }
    }
}

extension FundHolding: Hashable, Equatable {
    static func == (lhs: FundHolding, rhs: FundHolding) -> Bool {
        let calendar = Calendar.current
        return lhs.fundCode == rhs.fundCode &&
            lhs.purchaseAmount == rhs.purchaseAmount &&
            lhs.purchaseShares == rhs.purchaseShares &&
            calendar.isDate(lhs.purchaseDate, inSameDayAs: rhs.purchaseDate) &&
            lhs.clientID == rhs.clientID &&
            lhs.clientName == rhs.clientName &&
            lhs.remarks == rhs.remarks
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fundCode)
        hasher.combine(purchaseAmount)
        hasher.combine(purchaseShares)
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: purchaseDate)
        hasher.combine(dateComponents.year)
        hasher.combine(dateComponents.month)
        hasher.combine(dateComponents.day)
        hasher.combine(clientID)
        hasher.combine(clientName)
        hasher.combine(remarks)
    }
}
