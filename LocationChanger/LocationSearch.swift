import MapKit

struct LocationSearchService {
    // Searches Apple's map service and returns the first matching place.
    // async: the caller can wait without blocking the interface.
    // throws: a network or search error is passed back to the caller.
    func search(query: String) async throws -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        let response = try await MKLocalSearch(request: request).start()

        // Returns nil if the search has no results.
        return response.mapItems.first
    }
}
