import SwiftUI
import SafariServices

// 帮助 URL 遵守 Identifiable 协议，以便与 .sheet(item:) 配合使用
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct FavoritesView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedIdentifiableUrl: IdentifiableURL?

    // 根据字符串生成颜色的辅助函数
    private func colorForString(_ string: String) -> Color {
        let colors: [Color] = [
            .orange.opacity(0.1),
            .blue.opacity(0.1),
            .green.opacity(0.1),
            .purple.opacity(0.1),
            .pink.opacity(0.1),
            .teal.opacity(0.1),
            .cyan.opacity(0.1)
        ]
        var hash = 0
        for character in string.unicodeScalars {
            hash = Int(character.value) + ((hash << 5) - hash)
        }
        let index = abs(hash) % colors.count
        return colors[index]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if dataManager.favorites.isEmpty {
                    Text("收藏夹为空")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(dataManager.favorites) { item in
                        CustomCardView(
                            title: item.name,
                            description: nil,
                            imageName: "link.circle.fill",
                            backgroundColor: colorForString(item.name),
                            contentForegroundColor: .secondary,
                            action: {
                                if let url = URL(string: item.url) {
                                    self.selectedIdentifiableUrl = IdentifiableURL(url: url)
                                }
                            }
                        ) { fgColor in
                            Text(item.url)
                                .font(.caption)
                                .foregroundColor(fgColor.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(.horizontal)
                        .scaleEffect(0.85) // 关键改动：将卡片大小调整为 0.85
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("我的收藏")
        .sheet(item: $selectedIdentifiableUrl) { identifiableURL in
            SafariView(url: identifiableURL.url)
        }
    }
}
