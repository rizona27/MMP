// FundService.swift
import Foundation
import Combine

// MARK: - 基金API枚举
enum FundAPI: String, CaseIterable, Identifiable {
    case eastmoney = "天天基金"
    case tencent = "腾讯财经"
    case fund123 = "蚂蚁基金"
    case fund10jqka = "同花顺"

    var id: String { self.rawValue }
}

// 定义一个用于缓存的结构，包含基金数据和缓存时间
struct CachedFundHolding: Codable {
    let holding: FundHolding
    let timestamp: Date
}

// 日志类型枚举
enum LogType: String {
    case info = "信息"
    case success = "成功"
    case error = "错误"
    case warning = "警告"
    case network = "网络"
    case cache = "缓存"
}

// 日志条目结构
struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let type: LogType
    let timestamp: Date
}

class FundService: ObservableObject {
    @Published var logMessages: [LogEntry] = []
    
    private var fundCache: [String: CachedFundHolding] = [:]
    private let cacheQueue = DispatchQueue(label: "com.mmp.fundcache")
    private let userDefaultsKey = "fundServiceCache"
    
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60

    // 用户选择的API
    private var selectedFundAPI: FundAPI {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "selectedFundAPI"),
               let api = FundAPI(rawValue: rawValue) {
                return api
            }
            return .eastmoney // 默认值
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedFundAPI")
        }
    }

    static let dateFormatterYYYYMMDD: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    static let dateFormatterYYYY_MM_DD: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let calendar = Calendar.current

    init() {
        cacheQueue.async {
            self.loadCacheFromUserDefaults()
        }
    }

    // 主要的基金信息获取方法 - 添加 useOnlyEastmoney 参数
    func fetchFundInfo(code: String, useOnlyEastmoney: Bool = false) async -> FundHolding {
        addLog("开始查询基金代码: \(code)，使用API: \(selectedFundAPI.rawValue)" + (useOnlyEastmoney ? " (仅使用天天基金)" : ""), type: .network)
        
        // 1. 检查主缓存
        if let cachedData = getFromCache(code: code) {
            let isSameNavDay = calendar.isDate(cachedData.holding.navDate, inSameDayAs: Date())
            let isCacheFresh = !isCacheExpired(cachedData)
            
            if isSameNavDay && isCacheFresh {
                addLog("基金代码 \(code): 从主缓存中获取数据，净值日期为今日且缓存未过期。", type: .cache)
                return cachedData.holding
            } else {
                addLog("基金代码 \(code): 主缓存数据净值日期非今日或缓存已过期，尝试更新。", type: .cache)
            }
        }
        
        // 2. 主缓存不存在或已过期，从 API 获取
        addLog("基金代码 \(code): 主缓存不可用，开始尝试从API获取。", type: .network)
        
        var fetchedHolding: FundHolding?
        
        // 根据用户选择的API获取数据
        switch selectedFundAPI {
        case .eastmoney:
            fetchedHolding = await fetchFromEastmoney(code: code)
        case .tencent:
            fetchedHolding = await fetchFromTencent(code: code)
        case .fund123:
            fetchedHolding = await fetchFromFund123(code: code)
        case .fund10jqka:
            fetchedHolding = await fetchFromFund10jqka(code: code)
        }
        
        var finalHolding = FundHolding(
            clientName: "", clientID: "", fundCode: code,
            purchaseAmount: 0, purchaseShares: 0, purchaseDate: Date(),
            remarks: "", fundName: "N/A", currentNav: 0, navDate: Date(),
            isValid: false, isPinned: false, pinnedTimestamp: nil,
            navReturn1m: nil, navReturn3m: nil, navReturn6m: nil, navReturn1y: nil
        )
        
        if let dataFromAPI = fetchedHolding, dataFromAPI.isValid {
            finalHolding = dataFromAPI
            
            // 如果使用天天基金API，尝试获取收益率数据
            if selectedFundAPI == .eastmoney {
                addLog("基金代码 \(code): 尝试获取收益率数据", type: .network)
                let returnsData = await fetchReturnsFromEastmoney(code: code)
                
                // 更新收益率数据
                finalHolding.navReturn1m = returnsData.navReturn1m
                finalHolding.navReturn3m = returnsData.navReturn3m
                finalHolding.navReturn6m = returnsData.navReturn6m
                finalHolding.navReturn1y = returnsData.navReturn1y
                
                addLog("基金代码 \(code): 收益率数据获取完成", type: .success)
            }
            
            saveToCache(holding: finalHolding)
            addLog("基金代码 \(code): 成功获取有效数据并更新主缓存。", type: .success)
        } else if !useOnlyEastmoney {
            // 如果首选API失败，并且允许使用备用API，则尝试其他API作为备用
            addLog("基金代码 \(code): 首选API失败，尝试备用API。", type: .warning)
            
            for api in FundAPI.allCases where api != selectedFundAPI {
                addLog("基金代码 \(code): 尝试备用API: \(api.rawValue)", type: .network)
                
                var backupHolding: FundHolding?
                switch api {
                case .eastmoney:
                    backupHolding = await fetchFromEastmoney(code: code)
                case .tencent:
                    backupHolding = await fetchFromTencent(code: code)
                case .fund123:
                    backupHolding = await fetchFromFund123(code: code)
                case .fund10jqka:
                    backupHolding = await fetchFromFund10jqka(code: code)
                }
                
                if let validBackup = backupHolding, validBackup.isValid {
                    finalHolding = validBackup
                    
                    // 如果使用天天基金API，尝试获取收益率数据
                    if api == .eastmoney {
                        addLog("基金代码 \(code): 尝试获取收益率数据", type: .network)
                        let returnsData = await fetchReturnsFromEastmoney(code: code)
                        
                        // 更新收益率数据
                        finalHolding.navReturn1m = returnsData.navReturn1m
                        finalHolding.navReturn3m = returnsData.navReturn3m
                        finalHolding.navReturn6m = returnsData.navReturn6m
                        finalHolding.navReturn1y = returnsData.navReturn1y
                        
                        addLog("基金代码 \(code): 收益率数据获取完成", type: .success)
                    }
                    
                    saveToCache(holding: finalHolding)
                    addLog("基金代码 \(code): 备用API \(api.rawValue) 成功获取数据。", type: .success)
                    break
                }
            }
            
            if !finalHolding.isValid, let cachedData = getFromCache(code: code) {
                addLog("基金代码 \(code): 所有API都失败，返回旧的主缓存数据。", type: .error)
                finalHolding = cachedData.holding
                finalHolding.isValid = !isCacheExpired(cachedData)
            }
        } else {
            // 如果只使用天天基金API且获取失败，直接返回无效数据
            addLog("基金代码 \(code): 天天基金API失败且不允许使用备用API。", type: .error)
        }
        
        return finalHolding
    }

    // MARK: - 各个API的具体实现
    
    // 天天基金API
    private func fetchFromEastmoney(code: String) async -> FundHolding {
        addLog("基金代码 \(code): 尝试从天天基金API获取数据", type: .network)
        
        let urlString = "https://fundgz.1234567.com.cn/js/\(code).js"
        guard let url = URL(string: urlString) else {
            addLog("基金代码 \(code): 天天基金API URL无效", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                addLog("基金代码 \(code): 天天基金API响应状态码非200", type: .error)
                return FundHolding.invalid(fundCode: code)
            }
            
            if let string = String(data: data, encoding: .utf8), string.starts(with: "jsonpgz") {
                // 解析JSONP格式数据
                let jsonString = string
                    .replacingOccurrences(of: "jsonpgz(", with: "")
                    .replacingOccurrences(of: ");", with: "")
                
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    var holding = FundHolding.invalid(fundCode: code)
                    holding.fundName = json["name"] as? String ?? "N/A"
                    
                    if let jzrq = json["jzrq"] as? String,
                       let date = FundService.dateFormatterYYYY_MM_DD.date(from: jzrq) {
                        holding.navDate = date
                    }
                    
                    if let dwjz = json["dwjz"] as? String, let value = Double(dwjz) {
                        holding.currentNav = value
                    }
                    
                    if let gsz = json["gsz"] as? String, let value = Double(gsz) {
                        // 使用估值作为当前净值
                        holding.currentNav = value
                    }
                    
                    holding.isValid = holding.fundName != "N/A" && holding.currentNav > 0
                    
                    if holding.isValid {
                        addLog("基金代码 \(code): 天天基金API解析成功", type: .success)
                    } else {
                        addLog("基金代码 \(code): 天天基金API数据无效", type: .error)
                    }
                    
                    return holding
                }
            }
            
            addLog("基金代码 \(code): 天天基金API数据解析失败", type: .error)
            return FundHolding.invalid(fundCode: code)
        } catch {
            addLog("基金代码 \(code): 天天基金API请求失败: \(error.localizedDescription)", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
    }
    
    // 从天天基金获取收益率数据
    private func fetchReturnsFromEastmoney(code: String) async -> (navReturn1m: Double?, navReturn3m: Double?, navReturn6m: Double?, navReturn1y: Double?) {
        addLog("基金代码 \(code): 尝试从天天基金获取收益率数据", type: .network)
        
        let urlString = "https://fund.eastmoney.com/pingzhongdata/\(code).js"
        guard let url = URL(string: urlString) else {
            addLog("基金代码 \(code): 天天基金收益率API URL无效", type: .error)
            return (nil, nil, nil, nil)
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                addLog("基金代码 \(code): 天天基金收益率API响应状态码非200", type: .error)
                return (nil, nil, nil, nil)
            }
            
            guard let jsString = String(data: data, encoding: .utf8) else {
                addLog("基金代码 \(code): 天天基金收益率API数据编码失败", type: .error)
                return (nil, nil, nil, nil)
            }
            
            var navReturn1m: Double? = nil
            var navReturn3m: Double? = nil
            var navReturn6m: Double? = nil
            var navReturn1y: Double? = nil
            
            // 修正正则表达式以匹配正确的变量名
            let regex = try NSRegularExpression(pattern: "syl_(\\d+[yn])\\s*=\\s*\"([^\"]*)\"", options: [])
            let range = NSRange(jsString.startIndex..<jsString.endIndex, in: jsString)
            
            regex.enumerateMatches(in: jsString, options: [], range: range) { match, _, _ in
                guard let match = match, match.numberOfRanges == 3 else { return }
                
                let keyRange = match.range(at: 1)
                let valueRange = match.range(at: 2)
                
                guard let keySwiftRange = Range(keyRange, in: jsString),
                      let valueSwiftRange = Range(valueRange, in: jsString) else {
                    return
                }
                
                let key = String(jsString[keySwiftRange])
                let valueString = String(jsString[valueSwiftRange])
                
                if let value = Double(valueString) {
                    // 将捕获的键值对赋给对应的变量
                    switch key {
                    case "1y":
                        navReturn1m = value
                    case "3y":
                        navReturn3m = value
                    case "6y":
                        navReturn6m = value
                    case "1n":
                        navReturn1y = value
                    default:
                        break
                    }
                }
            }
            
            addLog("基金代码 \(code): 收益率数据解析完成: 1月=\(navReturn1m ?? 0), 3月=\(navReturn3m ?? 0), 6月=\(navReturn6m ?? 0), 1年=\(navReturn1y ?? 0)", type: .success)
            return (navReturn1m, navReturn3m, navReturn6m, navReturn1y)
            
        } catch {
            addLog("基金代码 \(code): 天天基金收益率API请求或正则解析失败: \(error.localizedDescription)", type: .error)
            return (nil, nil, nil, nil)
        }
    }
    
    // 腾讯财经API
    private func fetchFromTencent(code: String) async -> FundHolding {
        addLog("基金代码 \(code): 尝试从腾讯财经API获取数据", type: .network)
        
        let urlString = "https://web.ifzq.gtimg.cn/fund/newfund/fundSsgz/getSsgz?app=web&symbol=jj\(code)"
        guard let url = URL(string: urlString) else {
            addLog("基金代码 \(code): 腾讯财经API URL无效", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                addLog("基金代码 \(code): 腾讯财经API响应状态码非200", type: .error)
                return FundHolding.invalid(fundCode: code)
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let status = dataDict["code"] as? Int, status != -1,
               let list = dataDict["data"] as? [[Any]],
               let lastData = list.last,
               lastData.count >= 2,
               let ssgsz = lastData[1] as? String {
                
                var holding = FundHolding.invalid(fundCode: code)
                
                // 获取基金名称和净值日期
                let detailUrlString = "https://gu.qq.com/jj\(code)"
                if let detailUrl = URL(string: detailUrlString) {
                    do {
                        let (htmlData, _) = try await URLSession.shared.data(from: detailUrl)
                        if let htmlString = String(data: htmlData, encoding: .utf8) {
                            // 使用正则表达式提取基金名称
                            let nameRegex = try NSRegularExpression(pattern: "<title>([^<]+)</title>", options: [])
                            let matches = nameRegex.matches(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.count))
                            
                            if let match = matches.first, match.numberOfRanges > 1 {
                                let range = Range(match.range(at: 1), in: htmlString)!
                                holding.fundName = String(htmlString[range])
                            }
                        }
                    } catch {
                        addLog("基金代码 \(code): 获取基金详情失败: \(error.localizedDescription)", type: .error)
                    }
                }
                
                holding.navDate = Date()
                if let gszValue = Double(ssgsz) {
                    holding.currentNav = gszValue
                }
                
                holding.isValid = holding.fundName != "N/A" && holding.currentNav > 0
                
                if holding.isValid {
                    addLog("基金代码 \(code): 腾讯财经API解析成功", type: .success)
                } else {
                    addLog("基金代码 \(code): 腾讯财经API数据无效", type: .error)
                }
                
                return holding
            }
            
            addLog("基金代码 \(code): 腾讯财经API数据解析失败", type: .error)
            return FundHolding.invalid(fundCode: code)
        } catch {
            addLog("基金代码 \(code): 腾讯财经API请求失败: \(error.localizedDescription)", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
    }
    
    // 蚂蚁基金API
    private func fetchFromFund123(code: String) async -> FundHolding {
        addLog("基金代码 \(code): 尝试从蚂蚁基金API获取数据", type: .network)
        
        let urlString = "https://www.fund123.cn/matiaria?fundCode=\(code)"
        guard let url = URL(string: urlString) else {
            addLog("基金代码 \(code): 蚂蚁基金API URL无效", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                addLog("基金代码 \(code): 蚂蚁基金API响应状态码非200", type: .error)
                return FundHolding.invalid(fundCode: code)
            }
            
            if let htmlString = String(data: data, encoding: .utf8) {
                // 使用正则表达式提取基金信息
                var holding = FundHolding.invalid(fundCode: code)
                
                // 提取基金名称
                let nameRegex = try NSRegularExpression(pattern: "fundNameAbbr[^']+'([^']+)'", options: [])
                if let nameMatch = nameRegex.firstMatch(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.count)) {
                    let range = Range(nameMatch.range(at: 1), in: htmlString)!
                    holding.fundName = String(htmlString[range])
                }
                
                // 提取净值
                let navRegex = try NSRegularExpression(pattern: "netValue[^']+'([^']+)'", options: [])
                if let navMatch = navRegex.firstMatch(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.count)) {
                    let range = Range(navMatch.range(at: 1), in: htmlString)!
                    if let navValue = Double(String(htmlString[range])) {
                        holding.currentNav = navValue
                    }
                }
                
                // 提取净值日期
                let dateRegex = try NSRegularExpression(pattern: "netValueDate[^']+'([^']+)'", options: [])
                if let dateMatch = dateRegex.firstMatch(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.count)) {
                    let range = Range(dateMatch.range(at: 1), in: htmlString)!
                    let dateStr = String(htmlString[range])
                    let currentYear = Calendar.current.component(.year, from: Date())
                    if let date = FundService.dateFormatterYYYY_MM_DD.date(from: "\(currentYear)-\(dateStr)") {
                        holding.navDate = date
                    }
                }
                
                holding.isValid = holding.fundName != "N/A" && holding.currentNav > 0
                
                if holding.isValid {
                    addLog("基金代码 \(code): 蚂蚁基金API解析成功", type: .success)
                } else {
                    addLog("基金代码 \(code): 蚂蚁基金API数据无效", type: .error)
                }
                
                return holding
            }
            
            addLog("基金代码 \(code): 蚂蚁基金API数据解析失败", type: .error)
            return FundHolding.invalid(fundCode: code)
        } catch {
            addLog("基金代码 \(code): 蚂蚁基金API请求失败: \(error.localizedDescription)", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
    }
    
    // 同花顺API
    private func fetchFromFund10jqka(code: String) async -> FundHolding {
        addLog("基金代码 \(code): 尝试从同花顺API获取数据", type: .network)
        
        let urlString = "https://fund.10jqka.com.cn/data/client/myfund/\(code)"
        guard let url = URL(string: urlString) else {
            addLog("基金代码 \(code): 同花顺API URL无效", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                addLog("基金代码 \(code): 同花顺API响应状态码非200", type: .error)
                return FundHolding.invalid(fundCode: code)
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]],
               let fundData = dataArray.first {
                
                var holding = FundHolding.invalid(fundCode: code)
                holding.fundName = fundData["name"] as? String ?? "N/A"
                
                if let netValue = fundData["net"] as? String, let value = Double(netValue) {
                    holding.currentNav = value
                }
                
                if let endDate = fundData["enddate"] as? String {
                    if let date = FundService.dateFormatterYYYY_MM_DD.date(from: endDate) {
                        holding.navDate = date
                    }
                }
                
                holding.isValid = holding.fundName != "N/A" && holding.currentNav > 0
                
                if holding.isValid {
                    addLog("基金代码 \(code): 同花顺API解析成功", type: .success)
                } else {
                    addLog("基金代码 \(code): 同花顺API数据无效", type: .error)
                }
                
                return holding
            }
            
            addLog("基金代码 \(code): 同花顺API数据解析失败", type: .error)
            return FundHolding.invalid(fundCode: code)
        } catch {
            addLog("基金代码 \(code): 同花顺API请求失败: \(error.localizedDescription)", type: .error)
            return FundHolding.invalid(fundCode: code)
        }
    }

    // MARK: - 缓存相关方法
    private func saveToCache(holding: FundHolding) {
        cacheQueue.sync {
            let cachedData = CachedFundHolding(holding: holding, timestamp: Date())
            fundCache[holding.fundCode] = cachedData
            persistCacheToUserDefaults()
            addLog("基金代码 \(holding.fundCode): 数据已存入主缓存。", type: .cache)
        }
    }

    private func getFromCache(code: String) -> CachedFundHolding? {
        return cacheQueue.sync {
            fundCache[code]
        }
    }

    private func isCacheExpired(_ cachedData: CachedFundHolding) -> Bool {
        return Date().timeIntervalSince(cachedData.timestamp) > cacheExpirationInterval
    }
    
    private func loadCacheFromUserDefaults() {
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey) {
            do {
                let decoder = JSONDecoder()
                self.fundCache = try decoder.decode([String: CachedFundHolding].self, from: savedData)
                addLog("主缓存已从本地加载。", type: .cache)
            } catch {
                addLog("加载主缓存失败: \(error.localizedDescription)", type: .error)
            }
        } else {
            addLog("UserDefaults 中没有找到主缓存数据。", type: .info)
        }
    }
    
    private func persistCacheToUserDefaults() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self.fundCache)
            UserDefaults.standard.set(data, forKey: self.userDefaultsKey)
        } catch {
            addLog("持久化主缓存失败: \(error.localizedDescription)", type: .error)
        }
    }

    // 日志记录方法
    internal func addLog(_ message: String, type: LogType) {
        DispatchQueue.main.async {
            let logEntry = LogEntry(message: message, type: type, timestamp: Date())
            self.logMessages.append(logEntry)
            if self.logMessages.count > 100 {
                self.logMessages.removeFirst(50)
            }
        }
    }
    
    // 新增：从pingzhongdata接口获取基金详情（包括名称和收益率）
    func fetchFundDetailsFromEastmoney(code: String) async -> (fundName: String, returns: (navReturn1m: Double?, navReturn3m: Double?, navReturn6m: Double?, navReturn1y: Double?)) {
        addLog("基金代码 \(code): 尝试从天天基金获取详情数据", type: .network)
        
        let urlString = "https://fund.eastmoney.com/pingzhongdata/\(code).js"
        guard let url = URL(string: urlString) else {
            addLog("基金代码 \(code): 天天基金详情API URL无效", type: .error)
            return (fundName: "N/A", returns: (nil, nil, nil, nil))
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                addLog("基金代码 \(code): 天天基金详情API响应状态码非200", type: .error)
                return (fundName: "N/A", returns: (nil, nil, nil, nil))
            }
            
            guard let jsString = String(data: data, encoding: .utf8) else {
                addLog("基金代码 \(code): 天天基金详情API数据编码失败", type: .error)
                return (fundName: "N/A", returns: (nil, nil, nil, nil))
            }
            
            var fundName = "N/A"
            var navReturn1m: Double? = nil
            var navReturn3m: Double? = nil
            var navReturn6m: Double? = nil
            var navReturn1y: Double? = nil
            
            // 使用正则表达式提取基金名称
            let namePattern = "fS_name\\s*=\\s*\"([^\"]*)\""
            if let nameRange = jsString.range(of: namePattern, options: .regularExpression) {
                let nameString = String(jsString[nameRange])
                if let quoteRange = nameString.range(of: "\"[^\"]*\"", options: .regularExpression) {
                    fundName = String(nameString[quoteRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            
            // 原有的收益率提取逻辑
            let regex = try NSRegularExpression(pattern: "syl_(\\d+[yn])\\s*=\\s*\"([^\"]*)\"", options: [])
            let range = NSRange(jsString.startIndex..<jsString.endIndex, in: jsString)
            
            regex.enumerateMatches(in: jsString, options: [], range: range) { match, _, _ in
                guard let match = match, match.numberOfRanges == 3 else { return }
                
                let keyRange = match.range(at: 1)
                let valueRange = match.range(at: 2)
                
                guard let keySwiftRange = Range(keyRange, in: jsString),
                      let valueSwiftRange = Range(valueRange, in: jsString) else {
                    return
                }
                
                let key = String(jsString[keySwiftRange])
                let valueString = String(jsString[valueSwiftRange])
                
                if let value = Double(valueString) {
                    switch key {
                    case "1y":
                        navReturn1m = value
                    case "3y":
                        navReturn3m = value
                    case "6y":
                        navReturn6m = value
                    case "1n":
                        navReturn1y = value
                    default:
                        break
                    }
                }
            }
            
            addLog("基金代码 \(code): 详情数据解析完成: 名称=\(fundName), 1月=\(navReturn1m ?? 0), 3月=\(navReturn3m ?? 0), 6月=\(navReturn6m ?? 0), 1年=\(navReturn1y ?? 0)", type: .success)
            return (fundName: fundName, returns: (navReturn1m, navReturn3m, navReturn6m, navReturn1y))
            
        } catch {
            addLog("基金代码 \(code): 天天基金详情API请求或正则解析失败: \(error.localizedDescription)", type: .error)
            return (fundName: "N/A", returns: (nil, nil, nil, nil))
        }
    }
}

// FundHolding扩展，用于创建无效的基金持仓
extension FundHolding {
    static func invalid(fundCode: String) -> FundHolding {
        return FundHolding(
            clientName: "", clientID: "", fundCode: fundCode,
            purchaseAmount: 0, purchaseShares: 0, purchaseDate: Date(),
            remarks: "", fundName: "N/A", currentNav: 0, navDate: Date(),
            isValid: false, isPinned: false, pinnedTimestamp: nil,
            navReturn1m: nil, navReturn3m: nil, navReturn6m: nil, navReturn1y: nil
        )
    }
}
