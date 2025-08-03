import SwiftUI

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

                        Spacer().frame(height: 30) // 在清空卡片前添加间距

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
                    fundService.addLog("ManageHoldingsMenuView: 所有持仓数据已清除。")
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此操作不可撤销，您确定要清除所有持仓数据吗？")
            }
        }
    }
}

struct ConfigView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss

    @State private var showingManageHoldingsMenuSheet = false
    @State private var showingAPILogSheet = false
    @State private var showingAboutSheet = false
    
    @AppStorage("isQuickNavBarEnabled") private var isQuickNavBarEnabled: Bool = true

    func onAppear() {
        // ...
    }
    
    func onDisappear() {
        // ...
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - 持仓管理
                    CustomCardView(
                        title: "管理持仓",
                        description: "新增、编辑或清空基金持仓数据",
                        imageName: "folder.fill",
                        backgroundColor: Color.blue.opacity(0.1),
                        contentForegroundColor: .blue,
                        action: {
                            showingManageHoldingsMenuSheet = true
                        }
                    ) { _ in EmptyView() }
                    .padding(.horizontal)
                    .scaleEffect(0.9) // 缩小卡片

                    // MARK: - 自定义功能
                    CustomCardView(
                        title: "快速定位栏",
                        description: nil, // 不再使用 description 参数
                        imageName: "slider.horizontal.3",
                        backgroundColor: Color.purple.opacity(0.1),
                        contentForegroundColor: .purple,
                        action: nil, // 明确传递 action 为 nil
                        toggleBinding: $isQuickNavBarEnabled // 传入 Toggle 的 Binding
                    ) { fgColor in // content 闭包中只包含描述文本
                        Text("在客户持仓页面启用或禁用快速字母定位栏")
                            .font(.caption)
                            .foregroundColor(fgColor.opacity(0.7))
                            .lineLimit(2)
                    }
                    .padding(.horizontal)
                    .scaleEffect(0.9) // 缩小卡片

                    // MARK: - 其他
                    CustomCardView(
                        title: "API 日志查询",
                        description: "查看基金净值API请求与响应日志",
                        imageName: "doc.text.magnifyingglass",
                        backgroundColor: Color.cyan.opacity(0.1),
                        contentForegroundColor: .cyan,
                        action: {
                            showingAPILogSheet = true
                        }
                    ) { _ in EmptyView() }
                    .padding(.horizontal)
                    .scaleEffect(0.9) // 缩小卡片

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
                    .padding(.horizontal)
                    .scaleEffect(0.9) // 缩小卡片
                }
                .padding(.vertical)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
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
        }
    }
}
