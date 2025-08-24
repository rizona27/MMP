import SwiftUI
import CoreFoundation

// 新增主题模式枚举，以供 MMPApp 使用
enum ThemeMode: String, CaseIterable, Identifiable {
    case light = "浅色"
    case dark = "深色"
    case system = "跟随系统"
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

@main
struct MMPApp: App {
    @StateObject private var dataManager = DataManager()
    @StateObject private var fundService = FundService()
    
    // 新增：使用 @AppStorage 读取保存的主题模式设置
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .environmentObject(fundService)
                // 新增：应用 themeMode 对应的 preferredColorScheme
                .preferredColorScheme(themeMode.colorScheme)
        }
    }
}
