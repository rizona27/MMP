import SwiftUI

struct ManageFavoritesView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showingAddFavoriteSheet = false
    @State private var showingEditListView = false
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationView {
            VStack {
                List {
                    // 第一个 Section 包含了新增和编辑卡片
                    Section {
                        // 新增地址卡片
                        CustomCardView(
                            title: "新增地址",
                            description: "手动添加新的收藏网址",
                            imageName: "plus.circle.fill",
                            backgroundColor: Color.green.opacity(0.1),
                            contentForegroundColor: .green
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingAddFavoriteSheet = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .scaleEffect(0.85)

                        // 编辑地址卡片
                        CustomCardView(
                            title: "编辑地址",
                            description: "管理现有收藏，包括修改和删除",
                            imageName: "pencil.circle.fill",
                            backgroundColor: Color.blue.opacity(0.1),
                            contentForegroundColor: .blue
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingEditListView = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .scaleEffect(0.85)
                    }

                    // 关键改动：添加一个明确的 Spacer 来创建你想要的距离
                    // 这段代码将确保两个 Section 之间有明显的空隙
                    Spacer().frame(height: 20)
                    .listRowInsets(EdgeInsets()) // 确保 Spacer 占满整行
                    .listRowSeparator(.hidden)

                    // 第二个 Section 包含了清空卡片
                    Section {
                        CustomCardView(
                            title: "清空所有收藏",
                            description: "删除所有收藏网址，此操作不可撤销",
                            imageName: "trash.circle.fill",
                            backgroundColor: Color.red.opacity(0.1),
                            contentForegroundColor: .red
                        ) { _ in EmptyView() }
                        .onTapGesture {
                            showingClearConfirmation = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .scaleEffect(0.85)
                    }
                }
                .listStyle(.plain)
                .padding(.top, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .sheet(isPresented: $showingAddFavoriteSheet) {
                AddFavoriteView()
                    .environmentObject(dataManager)
            }
            .sheet(isPresented: $showingEditListView) {
                EditFavoritesListView()
                    .environmentObject(dataManager)
            }
            .confirmationDialog("确认清空所有收藏？",
                               isPresented: $showingClearConfirmation,
                               titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    dataManager.favorites.removeAll()
                    dataManager.saveData()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此操作不可撤销，您确定要清除所有收藏数据吗？")
            }
        }
    }
}
