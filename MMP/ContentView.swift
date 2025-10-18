import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var fundService = FundService()

    @State private var showSplash = true
    @State private var selectedTab = 0
    @State private var splashOpacity: Double = 0.0
    
    @State private var startPoint = UnitPoint.topLeading
    @State private var endPoint = UnitPoint.bottomTrailing

    @State private var copyrightGradientStartPoint = UnitPoint.leading
    @State private var copyrightGradientEndPoint = UnitPoint.trailing

    @State private var isRefreshLocked = false

    var body: some View {
        ZStack {
            NavigationView {
                TabView(selection: $selectedTab) {
                    SummaryView()
                        .tabItem {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text("一览")
                        }
                        .tag(0)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                    
                    ClientView()
                        .tabItem {
                            Image(systemName: "dollarsign.circle")
                            Text("客户")
                        }
                        .tag(1)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                    
                    TopPerformersView()
                        .tabItem {
                            Image(systemName: "list.bullet.rectangle.portrait")
                            Text("排名")
                        }
                        .tag(2)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)

                    ConfigView()
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text("设置")
                        }
                        .tag(3)
                        .environmentObject(dataManager)
                        .environmentObject(fundService)
                }
                .disabled(isRefreshLocked)
            }
            .opacity(showSplash ? 0 : 1)
            .animation(.easeIn(duration: 1.0), value: showSplash)

            if showSplash {
                VStack(alignment: .leading, spacing: 8) {

                    Spacer()
                        .frame(height: 150)
                    
                    Text("Less")
                        .font(.system(size: 50, weight: .light, design: .serif).italic())
                        .foregroundColor(Color(hex: "8B0000"))
                        .shadow(color: .gray.opacity(0.6), radius: 8, x: 2, y: 8)
                    Text("is")
                        .font(.system(size: 35, weight: .light, design: .serif).italic())
                        .foregroundColor(Color(hex: "8B0000"))
                        .shadow(color: .gray.opacity(0.6), radius: 8, x: 2, y: 8)
                    Text("More.")
                        .font(.system(size: 70, weight: .heavy, design: .serif).italic())
                        .foregroundColor(Color(hex: "8B0000"))
                        .shadow(color: .gray.opacity(0.6), radius: 8, x: 2, y: 8)
                    Text("Finding Abundance Through Subtraction...")
                        .font(.system(size: 18, weight: .light).italic())
                        .foregroundColor(Color(hex: "8B0000").opacity(0.8))
                        .shadow(color: .gray.opacity(0.6), radius: 6, x: 1, y: 6)
                        .padding(.top, 25)

                    Spacer()

                    Text("Copyright©Rizona. All Rights Reserved")
                        .font(.system(size: 12, weight: .light).italic())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 40)
                        .foregroundColor(.clear)
                        .overlay(
                            LinearGradient(gradient: Gradient(colors: [Color.blue, Color.red]), startPoint: copyrightGradientStartPoint, endPoint: copyrightGradientEndPoint)
                                .mask(
                                    Text("Copyright © Rizona. All Rights Reserved")
                                        .font(.system(size: 12, weight: .light).italic())
                                )
                        )
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                self.copyrightGradientStartPoint = UnitPoint.trailing
                                self.copyrightGradientEndPoint = UnitPoint.leading
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 30)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color(hex: "F5F5DC"), Color(hex: "FFFFFF")]), startPoint: startPoint, endPoint: endPoint)
                )
                .edgesIgnoringSafeArea(.all)
                .opacity(splashOpacity)
                .onAppear {
                    withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: true)) {
                        self.startPoint = UnitPoint(x: 1.0, y: 0.0)
                        self.endPoint = UnitPoint(x: 0.0, y: 1.0)
                    }

                    withAnimation(.easeIn(duration: 1.0)) {
                        self.splashOpacity = 1.0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 1.5)) {
                            self.splashOpacity = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.showSplash = false
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshLockEnabled"))) { _ in
            isRefreshLocked = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshLockDisabled"))) { _ in
            isRefreshLocked = false
        }
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        
        if hex.hasPrefix("#") {
            scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
        }
        
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

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
