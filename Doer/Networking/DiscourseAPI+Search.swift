import Alamofire
import Foundation
import UniformTypeIdentifiers

// MARK: - search
extension DiscourseAPI {
    func search(term: String, page: Int = 0, typeFilter: String? = nil) async throws -> DiscourseSearchResult {
        try await request(route: .search(term: term, page: page, typeFilter: typeFilter))
    }

    /// Discourse AI 语义搜索；站点未启用 discourse-ai 时会以 403/404 失败。

    func semanticSearch(term: String) async throws -> DiscourseSearchResult {
        try await request(route: .semanticSearch(term: term))
    }

    func fetchRecentSearches() async throws -> [String] {
        struct RecentSearchesResponse: Decodable {
            let recentSearches: [String]

            enum CodingKeys: String, CodingKey {
                case recentSearches = "recent_searches"
            }
        }
        let response: RecentSearchesResponse = try await request(route: .recentSearches)
        return response.recentSearches
    }

    func clearRecentSearches() async throws {
        try await requestVoid(route: .clearRecentSearches)
    }
}
