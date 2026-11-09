import Flutter
import UIKit
import CoreLocation

public class SwiftBackgroundLocationPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
    static var locationManager: CLLocationManager?
    static var channel: FlutterMethodChannel?
    var running = false
    private var pendingCurrentLocationResult: FlutterResult?
    private var currentLocationRequestManager: CLLocationManager?
    private var currentLocationTimeout: DispatchWorkItem?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftBackgroundLocationPlugin()
        
        SwiftBackgroundLocationPlugin.channel = FlutterMethodChannel(name: "com.almoullim.background_location/methods", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: SwiftBackgroundLocationPlugin.channel!)
        SwiftBackgroundLocationPlugin.channel?.setMethodCallHandler(instance.handle)
        instance.running = false
    }

    private func initLocationManager() {
        if (SwiftBackgroundLocationPlugin.locationManager == nil) {
            SwiftBackgroundLocationPlugin.locationManager = CLLocationManager()
            SwiftBackgroundLocationPlugin.locationManager?.delegate = self
            SwiftBackgroundLocationPlugin.locationManager?.requestAlwaysAuthorization()

            SwiftBackgroundLocationPlugin.locationManager?.allowsBackgroundLocationUpdates = true
            if #available(iOS 11.0, *) {
                SwiftBackgroundLocationPlugin.locationManager?.showsBackgroundLocationIndicator = true;
            }
            SwiftBackgroundLocationPlugin.locationManager?.pausesLocationUpdatesAutomatically = false
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "get_current_location" {
            requestCurrentLocation(result: result)
            return
        }

        SwiftBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "method")

        if (call.method == "start_location_service") {
            initLocationManager()
            SwiftBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "start_location_service")
            
            let args = call.arguments as? Dictionary<String, Any>
            let distanceFilter = args?["distance_filter"] as? Double
            let priority = args?["priority"] as? Int

            SwiftBackgroundLocationPlugin.locationManager?.distanceFilter = distanceFilter ?? 0

            if (priority == 0) {
                SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            }
            if (priority == 1) {
                SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            }
            if (priority == 2) {
                SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            }
            if (priority == 3) {
                if #available(iOS 14.0, *) {
                    SwiftBackgroundLocationPlugin.locationManager?.desiredAccuracy = kCLLocationAccuracyReduced
                } else {
                    // Fallback on earlier versions
                }
            }

            SwiftBackgroundLocationPlugin.locationManager?.startUpdatingLocation()
            running = true
            result(true)
        } else if (call.method == "is_service_running") {
            result(running)
        } else if (call.method == "stop_location_service") {
            initLocationManager()
            running = false
            SwiftBackgroundLocationPlugin.channel?.invokeMethod("location", arguments: "stop_location_service")
            SwiftBackgroundLocationPlugin.locationManager?.stopUpdatingLocation()
            result(true)
        }
    }

    private func requestCurrentLocation(result: @escaping FlutterResult) {
        guard CLLocationManager.locationServicesEnabled() else {
            result(FlutterError(
                code: "location_unavailable",
                message: "Location services are disabled.",
                details: nil
            ))
            return
        }
        guard pendingCurrentLocationResult == nil else {
            result(FlutterError(
                code: "location_request_in_progress",
                message: "A current location request is already in progress.",
                details: nil
            ))
            return
        }

        let manager = CLLocationManager()
        manager.delegate = self
        currentLocationRequestManager = manager
        pendingCurrentLocationResult = result

        let timeout = DispatchWorkItem { [weak self] in
            self?.failCurrentLocation(
                code: "location_timeout",
                message: "Timed out waiting for a location fix."
            )
        }
        currentLocationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)

        switch authorizationStatus(for: manager) {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            failCurrentLocation(
                code: "permission_denied",
                message: "Location permission has not been granted."
            )
        @unknown default:
            failCurrentLocation(
                code: "permission_denied",
                message: "The location authorization status is unknown."
            )
        }
    }

    private func authorizationStatus(for manager: CLLocationManager) -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    private func failCurrentLocation(code: String, message: String) {
        guard let result = pendingCurrentLocationResult else {
            return
        }
        clearCurrentLocationRequest()
        result(FlutterError(code: code, message: message, details: nil))
    }

    private func completeCurrentLocationRequest(with location: CLLocation) {
        guard let result = pendingCurrentLocationResult else {
            return
        }
        clearCurrentLocationRequest()
        result(locationDictionary(location))
    }

    private func clearCurrentLocationRequest() {
        currentLocationTimeout?.cancel()
        currentLocationTimeout = nil
        currentLocationRequestManager?.delegate = nil
        currentLocationRequestManager = nil
        pendingCurrentLocationResult = nil
    }

    private func locationDictionary(_ location: CLLocation) -> [String: Any] {
        return [
            "speed": location.speed,
            "altitude": location.altitude,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "bearing": location.course,
            "time": location.timestamp.timeIntervalSince1970 * 1000,
            "is_mock": false
        ]
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard manager === currentLocationRequestManager,
              pendingCurrentLocationResult != nil else {
            return
        }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            failCurrentLocation(
                code: "permission_denied",
                message: "Location permission has not been granted."
            )
        default:
            break
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        if manager === currentLocationRequestManager {
            completeCurrentLocationRequest(with: location)
            return
        }
        SwiftBackgroundLocationPlugin.channel?.invokeMethod(
            "location",
            arguments: locationDictionary(location)
        )
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === currentLocationRequestManager else {
            return
        }
        failCurrentLocation(code: "location_error", message: error.localizedDescription)
    }
}
