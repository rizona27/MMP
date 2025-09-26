    import Foundation
    import Combine

    enum FundAPI: String, CaseIterable, Identifiable {
        case eastmoney = "天天基金"
        case tencent = "腾讯财经"
        case fund123 = "蚂蚁基金"
        case fund10jqka = "同花顺"

        var id: String { self.rawValue }
    }

    struct CachedFundHolding: Codable {
        let holding: FundHolding
        let timestamp: Date
    }

    enum LogType: String {
        case info = "信息"
        case success = "成功"
        case error = "错误"
        case warning = "警告"
        case network = "网络"
        case cache = "缓存"
    }

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

        private var selectedFundAPI: FundAPI {
            get {
                if let rawValue = UserDefaults.standard.string(forKey: "selectedFundAPI"),
                   let api = FundAPI(rawValue: rawValue) {
                    return api
                }
                return .eastmoney
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

        func fetchFundInfo(code: String, useOnlyEastmoney: Bool = false) async -> FundHolding {
            addLog("开始查询基金代码: \(code)，使用API: \(selectedFundAPI.rawValue)" + (useOnlyEastmoney ? " (仅使用天天基金)" : ""), type: .network)

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
            
            addLog("基金代码 \(code): 主缓存不可用，开始尝试从API获取。", type: .network)
            
            var fetchedHolding: FundHolding?

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

                if selectedFundAPI == .eastmoney {
                    addLog("基金代码 \(code): 尝试获取收益率数据", type: .network)
                    let returnsData = await fetchReturnsFromEastmoney(code: code)

                    finalHolding.navReturn1m = returnsData.navReturn1m
                    finalHolding.navReturn3m = returnsData.navReturn3m
                    finalHolding.navReturn6m = returnsData.navReturn6m
                    finalHolding.navReturn1y = returnsData.navReturn1y
                    
                    addLog("基金代码 \(code): 收益率数据获取完成", type: .success)
                }
                
                saveToCache(holding: finalHolding)
                addLog("基金代码 \(code): 成功获取有效数据并更新主缓存。", type: .success)
            } else if !useOnlyEastmoney {
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

                        if api == .eastmoney {
                            addLog("基金代码 \(code): 尝试获取收益率数据", type: .network)
                            let returnsData = await fetchReturnsFromEastmoney(code: code)
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

                addLog("基金代码 \(code): 天天基金API失败且不允许使用备用API。", type: .error)
            }
            
            return finalHolding
        }

        private func fetchFromEastmoney(code: String) async -> FundHolding {
            addLog("基金代码 \(code): 尝试从天天基金API获取数据", type: .network)

            let urlString1 = "https://fundgz.1234567.com.cn/js/\(code).js"
            guard let url1 = URL(string: urlString1) else {
                addLog("基金代码 \(code): 天天基金API URL无效", type: .error)
                return FundHolding.invalid(fundCode: code)
            }
            
            do {
                var request1 = URLRequest(url: url1)
                request1.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                
                let (data1, response1) = try await URLSession.shared.data(for: request1)
                guard let httpResponse1 = response1 as? HTTPURLResponse, httpResponse1.statusCode == 200 else {
                    addLog("基金代码 \(code): 天天基金API响应状态码非200", type: .error)
                    return FundHolding.invalid(fundCode: code)
                }
                
                var holding = FundHolding.invalid(fundCode: code)
                var firstInterfaceDate: Date?
                
                if let string = String(data: data1, encoding: .utf8), string.starts(with: "jsonpgz") {
                    let jsonString = string
                        .replacingOccurrences(of: "jsonpgz(", with: "")
                        .replacingOccurrences(of: ");", with: "")
                    
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        
                        holding.fundName = json["name"] as? String ?? "N/A"
                        
                        if let jzrq = json["jzrq"] as? String,
                           let date = FundService.dateFormatterYYYY_MM_DD.date(from: jzrq) {
                            firstInterfaceDate = date
                            holding.navDate = date
                        }
                        
                        if let dwjz = json["dwjz"] as? String, let value = Double(dwjz) {
                            holding.currentNav = value
                        } else if let gsz = json["gsz"] as? String, let value = Double(gsz) {
                            holding.currentNav = value
                        }
                    }
                }

                let urlString2 = "https://fund.eastmoney.com/pingzhongdata/\(code).js"
                guard let url2 = URL(string: urlString2) else {
                    addLog("基金代码 \(code): 天天基金详情API URL无效", type: .error)
                    return holding
                }
                
                var request2 = URLRequest(url: url2)
                request2.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                
                let (data2, response2) = try await URLSession.shared.data(for: request2)
                guard let httpResponse2 = response2 as? HTTPURLResponse, httpResponse2.statusCode == 200 else {
                    addLog("基金代码 \(code): 天天基金详情API响应状态码非200", type: .error)
                    return holding
                }
                
                guard let jsString = String(data: data2, encoding: .utf8) else {
                    addLog("基金代码 \(code): 天天基金详情API数据编码失败", type: .error)
                    return holding
                }

                var latestNavDate: Date?
                var latestNavValue: Double?

                if let trendRange = jsString.range(of: "Data_netWorthTrend\\s*=\\s*\\[([^\\]]+)\\]") {
                    let trendString = String(jsString[trendRange])
                    if let arrayStart = trendString.range(of: "["),
                       let arrayEnd = trendString.range(of: "]") {
                        let arrayContent = String(trendString[arrayStart.upperBound..<arrayEnd.lowerBound])
                        let elements = arrayContent.split(separator: "},{").map(String.init)
                        
                        if let lastElement = elements.last {
                            let datePattern = "\"x\":(\\d+)"
                            let navPattern = "\"y\":([\\d.]+)"
                            
                            if let dateRange = lastElement.range(of: datePattern, options: .regularExpression),
                               let navRange = lastElement.range(of: navPattern, options: .regularExpression) {
                                let dateString = String(lastElement[dateRange])
                                if let timestamp = dateString.split(separator: ":").last.flatMap({ Int64($0) }) {
                                    latestNavDate = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
                                }
                                
                                let navString = String(lastElement[navRange])
                                if let nav = navString.split(separator: ":").last.flatMap({ Double($0) }) {
                                    latestNavValue = nav
                                }
                            }
                        }
                    }
                }

                if let latestDate = latestNavDate, let latestNav = latestNavValue,
                   let firstDate = firstInterfaceDate {
                    
                    if latestDate > firstDate {
                        holding.navDate = latestDate
                        holding.currentNav = latestNav
                        addLog("基金代码 \(code): 使用详情API的最新净值数据（日期: \(latestDate), 净值: \(latestNav))", type: .success)
                    } else {
                        addLog("基金代码 \(code): 使用主API的单位净值数据（日期: \(firstDate), 净值: \(holding.currentNav))", type: .success)
                    }
                } else if let latestDate = latestNavDate, let latestNav = latestNavValue {
                    holding.navDate = latestDate
                    holding.currentNav = latestNav
                    addLog("基金代码 \(code): 使用详情API的净值数据（日期: \(latestDate), 净值: \(latestNav))", type: .success)
                }
                
                holding.isValid = holding.fundName != "N/A" && holding.currentNav > 0
                
                if holding.isValid {
                    addLog("基金代码 \(code): 天天基金API解析成功", type: .success)
                } else {
                    addLog("基金代码 \(code): 天天基金API数据无效", type: .error)
                }
                
                return holding
            } catch {
                addLog("基金代码 \(code): 天天基金API请求失败: \(error.localizedDescription)", type: .error)
                return FundHolding.invalid(fundCode: code)
            }
        }

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
                
                addLog("基金代码 \(code): 收益率数据解析完成: 1月=\(navReturn1m ?? 0), 3月=\(navReturn3m ?? 0), 6月=\(navReturn6m ?? 0), 1年=\(navReturn1y ?? 0)", type: .success)
                return (navReturn1m, navReturn3m, navReturn6m, navReturn1y)
                
            } catch {
                addLog("基金代码 \(code): 天天基金收益率API请求或正则解析失败: \(error.localizedDescription)", type: .error)
                return (nil, nil, nil, nil)
            }
        }

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

                    let detailUrlString = "https://gu.qq.com/jj\(code)"
                    if let detailUrl = URL(string: detailUrlString) {
                        do {
                            let (htmlData, _) = try await URLSession.shared.data(from: detailUrl)
                            if let htmlString = String(data: htmlData, encoding: .utf8) {
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
                    var holding = FundHolding.invalid(fundCode: code)

                    let nameRegex = try NSRegularExpression(pattern: "fundNameAbbr[^']+'([^']+)'", options: [])
                    if let nameMatch = nameRegex.firstMatch(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.count)) {
                        let range = Range(nameMatch.range(at: 1), in: htmlString)!
                        holding.fundName = String(htmlString[range])
                    }

                    let navRegex = try NSRegularExpression(pattern: "netValue[^']+'([^']+)'", options: [])
                    if let navMatch = navRegex.firstMatch(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.count)) {
                        let range = Range(navMatch.range(at: 1), in: htmlString)!
                        if let navValue = Double(String(htmlString[range])) {
                            holding.currentNav = navValue
                        }
                    }

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

        internal func addLog(_ message: String, type: LogType) {
            DispatchQueue.main.async {
                let logEntry = LogEntry(message: message, type: type, timestamp: Date())
                self.logMessages.append(logEntry)
                if self.logMessages.count > 100 {
                    self.logMessages.removeFirst(50)
                }
            }
        }

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

                let namePattern = "fS_name\\s*=\\s*\"([^\"]*)\""
                if let nameRange = jsString.range(of: namePattern, options: .regularExpression) {
                    let nameString = String(jsString[nameRange])
                    if let quoteRange = nameString.range(of: "\"[^\"]*\"", options: .regularExpression) {
                        fundName = String(nameString[quoteRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }
                }

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
