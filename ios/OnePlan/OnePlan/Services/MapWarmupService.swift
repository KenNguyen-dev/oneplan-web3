import CoreLocation
import Foundation
import MapKit

@MainActor
enum MapWarmupService {
    private static let timeoutDuration: Duration = .milliseconds(400)
    private static let distanceThresholdMeters: CLLocationDistance = 30_000
    private static let idleThresholdSeconds: TimeInterval = 15 * 60
    private static var lastWarmupCenter: CLLocationCoordinate2D?
    private static var lastWarmupDate: Date?

    static func warmup(latitude: Double, longitude: Double) async {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard shouldWarmup(for: center) else { return }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 1_500,
            longitudinalMeters: 1_500
        )
        options.size = CGSize(width: 120, height: 120)
        options.scale = 1
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { _, _ in
            // Best-effort warmup only; no completion dependency.
        }

        // Hard cap so chooser never waits indefinitely.
        try? await Task.sleep(for: timeoutDuration)
        snapshotter.cancel()
        lastWarmupCenter = center
        lastWarmupDate = Date()
    }

    private static func shouldWarmup(for center: CLLocationCoordinate2D) -> Bool {
        guard let lastWarmupCenter else { return true }

        let previous = CLLocation(
            latitude: lastWarmupCenter.latitude,
            longitude: lastWarmupCenter.longitude
        )
        let current = CLLocation(latitude: center.latitude, longitude: center.longitude)
        if previous.distance(from: current) >= distanceThresholdMeters {
            return true
        }

        guard let lastWarmupDate else { return true }
        return Date().timeIntervalSince(lastWarmupDate) >= idleThresholdSeconds
    }
}
