import SwiftUI
import CoreFoundation

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
    
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .environmentObject(fundService)
                .preferredColorScheme(themeMode.colorScheme)
        }
    }
}
