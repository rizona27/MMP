import Foundation

struct TableColumn: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let keyPath: String
    var isSelected: Bool = true

    static func == (lhs: TableColumn, rhs: TableColumn) -> Bool {
        lhs.id == rhs.id
    }
}

extension TableColumn {
    static var allColumns: [TableColumn] {
        [
            TableColumn(title: "基金代码", keyPath: "fundCode", isSelected: true),
            TableColumn(title: "基金名称", keyPath: "fundName", isSelected: true),
            TableColumn(title: "近1月收益率", keyPath: "navReturn1m", isSelected: true),
            TableColumn(title: "近3月收益率", keyPath: "navReturn3m", isSelected: true),
            TableColumn(title: "近6月收益率", keyPath: "navReturn6m", isSelected: true),
            TableColumn(title: "近1年收益率", keyPath: "navReturn1y", isSelected: true)
        ]
    }
}
