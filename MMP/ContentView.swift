import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var fundService = FundService()

    @State private var showSplash = true
    @State private var selectedTab = 2
    @State private var splashOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // 主应用视图，当 showSplash 为 false 时显示
            NavigationView {
                TabView(selection: $selectedTab) {
                    ClientView()
                        .tabItem {
                            Image(systemName: "dollarsign.circle")
                            Text("客户")
                        }
                        .tag(0)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                        .animation(.easeInOut(duration: 0.4), value: selectedTab)
                        .transition(.slide) // 使用内置的 .slide 过渡效果
                    
                    TopPerformersView()
                        .tabItem {
                            Image(systemName: "list.bullet.rectangle.portrait")
                            Text("排名")
                        }
                        .tag(1)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                        .animation(.easeInOut(duration: 0.4), value: selectedTab)
                        .transition(.slide) // 使用内置的 .slide 过渡效果

                    SummaryView()
                        .tabItem {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text("一览")
                        }
                        .tag(2)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                        .animation(.easeInOut(duration: 0.4), value: selectedTab)
                        .transition(.slide) // 使用内置的 .slide 过渡效果

                    FavoritesView()
                        .tabItem {
                            Image(systemName: "heart.fill")
                            Text("收藏")
                        }
                        .tag(3)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                        .animation(.easeInOut(duration: 0.4), value: selectedTab)
                        .transition(.slide) // 使用内置的 .slide 过渡效果

                    ConfigView()
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text("设置")
                        }
                        .tag(4)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                        .animation(.easeInOut(duration: 0.4), value: selectedTab)
                        .transition(.slide) // 使用内置的 .slide 过渡效果
                }
            }
            .opacity(showSplash ? 0 : 1)

            // 启动动画视图
            if showSplash {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Less")
                        .font(.system(size: 50, weight: .light, design: .serif))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 6)
                    Text("is")
                        .font(.system(size: 35, weight: .light, design: .serif))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 6)
                    Text("More")
                        .font(.system(size: 70, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 6)
                    Text("Finding Abundance Through Subtraction")
                        .font(.custom("HelveticaNeue-Light", size: 18))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 4)
                        .padding(.top, 25)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 30)
                .padding(.top, 250)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color(hex: "99A9E9"), Color(hex: "7585D0")]), startPoint: .top, endPoint: .bottom)
                )
                .edgesIgnoringSafeArea(.all)
                .opacity(splashOpacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 1.5)) {
                            self.splashOpacity = 0.0
                            self.showSplash = false
                        }
                    }
                }
            }
        }
    }
}

// 颜色扩展，用于方便地使用十六进制颜色
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// --- 模拟环境测试 (预览代码) ---
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let dataManager = DataManager()
        let fundService = FundService()

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

            DispatchQueue.main.async {
                dataManager.addHolding(holding1)
                dataManager.addHolding(holding2)
            }
        }

        return ContentView()
            .environmentObject(dataManager)
            .environmentObject(fundService)
    }
}
