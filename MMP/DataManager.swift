import Foundation
import Combine

struct ProfitResult: Codable {
    var absolute: Double
    var annualized: Double
}

struct FavoriteItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var url: String
}

class DataManager: ObservableObject {
    @Published var holdings: [FundHolding] = []
    @Published var favorites: [FavoriteItem] = []
    
    private let holdingsKey = "fundHoldings"
    private let favoritesKey = "Favorites"
    
    init() {
        loadData()
    }

    func loadData() {
        var decodedHoldings: [FundHolding] = []
        if let data = UserDefaults.standard.data(forKey: holdingsKey) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                decodedHoldings = try decoder.decode([FundHolding].self, from: data)
                print("DataManager: 持仓数据加载成功。总持仓数: \(decodedHoldings.count)")
            } catch {
                print("DataManager: 持仓数据加载失败或解码错误: \(error.localizedDescription)")
            }
        } else {
            print("DataManager: 没有找到 UserDefaults 中的持仓数据。")
        }
        
        var decodedFavorites: [FavoriteItem] = []
        if let savedFavorites = UserDefaults.standard.data(forKey: favoritesKey) {
            if let decodedData = try? JSONDecoder().decode([FavoriteItem].self, from: savedFavorites) {
                decodedFavorites = decodedData
                print("DataManager: 收藏夹数据加载成功。总收藏数: \(decodedFavorites.count)")
            } else {
                print("DataManager: 收藏夹数据解码失败。")
            }
        } else {
            print("DataManager: 没有找到 UserDefaults 中的收藏夹数据。")
        }

        self.holdings = decodedHoldings
        self.favorites = decodedFavorites
    }

    func saveData() {
        do {
            let holdingsEncoder = JSONEncoder()
            holdingsEncoder.dateEncodingStrategy = .iso8601
            let holdingsData = try holdingsEncoder.encode(self.holdings)
            UserDefaults.standard.set(holdingsData, forKey: holdingsKey)
            
            let favoritesEncoder = JSONEncoder()
            let favoritesData = try favoritesEncoder.encode(self.favorites)
            UserDefaults.standard.set(favoritesData, forKey: favoritesKey)
            
            print("DataManager: 所有数据保存成功。")
        } catch {
            print("DataManager: 数据保存失败或编码错误: \(error.localizedDescription)")
        }
    }

    func addHolding(_ holding: FundHolding) {
        var tempHoldings = self.holdings
        tempHoldings.append(holding)
        self.holdings = tempHoldings
        self.saveData()
        print("DataManager: 添加新持仓: \(holding.fundCode) - \(holding.clientName)")
    }
    
    func updateHolding(_ updatedHolding: FundHolding) {
        if let index = holdings.firstIndex(where: { $0.id == updatedHolding.id }) {
            var tempHoldings = self.holdings
            tempHoldings[index] = updatedHolding
            self.holdings = tempHoldings
            self.saveData()
            print("DataManager: 更新持仓: \(updatedHolding.fundCode) - \(updatedHolding.clientName)")
        }
    }
    
    func deleteHolding(at offsets: IndexSet) {
        var tempHoldings = self.holdings
        tempHoldings.remove(atOffsets: offsets)
        self.holdings = tempHoldings
        self.saveData()
        print("DataManager: 删除持仓。")
    }

    func togglePinStatus(forHoldingId id: UUID) {
        if let index = holdings.firstIndex(where: { $0.id == id }) {
            var tempHoldings = self.holdings
            tempHoldings[index].isPinned.toggle()
            if tempHoldings[index].isPinned {
                tempHoldings[index].pinnedTimestamp = Date()
            } else {
                tempHoldings[index].pinnedTimestamp = nil
            }
            self.holdings = tempHoldings
            self.saveData()
            print("DataManager: 持仓 \(tempHoldings[index].fundCode) 置顶状态切换为 \(tempHoldings[index].isPinned)。")
        }
    }

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
