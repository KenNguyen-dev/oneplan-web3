import MapKit

struct MapSearchResult: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let pointOfInterestCategory: MKPointOfInterestCategory?

    init(mapItem: MKMapItem) {
        self.id = UUID().uuidString
        self.name = mapItem.name ?? "Unknown"
        self.address = [
            mapItem.placemark.thoroughfare,
            mapItem.placemark.subLocality,
            mapItem.placemark.locality
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        self.latitude = mapItem.placemark.coordinate.latitude
        self.longitude = mapItem.placemark.coordinate.longitude
        self.pointOfInterestCategory = mapItem.pointOfInterestCategory
    }

    /// The string to write into plan item's `location` field
    var locationString: String { name }
}
