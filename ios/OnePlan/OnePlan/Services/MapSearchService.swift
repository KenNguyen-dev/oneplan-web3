import Foundation
import MapKit
import CoreLocation

@MainActor
@Observable
final class MapSearchService: NSObject {
    var completions: [MKLocalSearchCompletion] = []
    var suggestedResults: [MapSearchResult] = []
    var isSearching = false
    var error: String?
    var userLocation: CLLocation?

    private var completer = MKLocalSearchCompleter()
    private var searchRegion: MKCoordinateRegion?
    private var locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Requests a one-shot user location, configures the search region around it.
    /// Falls back silently if permission is denied.
    func configureWithUserLocation() async {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Wait briefly for authorization to be processed
            try? await Task.sleep(for: .milliseconds(500))
        }

        let currentStatus = locationManager.authorizationStatus
        guard currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways else {
            return
        }

        let location = await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }

        guard let location else { return }
        userLocation = location

        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
        configure(region: region)
    }

    func configure(region: MKCoordinateRegion?) {
        if let region {
            completer.region = region
        }
        searchRegion = region
    }

    func updateQuery(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            completions = []
            return
        }
        completer.queryFragment = text
    }

    func resolveCompletion(_ completion: MKLocalSearchCompletion) async -> MapSearchResult? {
        let request = MKLocalSearch.Request(completion: completion)
        if let region = searchRegion {
            request.region = region
        }
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            return MapSearchResult(mapItem: item)
        } catch {
            self.error = String(localized: "Failed to resolve location")
            return nil
        }
    }

    func searchNearby(query: String) async {
        guard !query.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let region = searchRegion {
            request.region = region
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            var results = Array(response.mapItems.prefix(10)).map { MapSearchResult(mapItem: $0) }
            if let userLocation {
                results.sort { a, b in
                    let distA = userLocation.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
                    let distB = userLocation.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                    return distA < distB
                }
            }
            suggestedResults = results
        } catch {
            self.error = String(localized: "Search failed")
        }
    }

    func searchNearbyCombined(queries: [String]) async {
        isSearching = true
        defer { isSearching = false }

        var combined: [MapSearchResult] = []
        var seenNames = Set<String>()

        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            if let region = searchRegion {
                request.region = region
            }

            let search = MKLocalSearch(request: request)
            if let response = try? await search.start() {
                for item in response.mapItems {
                    let result = MapSearchResult(mapItem: item)
                    if seenNames.insert(result.name).inserted {
                        combined.append(result)
                    }
                }
            }
        }

        if let userLocation {
            combined.sort { a, b in
                let distA = userLocation.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
                let distB = userLocation.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                return distA < distB
            }
        }

        suggestedResults = Array(combined.prefix(10))
    }

    func clearSearch() {
        completions = []
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension MapSearchService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.completions = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = String(localized: "Search autocomplete error")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension MapSearchService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: locations.first)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
