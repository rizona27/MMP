import Foundation

struct FundHolding: Identifiable, Codable {
    var id = UUID()
    
    // 客户信息
    var clientName: String // 客户名 (必填)
    var clientID: String // 客户号 (选填)
    
    // 基金信息
    var fundCode: String // 基金代码 (必填)
    var fundName: String = "未加载" // 基金名称
    
    // 持仓信息
    var purchaseAmount: Double // 购买金额 (必填)
    var purchaseShares: Double // 购买份额 (必填) - 这是直接输入的份额
    var purchaseDate: Date // 购买日期 (必填)
    var remarks: String // 备注 (选填)
    
    // 净值信息
    var currentNav: Double = 0.0 // 当前净值
    var navDate: Date = Date() // 净值日期
    var isValid: Bool = false // 标记数据是否有效/成功获取
    
    // 置顶状态
    var isPinned: Bool = false // 是否置顶
    var pinnedTimestamp: Date? // 置顶时间戳

    // 新增的收益率属性
    var navReturn1m: Double? // 近1个月收益率
    var navReturn3m: Double? // 近3个月收益率
    var navReturn6m: Double? // 近6个月收益率
    var navReturn1y: Double? // 近1年收益率
    
    // 计算属性，用于计算当前总市值
    var totalValue: Double {
        // 确保 currentNav 和 purchaseShares 都是有效数字
        guard currentNav >= 0 && purchaseShares >= 0 else {
            return 0.0 // 如果数据无效，返回0
        }
        return currentNav * purchaseShares
    }

    // 自定义初始化方法 - 已调整参数顺序以匹配调用
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
