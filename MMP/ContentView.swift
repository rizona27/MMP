import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var fundService = FundService()

    @State private var showSplash = true
    @State private var selectedTab = 0
    
    // 启动动画状态变量
    @State private var splashOpacity: Double = 1.0
    @State private var mainTextOpacity: Double = 0.0
    @State private var subtitleOpacity: Double = 0.0
    @State private var copyrightOpacity: Double = 0.0
    
    @State private var mainTextOffset: CGFloat = 10.0
    @State private var subtitleOffset: CGFloat = 8.0
    
    // 高光动画状态
    @State private var highlightPosition: CGFloat = -1.0
    @State private var highlightOpacity: Double = 0.0
    
    // 光晕动画状态
    @State private var glowScale: CGFloat = 0.7
    @State private var glowOpacity: Double = 0.0
    @State private var glowRotation: Double = 0.0
    @State private var glowOffset: CGSize = CGSize(width: -100, height: -100)
    
    // 转场效果状态
    @State private var splashBlur: CGFloat = 0.0
    @State private var splashScale: CGFloat = 1.0

    @State private var isRefreshLocked = false

    var body: some View {
        ZStack {
            // 主程序界面
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
            .animation(.easeIn(duration: 0.6), value: showSplash)

            if showSplash {
                ZStack {
                    // 基础背景
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "F8F5F0"),
                                    Color(hex: "F0ECE5"),
                                    Color(hex: "F8F5F0")
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .edgesIgnoringSafeArea(.all)
                    
                    // 动态光晕效果
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color(hex: "E8D5C4").opacity(0.3),
                                        Color(hex: "F0ECE5").opacity(0.15),
                                        Color.clear
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 150 + CGFloat(index) * 60
                                )
                            )
                            .frame(
                                width: 250 + CGFloat(index) * 100,
                                height: 250 + CGFloat(index) * 100
                            )
                            .scaleEffect(glowScale * (1.0 - CGFloat(index) * 0.1))
                            .opacity(glowOpacity * (1.0 - Double(index) * 0.2))
                            .rotationEffect(.degrees(glowRotation * Double(index + 1) * 0.3))
                            .offset(glowOffset)
                            .blur(radius: 15 + CGFloat(index) * 5)
                    }
                    
                    // 文字内容层
                    VStack(alignment: .center, spacing: 12) {
                        Spacer()
                        
                        // 主标题
                        VStack(alignment: .center, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Less")
                                    .font(.system(size: 46, weight: .light, design: .serif))
                                    .foregroundColor(Color(hex: "5D4037"))
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                
                                Text("is")
                                    .font(.system(size: 32, weight: .light, design: .serif))
                                    .foregroundColor(Color(hex: "5D4037"))
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                            }
                            
                            Text("More.")
                                .font(.system(size: 60, weight: .semibold, design: .serif))
                                .foregroundColor(Color(hex: "3E2723"))
                                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
                        }
                        .opacity(mainTextOpacity)
                        .offset(y: mainTextOffset)
                        
                        // 副标题
                        Text("Finding Abundance Through Subtraction")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color(hex: "6D4C41").opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 20)
                            .opacity(subtitleOpacity)
                            .offset(y: subtitleOffset)

                        Spacer()

                        // 版权信息
                        VStack(spacing: 4) {
                            Text("专注 · 价值")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(Color(hex: "795548").opacity(0.6))
                            
                            Text("Copyright © 2025 Rizona")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(Color(hex: "795548").opacity(0.5))
                        }
                        .opacity(copyrightOpacity)
                        .padding(.bottom, 50)
                        .overlay(
                            // 高光扫过效果
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.clear,
                                            Color.white.opacity(0.4),
                                            Color.white.opacity(0.6),
                                            Color.white.opacity(0.4),
                                            Color.clear
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 80)
                                .offset(x: highlightPosition * 200)
                                .opacity(highlightOpacity)
                                .blendMode(.plusLighter)
                                .mask(
                                    VStack(spacing: 4) {
                                        Text("专注 · 价值")
                                            .font(.system(size: 13, weight: .light))
                                        
                                        Text("© 2025 Rizona Developed")
                                            .font(.system(size: 11, weight: .light))
                                    }
                                )
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
                }
                .opacity(splashOpacity)
                .scaleEffect(splashScale)
                .blur(radius: splashBlur)
                .onAppear {
                    startNaturalAnimation()
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
    
    private func startNaturalAnimation() {
        // 重置所有状态
        splashOpacity = 1.0
        mainTextOpacity = 0.0
        subtitleOpacity = 0.0
        copyrightOpacity = 0.0
        mainTextOffset = 10.0
        subtitleOffset = 8.0
        glowScale = 0.7
        glowOpacity = 0.0
        glowRotation = 0.0
        glowOffset = CGSize(width: -100, height: -100)
        splashBlur = 0.0
        splashScale = 1.0
        
        // 光晕动画
        withAnimation(.easeOut(duration: 2.5)) {
            glowScale = 1.4
            glowOpacity = 0.4
            glowOffset = CGSize(width: 30, height: 30)
        }
        
        // 光晕旋转
        withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            glowRotation = 360
        }
        
        // 主文字淡入和轻微上移
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 1.2)) {
                mainTextOpacity = 1.0
                mainTextOffset = 0.0
            }
        }
        
        // 副标题延迟淡入
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 1.0)) {
                subtitleOpacity = 1.0
                subtitleOffset = 0.0
            }
        }
        
        // 版权信息最后淡入
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.8)) {
                copyrightOpacity = 1.0
            }
            
            // 高光扫过动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 0.1)) {
                    highlightOpacity = 1.0
                }
                
                withAnimation(.easeInOut(duration: 0.8)) {
                    highlightPosition = 1.0
                }
                
                // 高光淡出
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        highlightOpacity = 0.0
                    }
                }
            }
        }
        
        // 整体转场效果 - 使用模糊和缩放淡出
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            // 光晕淡出
            withAnimation(.easeIn(duration: 0.8)) {
                glowOpacity = 0.0
            }
            
            // 启动画面转场效果 - 模糊和轻微缩小
            withAnimation(.easeOut(duration: 1.2)) {
                splashOpacity = 0.0
                splashBlur = 8.0
                splashScale = 0.98
            }
            
            // 延迟一点再切换主界面
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeIn(duration: 0.3)) {
                    showSplash = false
                }
            }
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
