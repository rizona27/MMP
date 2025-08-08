import SwiftUI

struct EditFavoritesListView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    @State private var showingEditFavoriteSheet: FavoriteItem?

    var body: some View {
        NavigationView {
            List {
                ForEach(dataManager.favorites) { item in
                    VStack(alignment: .leading) {
                        Text(item.name).font(.headline)
                        Text(item.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if let index = dataManager.favorites.firstIndex(where: { $0.id == item.id }) {
                                dataManager.favorites.remove(at: index)
                                dataManager.saveData()
                            }
                        } label: {
                            Label("删除", systemImage: "trash.fill")
                        }
                    }
                    .onTapGesture {
                        self.showingEditFavoriteSheet = item
                    }
                }
            }
            .listStyle(.plain) // 使用 .plain 样式以匹配风格
            .navigationTitle("")
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
            .sheet(item: $showingEditFavoriteSheet) { favoriteItem in
                EditFavoriteView(favorite: favoriteItem)
                    .environmentObject(dataManager)
            }
        }
    }
}
