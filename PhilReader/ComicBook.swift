import Foundation

struct ComicBook: Identifiable, Codable {
    let id: UUID
    var title: String
    var fileName: String      // Stored file name in app's Documents
    var pageCount: Int
    var currentPage: Int
    var dateAdded: Date

    init(id: UUID = UUID(), title: String, fileName: String, pageCount: Int = 0) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.currentPage = 0
        self.dateAdded = Date()
    }

    var progress: Double {
        guard pageCount > 1 else { return 0 }
        return Double(currentPage) / Double(pageCount - 1)
    }

    var progressText: String {
        guard pageCount > 0 else { return "" }
        return "Page \(currentPage + 1) of \(pageCount)"
    }
}
