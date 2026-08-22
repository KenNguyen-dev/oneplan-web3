import CoreLocation
import Foundation

/// Streams the physical device's compass heading. Independent of any map
/// camera state — only the phone's orientation moves the value.
@MainActor
@Observable
final class DeviceHeadingService: NSObject {
    /// True heading in degrees [0, 360). 0 means the top of the device points
    /// at true north. `nil` until the first valid reading arrives.
    var trueHeading: CLLocationDirection?

    private let locationManager = CLLocationManager()
    private var isUpdating = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.headingFilter = 1
        locationManager.headingOrientation = .portrait
    }

    func start() {
        guard !isUpdating, CLLocationManager.headingAvailable() else { return }
        isUpdating = true
        locationManager.startUpdatingHeading()
    }

    func stop() {
        guard isUpdating else { return }
        isUpdating = false
        locationManager.stopUpdatingHeading()
    }
}

extension DeviceHeadingService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        let value = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading
        Task { @MainActor in
            trueHeading = value
        }
    }
}
