import Foundation

// MARK: - 隐私辅助函数

/// 根据姓名长度，对客户姓名进行隐私模糊化处理。
/// - Parameter name: 客户的原始姓名。
/// - Returns: 处理后的模糊化姓名。
func processClientName(_ name: String) -> String {
    guard !name.isEmpty else { return "" }
    let characters = Array(name)
    let count = characters.count
    
    switch count {
    case 2:
        return "\(characters[0])*"
    case 3:
        return "\(characters[0])*\(characters[2])"
    case let c where c >= 4:
        return "\(characters[0])**\(characters[count - 1])"
    default:
        return name
    }
}
