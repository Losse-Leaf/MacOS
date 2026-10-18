import Foundation
import CoreLocation
import Observation
import os

/// 原生定位与省市解析服务 (LocationManager)
/// 负责静默获取经纬度并反查行政省市，完全消除手动输入省市的低效交互。
@Observable
@MainActor
public final class LocationManager: NSObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "location")
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    public var authorizationStatus: CLAuthorizationStatus
    public var isLocating: Bool = false
    public var currentProvince: String = ""
    public var currentCity: String = ""
    public var lastResolvedLocationName: String = ""

    private override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// 请求定位权限并尝试触发单次定位
    public func requestAuthorizationAndFetch() {
        let status = manager.authorizationStatus
        self.authorizationStatus = status

        switch status {
        case .notDetermined:
            Self.logger.info("请求系统位置权限")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            fetchCurrentLocation()
        case .denied, .restricted:
            Self.logger.notice("位置权限已被拒绝或受限")
        @unknown default:
            break
        }
    }

    /// 执行单次轻量定位
    public func fetchCurrentLocation() {
        guard !isLocating else { return }
        isLocating = true
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if self.authorizationStatus == .authorized || self.authorizationStatus == .authorizedAlways {
                self.fetchCurrentLocation()
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.isLocating = false
            await self.reverseGeocode(location: location)
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLocating = false
            Self.logger.warning("定位获取失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 地理逆编码

    private func reverseGeocode(location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            guard let placemark = placemarks.first else { return }

            let administrativeArea = placemark.administrativeArea ?? "" // 省/直辖市 (如 "云南省"、"北京市")
            let locality = placemark.locality ?? placemark.subAdministrativeArea ?? administrativeArea // 城市 (如 "大理白族自治州"、"北京市")

            self.currentProvince = administrativeArea
            self.currentCity = locality

            if administrativeArea == locality || administrativeArea.isEmpty {
                self.lastResolvedLocationName = locality
            } else {
                self.lastResolvedLocationName = "\(administrativeArea) · \(locality)"
            }
            Self.logger.info("成功逆地理编码: \(self.lastResolvedLocationName)")
        } catch {
            Self.logger.warning("逆地理编码失败: \(error.localizedDescription)")
        }
    }
}
