import SwiftUI
import CoreFoundation

@main
struct MMPApp: App {
    @StateObject private var dataManager = DataManager()
    @StateObject private var fundService = FundService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .environmentObject(fundService)
                // 移除了 .onOpenURL 修饰符，因为不再处理外部 CSV 文件导入
                /*
                .onOpenURL { url in
                    print("MMPApp: 收到外部应用传入的 URL: \(url)")
                    handleIncomingURL(url)
                }
                */
        }
    }
    
    // 移除了处理传入 URL 的方法，因为它与 CSV 导入功能相关
    /*
    // MARK: - 处理传入的 URL (例如从微信分享的 CSV 文件)
    private func handleIncomingURL(_ url: URL) {
        // 1. 检查文件类型
        guard url.pathExtension.lowercased() == "csv" else {
            print("MMPApp: 错误：传入的文件不是 CSV 类型 (\(url.pathExtension))")
            return
        }
        
        // 2. 获取安全访问权限
        guard url.startAccessingSecurityScopedResource() else {
            print("MMPApp: 错误：无法获取文件安全访问权限")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // 3. 读取文件内容
        do {
            let data = try Data(contentsOf: url)
            print("MMPApp: 成功读取文件，大小: \(data.count) 字节")
            
            // 4. 尝试解码为 UTF-8
            if let csvString = String(data: data, encoding: .utf8) {
                // UTF-8 解码成功
                dataManager.processCSVData(csvString: csvString)
            } else {
                // 5. 尝试 GB18030 编码 (中文常用)
                let cfEncoding = CFStringEncodings.GB_18030_2000
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
                let gb18030Encoding = String.Encoding(rawValue: nsEncoding)
                
                if let gbkString = String(data: data, encoding: gb18030Encoding) {
                    print("MMPApp: 使用 GB18030 编码成功解码文件")
                    dataManager.processCSVData(csvString: gbkString)
                } else {
                    print("MMPApp: 错误：无法解码文件内容")
                    // 可以在这里添加用户提示，例如通过环境对象显示错误信息
                }
            }
        } catch {
            print("MMPApp: 读取文件失败: \(error.localizedDescription)")
        }
    }
    */
}
