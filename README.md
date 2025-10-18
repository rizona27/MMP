# 一基暴富 - 基金持仓管理工具

![Swift](https://img.shields.io/badge/Swift-5.0+-orange)
![Platform](https://img.shields.io/badge/Platform-iOS-blue)
![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-blue)

一个简单的基金持仓管理工具，为客户和基金管理设计。支持多客户基金持仓跟踪、实时净值查询、收益统计分析等功能。

## ✨ 主要特性

### 📊 多维度数据展示

- **一览视图**：按基金代码分组展示所有持仓，支持多种排序方式
- **客户视图**：按客户分组管理持仓，支持置顶和快速刷新
- **排名视图**：按收益率等指标排序筛选，支持多种过滤条件
- **设置中心**：数据导入导出、主题设置、隐私模式等

### 🔄 智能数据同步

- **多数据源支持**：天天基金、腾讯财经、蚂蚁基金、同花顺
- **自动缓存机制**：智能缓存减少请求，提升响应
- **批量刷新功能**：并发刷新基金数据
- **数据有效性检查**：识别过期数据并提示更新

### 🔒 隐私与安全

- **隐私模式**：姓名可脱敏显示，保护隐私
- **本地数据存储**：敏感数据本地加密存储

### 🎨 用户体验

- **UI设计**：SwiftUI
- **深色/浅色主题**：支持系统主题切换
- **实时搜索**：支持自定义快速搜索

## 📖 使用

1. **导入数据**
   - 进入"设置"页面
   - 点击"导入数据"
   - 选择符合格式的CSV文件
2. **CSV格式要求**

csv

```
客户姓名,基金代码,购买金额,购买份额,购买日期,客户号,备注
张三,000001,10000.00,5000.00,2024-01-15,123456789012,首次购买
```



## 📱 界面功能详解

### 一览视图 (SummaryView)

- **基金分组展示**：相同基金代码的持仓自动分组
- **智能排序**：支持按近1月、3月、6月、1年收益率排序
- **展开/收起**：一键展开或收起所有基金卡片
- **实时搜索**：快速定位特定基金或客户

### 客户视图 (ClientView)

- **客户分组管理**：按客户姓名分组显示所有持仓
- **置顶功能**：重要客户可置顶显示
- **批量刷新**：支持刷新单个客户或所有客户数据
- **滑动操作**：左滑快速置顶/取消置顶

### 排名视图 (TopPerformersView)

- **多条件筛选**：支持金额范围、持有天数、收益率等筛选
- **收益排名**：按年化收益率自动排序
- **数据导出**：筛选结果可导出分析

### 设置中心 (ConfigView)

- **数据管理**：导入、导出、清空持仓数据
- **主题设置**：浅色、深色、系统主题
- **API配置**：选择数据源接口
- **日志查询**：查看API请求日志

## 🔧 技术架构

### 核心组件

- **DataManager**：数据持久化管理
- **FundService**：基金数据获取服务
- **ToastQueueManager**：消息提示管理
- **CacheSystem**：智能缓存系统

### 网络层特性

swift

```
// 多API冗余设计
enum FundAPI: String, CaseIterable {
    case eastmoney = "天天基金"
    case tencent = "腾讯财经" 
    case fund123 = "蚂蚁基金"
    case fund10jqka = "同花顺"
}
```



### 数据模型

swift

```
struct FundHolding: Identifiable, Codable {
    var clientName: String
    var clientID: String
    var fundCode: String
    var fundName: String
    var purchaseAmount: Double
    var currentNav: Double
    var navDate: Date
    // ... 更多字段
}
```



## 📈 收益计算

### 计算公式

- **绝对收益**：`当前市值 - 购买金额`
- **年化收益率**：`(绝对收益 / 购买金额) / 持有天数 × 365 × 100%`

### 持有天数计算

精确到天的持有期计算，考虑净值日期与购买日期的时间差。

## 🔄 数据同步

### 缓存策略

- **智能过期**：24小时缓存有效期
- **条件更新**：净值日期非今日时自动更新
- **失败重试**：最多3次重试机制

### 并发控制

- **最大并发数**：3个同时请求
- **进度跟踪**：实时显示刷新进度
- **错误处理**：网络异常自动降级

## 🛠 开发指南

### 项目结构

text

```
MMP/
├── Views/                 # 主要界面
│   ├── ContentView.swift
│   ├── SummaryView.swift
│   ├── ClientView.swift
│   └── ConfigView.swift
├── Models/               # 数据模型
│   ├── FundModels.swift
│   └── DataManager.swift
├── Services/             # 服务层
│   └── FundService.swift
└── Utilities/           # 工具类
    ├── ToastView.swift
    └── PrivacyHelpers.swift
```



### 扩展开发

要添加新的数据源，实现以下协议：

swift

```
// 在FundService中扩展新的API方法
private func fetchFromNewAPI(code: String) async -> FundHolding
```



### 自定义主题

在 `ConfigView` 中扩展主题配置：

swift

```
enum ThemeMode: String, CaseIterable {
    case light = "浅色"
    case dark = "深色" 
    case system = "跟随系统"
}
```



## 📄 许可

采用 GPL-3.0 许可证 - 查看 LICENSE 文件了解详情。

## 🐛 问题反馈

如果您遇到任何问题或有改进建议，请通过以下方式反馈：

1. 创建Issue
2. 提供详细的错误描述和重现步骤
3. 包括设备型号和iOS版本信息

## 🙏 致谢

感谢所有为这个项目做出贡献的开发者，以及提供基金数据的各大平台。
