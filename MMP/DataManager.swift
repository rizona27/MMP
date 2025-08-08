import Foundation
import Combine

// 注意：本文件中不应包含 FundHolding 和 FundService 的定义，
// 它们应在项目的其他文件中定义，例如 FundModels.swift。

// 定义一个结构体来存储收益计算结果
struct ProfitResult: Codable {
    var absolute: Double // 绝对收益
    var annualized: Double // 年化收益率
}

// 定义 FavoriteItem 结构体，用于存储收藏信息
// **注意：这个结构体只在这里定义一次**
struct FavoriteItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var url: String
}

class DataManager: ObservableObject {
    @Published var holdings: [FundHolding] = [] {
        didSet {
            saveData()
        }
    }
    // 新增用于存储收藏夹数据的数组
    @Published var favorites: [FavoriteItem] = [] {
        didSet {
            saveData()
        }
    }
    
    private let holdingsKey = "fundHoldings"
    private let favoritesKey = "Favorites" // 新增收藏夹数据的 UserDefaults Key
    
    init() {
        loadData()
    }
    
    // 加载数据
    func loadData() {
        // 加载持仓数据
        if let data = UserDefaults.standard.data(forKey: holdingsKey) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                holdings = try decoder.decode([FundHolding].self, from: data)
                print("DataManager: 数据加载成功。总持仓数: \(holdings.count)")
            } catch {
                print("DataManager: 数据加载失败或解码错误: \(error.localizedDescription)")
                holdings = []
            }
        } else {
            print("DataManager: 没有找到 UserDefaults 中的数据。")
        }
        
        // 加载收藏夹数据
        if let savedFavorites = UserDefaults.standard.data(forKey: favoritesKey) {
            if let decodedFavorites = try? JSONDecoder().decode([FavoriteItem].self, from: savedFavorites) {
                favorites = decodedFavorites
                return
            }
        }
        print("DataManager: 没有找到 UserDefaults 中的收藏夹数据。")
        favorites = []
    }
    
    // 保存数据
    func saveData() {
        // 保存持仓数据
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(holdings)
            UserDefaults.standard.set(data, forKey: holdingsKey)
            print("DataManager: 持仓数据保存成功。")
        } catch {
            print("DataManager: 持仓数据保存失败或编码错误: \(error.localizedDescription)")
        }
        
        // 保存收藏夹数据
        if let encodedFavorites = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encodedFavorites, forKey: favoritesKey)
            print("DataManager: 收藏夹数据保存成功。")
        }
    }
    
    // 添加新的持仓
    func addHolding(_ holding: FundHolding) {
        holdings.append(holding)
        print("DataManager: 添加新持仓: \(holding.fundCode) - \(holding.clientName)")
    }
    
    // 更新持仓
    func updateHolding(_ updatedHolding: FundHolding) {
        if let index = holdings.firstIndex(where: { $0.id == updatedHolding.id }) {
            holdings[index] = updatedHolding
            print("DataManager: 更新持仓: \(updatedHolding.fundCode) - \(updatedHolding.clientName)")
        }
    }
    
    // 删除持仓
    func deleteHolding(at offsets: IndexSet) {
        holdings.remove(atOffsets: offsets)
        print("DataManager: 删除持仓。")
    }
    
    // 切换基金的置顶状态
    func togglePinStatus(forHoldingId id: UUID) {
        if let index = holdings.firstIndex(where: { $0.id == id }) {
            holdings[index].isPinned.toggle()
            if holdings[index].isPinned {
                holdings[index].pinnedTimestamp = Date()
            } else {
                holdings[index].pinnedTimestamp = nil
            }
            print("DataManager: 持仓 \(holdings[index].fundCode) 置顶状态切换为 \(holdings[index].isPinned)。")
        }
    }

    // 计算单个基金的收益 (绝对收益和年化收益率)
    func calculateProfit(for holding: FundHolding) -> ProfitResult {
        guard holding.purchaseShares > 0 && holding.currentNav >= 0 && holding.purchaseAmount > 0 else {
            return ProfitResult(absolute: 0.0, annualized: 0.0)
        }

        let currentMarketValue = holding.currentNav * holding.purchaseShares
        let absoluteProfit = currentMarketValue - holding.purchaseAmount

        let calendar = Calendar.current
        let holdingStartDate = calendar.startOfDay(for: holding.purchaseDate)
        let holdingEndDate = calendar.startOfDay(for: holding.navDate)

        guard let days = calendar.dateComponents([.day], from: holdingStartDate, to: holdingEndDate).day else {
            return ProfitResult(absolute: absoluteProfit, annualized: 0.0)
        }
        
        let holdingDays = Double(days) + 1.0
        
        guard holdingDays > 0 else {
            return ProfitResult(absolute: absoluteProfit, annualized: 0.0)
        }

        let annualizedReturn = (absoluteProfit / holding.purchaseAmount) / holdingDays * 365.0
        
        return ProfitResult(absolute: absoluteProfit, annualized: annualizedReturn * 100)
    }
}
