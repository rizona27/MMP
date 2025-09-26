import Foundation

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
