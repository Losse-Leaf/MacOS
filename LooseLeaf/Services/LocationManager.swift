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
    /// 定位 / 逆地理编码失败时的用户可读提示（nil 表示无错误）
    public var errorMessage: String?

    /// 是否由用户显式触发的定位（只有显式触发才允许自动发起定位）
    private var userInitiated: Bool = false
    /// 逆地理编码并发守卫（避免连点触发多个并发请求被 Apple 限流）
    private var isGeocoding: Bool = false

    private override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // 非导航场景用 .other 更省电
        manager.activityType = .other
    }

    /// 当前是否已获得定位授权（直接读取已同步的授权状态快照，避免每次都跨进程查询系统）
    public var isAuthorized: Bool {
        let status = authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }

    /// 请求定位权限并尝试触发单次定位（仅在用户显式点击「定位」时调用）
    public func requestAuthorizationAndFetch() {
        let status = manager.authorizationStatus
        self.authorizationStatus = status
        userInitiated = true
        errorMessage = nil

        switch status {
        case .notDetermined:
            Self.logger.info("请求系统位置权限")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            fetchCurrentLocation()
        case .denied, .restricted:
            Self.logger.notice("位置权限已被拒绝或受限")
            errorMessage = "位置权限已被拒绝，请在「系统设置 → 隐私与安全性 → 定位服务」中允许后重试"
        @unknown default:
            break
        }
    }

    /// 执行单次轻量定位
    public func fetchCurrentLocation() {
        guard !isLocating else { return }
        isLocating = true
        errorMessage = nil
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 先在当前上下文取出授权状态（避免把 CLLocationManager 跨隔离域传入 Task）
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // 关键：只有用户**显式**触发过定位才允许自动发起。
            // CLLocationManager 设置 delegate 后会立即回调一次授权状态，
            // 原实现会导致「每次启动应用都自动定位」，与设计意图冲突且白白消耗电量。
            if self.userInitiated,
               self.authorizationStatus == .authorized || self.authorizationStatus == .authorizedAlways {
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
            // 失败必须对用户可见：原先只写日志，用户点「定位」后界面毫无反应
            let nsError = error as NSError
            if nsError.code == CLError.denied.rawValue {
                self.errorMessage = "定位权限已被拒绝，请在「系统设置 → 隐私与安全性 → 定位服务」中允许后重试"
            } else {
                self.errorMessage = "定位失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 地理逆编码

    private func reverseGeocode(location: CLLocation) async {
        // 并发守卫：连点「定位」会并发发起多个逆地理编码请求，触发 Apple 地理服务限流
        guard !isGeocoding else { return }
        isGeocoding = true
        defer { isGeocoding = false }
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            guard let placemark = placemarks.first else {
                errorMessage = "未能解析该位置所属的省市，请手动填写"
                return
            }

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
            errorMessage = "位置解析失败，请手动填写省市"
        }
    }
}
