import Foundation
import Combine

// 定义一个用于缓存的结构，包含基金数据和缓存时间
struct CachedFundHolding: Codable {
    let holding: FundHolding
    let timestamp: Date // 缓存时间戳
}

class FundService: ObservableObject {
    // 硬编码的 API 地址列表
    private let apiURLs = [
        "https://fundgz.1234567.com.cn/js/{code}.js", // API1
        "https://fund.eastmoney.com/pingzhongdata/{code}.js"  // 新的 API2
    ]
    
    @Published var logMessages: [LogEntry] = [] // 更改为结构化日志数组
    
    // 主基金数据缓存，使用基金代码作为键，存储 CachedFundHolding
    // 使用 DispatchQueue 确保对缓存字典的读写是同步的，避免并发问题
    private var fundCache: [String: CachedFundHolding] = [:]
    private let cacheQueue = DispatchQueue(label: "com.mmp.fundcache")
    private let userDefaultsKey = "fundServiceCache"
    
    // 主缓存过期时间（例如，1 天）
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60 // 24小时

    // 优化：将 DateFormatter 声明为静态常量，避免重复创建
    // 注意：DateFormatter 不是线程安全的，但在这种使用模式下（在主线程或独立Task中访问）通常是可接受的
    static let dateFormatterYYYYMMDD: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX") // 确保日期格式化在不同地区一致
        return formatter
    }()
    
    static let dateFormatterYYYY_MM_DD: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX") // 确保日期格式化在不同地区一致
        return formatter
    }()

    // 用于比较日期是否为同一天的日历
    private let calendar = Calendar.current

    init() {
        // 在初始化时加载持久化的主缓存
        cacheQueue.async {
            self.loadCacheFromUserDefaults()
        }
    }

    // 主要的基金信息获取方法
    func fetchFundInfo(code: String) async -> FundHolding {
        addLog("开始查询基金代码: \(code)", type: .network)
        
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
        
        // 2. 主缓存不存在或已过期，从 API 并发获取
        addLog("基金代码 \(code): 主缓存不可用，开始并发尝试从API获取。", type: .network)
        
        var fetchedHolding: FundHolding?
        
        // 使用 TaskGroup 实现并发请求
        await withTaskGroup(of: FundHolding?.self) { group in
            for (index, urlStringTemplate) in apiURLs.enumerated() {
                group.addTask {
                    let urlString = urlStringTemplate.replacingOccurrences(of: "{code}", with: code)
                    guard let url = URL(string: urlString) else {
                        self.addLog("基金代码 \(code): API \(index + 1) URL无效: \(urlString)", type: .error)
                        return nil
                    }
                    
                    self.addLog("基金代码 \(code): 尝试从 API \(index + 1) 获取数据: \(urlString)", type: .network)
                    
                    let randomDelay = Double.random(in: 0.5...1.0)
                    self.addLog("基金代码 \(code): API \(index + 1) 将延迟 \(String(format: "%.2f", randomDelay)) 秒。", type: .info)
                    try? await Task.sleep(nanoseconds: UInt64(randomDelay * 1_000_000_000))
                    
                    var request = URLRequest(url: url)
                    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                    
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            self.addLog("基金代码 \(code): API \(index + 1) 响应状态码非200: \((response as? HTTPURLResponse)?.statusCode ?? -1)", type: .error)
                            return nil
                        }
                        
                        if let result = await self.parseFundData(data: data, apiIndex: index, code: code) {
                            self.addLog("基金代码 \(code): API \(index + 1) 解析成功。", type: .success)
                            return result
                        } else {
                            self.addLog("基金代码 \(code): API \(index + 1) 数据解析失败。", type: .error)
                            return nil
                        }
                    } catch {
                        self.addLog("基金代码 \(code): API \(index + 1) 请求失败: \(error.localizedDescription)", type: .error)
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let validHolding = result {
                    // 只需一个 API 成功获取到核心数据，就认为是有效数据
                    // 收益率数据可以缺失
                    if validHolding.fundName != "N/A" && validHolding.currentNav > 0 {
                        fetchedHolding = validHolding
                        group.cancelAll()
                        break
                    }
                }
            }
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
            // 尝试获取收益率数据，如果获取失败，不影响 isValid 状态
            if dataFromAPI.fundName != "N/A" {
                if let returnData = await self.getFundReturns(for: code) {
                    finalHolding.navReturn1m = returnData.navReturn1m
                    finalHolding.navReturn3m = returnData.navReturn3m
                    finalHolding.navReturn6m = returnData.navReturn6m
                    finalHolding.navReturn1y = returnData.navReturn1y
                }
            }
            saveToCache(holding: finalHolding)
            addLog("基金代码 \(code): 成功获取有效数据并更新主缓存。", type: .success)
        } else {
            if let cachedData = getFromCache(code: code) {
                addLog("基金代码 \(code): 新数据获取失败，返回旧的主缓存数据。", type: .error)
                finalHolding = cachedData.holding
                // 如果缓存数据过期但没有新数据，标记为无效以便下次刷新
                finalHolding.isValid = !isCacheExpired(cachedData)
            } else {
                addLog("基金代码 \(code): 未能获取任何有效数据，也没有可用主缓存。", type: .error)
                finalHolding.isValid = false
            }
        }
        
        return finalHolding
    }

    private func getFundReturns(for code: String) async -> FundHolding? {
        let urlStringTemplate = apiURLs[1]
        let urlString = urlStringTemplate.replacingOccurrences(of: "{code}", with: code)
        guard let url = URL(string: urlString) else { return nil }
        
        addLog("基金代码 \(code): 尝试从 API 2 (收益率) 获取数据: \(urlString)", type: .network)

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let string = String(data: data, encoding: .utf8) {
                var holding = FundHolding(clientName: "", fundCode: code, purchaseAmount: 0, purchaseShares: 0, purchaseDate: Date())
                
                if let syl1mRegex = try? NSRegularExpression(pattern: #"var syl_1y="([\d.-]+)";"#, options: []),
                   let syl1mMatch = syl1mRegex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) {
                    let valueString = (string as NSString).substring(with: syl1mMatch.range(at: 1))
                    if let value = Double(valueString) { holding.navReturn1m = value }
                }

                if let syl3mRegex = try? NSRegularExpression(pattern: #"var syl_3y="([\d.-]+)";"#, options: []),
                   let syl3mMatch = syl3mRegex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) {
                    let valueString = (string as NSString).substring(with: syl3mMatch.range(at: 1))
                    if let value = Double(valueString) { holding.navReturn3m = value }
                }

                if let syl6mRegex = try? NSRegularExpression(pattern: #"var syl_6y="([\d.-]+)";"#, options: []),
                   let syl6mMatch = syl6mRegex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) {
                    let valueString = (string as NSString).substring(with: syl6mMatch.range(at: 1))
                    if let value = Double(valueString) { holding.navReturn6m = value }
                }
                
                if let syl1yRegex = try? NSRegularExpression(pattern: #"var syl_1n="([\d.-]+)";"#, options: []),
                   let syl1yMatch = syl1yRegex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) {
                    let valueString = (string as NSString).substring(with: syl1yMatch.range(at: 1))
                    if let value = Double(valueString) { holding.navReturn1y = value }
                }
                
                addLog("基金代码 \(code): API 2 (收益率) 数据解析成功。", type: .success)
                return holding
            }
        } catch {
            addLog("基金代码 \(code): API 2 (收益率) 请求失败: \(error.localizedDescription)", type: .error)
        }
        
        return nil
    }

    private func parseFundData(data: Data, apiIndex: Int, code: String) async -> FundHolding? {
        var holding = FundHolding(
            clientName: "", clientID: "", fundCode: code,
            purchaseAmount: 0, purchaseShares: 0, purchaseDate: Date(),
            remarks: "", fundName: "N/A", currentNav: 0, navDate: Date(),
            isValid: false, isPinned: false, pinnedTimestamp: nil,
            navReturn1m: nil, navReturn3m: nil, navReturn6m: nil, navReturn1y: nil
        )

        if apiIndex == 0 { // API1
            if let string = String(data: data, encoding: .utf8) {
                if let regex = try? NSRegularExpression(pattern: "\\{.*?\\}", options: .dotMatchesLineSeparators),
                   let match = regex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) {
                    let jsonString = (string as NSString).substring(with: match.range)
                    if let jsonData = jsonString.data(using: .utf8) {
                        do {
                            if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                                holding.fundName = json["name"] as? String ?? "N/A"
                                if let jzrq = json["jzrq"] as? String, let date = FundService.dateFormatterYYYY_MM_DD.date(from: jzrq) {
                                    holding.navDate = date
                                }
                                if let dwjz = json["dwjz"] as? String, let value = Double(dwjz) {
                                    holding.currentNav = value
                                }
                                holding.isValid = holding.fundName != "N/A" && holding.currentNav > 0
                                return holding
                            }
                        } catch {
                            addLog("基金代码 \(code): API 1 JSON 解析错误: \(error.localizedDescription)", type: .error)
                        }
                    }
                }
            }
        } else if apiIndex == 1 { // API2
            if let string = String(data: data, encoding: .utf8) {
                // 解析 fS_name
                if let nameRange = string.range(of: "fS_name = \""),
                   let nameEndRange = string[nameRange.upperBound...].range(of: "\";") {
                    let startIndex = nameRange.upperBound
                    let endIndex = nameEndRange.lowerBound
                    holding.fundName = String(string[startIndex..<endIndex])
                }
                
                // 解析最新的净值和日期
                if let trendRange = string.range(of: "Data_netWorthTrend = "),
                   let trendEndRange = string[trendRange.upperBound...].range(of: ";") {
                    let jsonPart = String(string[trendRange.upperBound..<trendEndRange.lowerBound])
                    if let jsonData = jsonPart.data(using: .utf8),
                       let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]],
                       let latestData = jsonArray.last {
                        if let timestamp = latestData["x"] as? Double {
                            holding.navDate = Date(timeIntervalSince1970: timestamp / 1000)
                        }
                        if let navValue = latestData["y"] as? Double {
                            holding.currentNav = navValue
                        }
                    }
                }

                // 收益率数据将在 getFundReturns 中单独处理，这里不再解析
                
                holding.isValid = holding.fundName != "N/A" && holding.currentNav > 0
                return holding
            }
        }
        
        return nil
    }

    // 主基金数据缓存相关方法
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
            print("FundService: 持久化主缓存失败: \(error.localizedDescription)")
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
}
