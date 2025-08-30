import Foundation

struct FundHolding: Identifiable, Codable {
    var id = UUID()
    
    var clientName: String
    var clientID: String
    var fundCode: String
    var fundName: String = "未加载"
    var purchaseAmount: Double
    var purchaseShares: Double
    var purchaseDate: Date
    var remarks: String
    var currentNav: Double = 0.0
    var navDate: Date = Date()
    var isValid: Bool = false
    var isPinned: Bool = false
    var pinnedTimestamp: Date?
    var navReturn1m: Double?
    var navReturn3m: Double?
    var navReturn6m: Double?
    var navReturn1y: Double?
    var totalValue: Double {
        guard currentNav >= 0 && purchaseShares >= 0 else {
            return 0.0
        }
        return currentNav * purchaseShares
    }

    init(clientName: String, clientID: String = "", fundCode: String, purchaseAmount: Double, purchaseShares: Double, purchaseDate: Date, remarks: String = "", fundName: String = "未加载", currentNav: Double = 0.0, navDate: Date = Date(), isValid: Bool = false, isPinned: Bool = false, pinnedTimestamp: Date? = nil, navReturn1m: Double? = nil, navReturn3m: Double? = nil, navReturn6m: Double? = nil, navReturn1y: Double? = nil) {
        self.clientName = clientName
        self.clientID = clientID
        self.fundCode = fundCode
        self.purchaseAmount = purchaseAmount
        self.purchaseShares = purchaseShares
        self.purchaseDate = purchaseDate
        self.remarks = remarks
        self.fundName = fundName
        self.currentNav = currentNav
        self.navDate = navDate
        self.isValid = isValid
        self.isPinned = isPinned
        self.pinnedTimestamp = pinnedTimestamp
        self.navReturn1m = navReturn1m
        self.navReturn3m = navReturn3m
        self.navReturn6m = navReturn6m
        self.navReturn1y = navReturn1y
    }
}
