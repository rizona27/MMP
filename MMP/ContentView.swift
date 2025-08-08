import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var fundService = FundService()

    var body: some View {
        // 将 NavigationView 移到 TabView 的外面，包裹整个应用的主要视图
        NavigationView {
            TabView {
                ClientView()
                    .tabItem {
                        Image(systemName: "dollarsign.circle")
                        Text("客户")
                    }
                    .environmentObject(dataManager)
                    .environmentObject(fundService)

                SummaryView()
                    .tabItem {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("一览")
                    }
                    .environmentObject(dataManager)
                    .environmentObject(fundService)

                // 新增收藏夹标签页
                FavoritesView()
                    .tabItem {
                        Image(systemName: "heart.fill")
                        Text("收藏")
                    }
                    .environmentObject(dataManager)

                ConfigView()
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("配置")
                    }
                    .environmentObject(dataManager)
                    .environmentObject(fundService)
            }
        }
    }
}

// --- 模拟环境测试 (预览代码) ---
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let dataManager = DataManager()
        let fundService = FundService()
        
        // 关键修改：只在 holdings 为空时添加模拟数据
        if dataManager.holdings.isEmpty {
            let holding1 = FundHolding(
                clientName: "张三",
                clientID: "A001",
                fundCode: "000001",
                purchaseAmount: 5000.0,
                purchaseShares: 2000.0,
                purchaseDate: Date().addingTimeInterval(-86400 * 180),
                remarks: "首次购买",
                fundName: "华夏成长混合 (预览)",
                currentNav: 2.50,
                navDate: Date()
            )
            let holding2 = FundHolding(
                clientName: "李四",
                clientID: "B002",
                fundCode: "000002",
                purchaseAmount: 2500.0,
                purchaseShares: 781.25,
                purchaseDate: Date().addingTimeInterval(-86400 * 90),
                remarks: "追加投资",
                fundName: "南方稳健增长 (预览)",
                currentNav: 3.20,
                navDate: Date()
            )
            
            // 注意：DispatchQueue.main.async 是为了确保在主线程上修改 @Published 属性
            DispatchQueue.main.async {
                dataManager.addHolding(holding1) // 使用 addHolding 方法
                dataManager.addHolding(holding2) // 使用 addHolding 方法
            }
        }
        
        return ContentView()
            .environmentObject(dataManager)
            .environmentObject(fundService)
    }
}
