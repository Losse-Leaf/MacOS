import SwiftUI

/// 山川经纬星野图谱画布 (CelestialAtlasCanvasView - RC-98)
/// 从 ProjectsWishesView 中拆出的独立视图组件：
/// 承载城市足迹的经纬度投影、星野网格底纹、城市聚节点位与古典罗盘玫瑰。
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 山川经纬星野图谱 (CelestialAtlasCanvasView - RC-98)

/// 经纬度 → 星野画布的归一化投影参数。
/// 原先散落在视图体内的魔法数（60 / 530 / 45 / 485）在此具名化，
/// 便于日后微调投影窗口而不必通读整段布局代码。
struct CelestialProjection {
    /// 经度起点（画布左缘对应的经度值）
    static let longitudeOrigin: Double = 60.0
    /// 经度跨度（画布横向覆盖的经度值）
    static let longitudeSpan: Double = 530.0
    /// 纬度起点（画布上缘对应的纬度值）
    static let latitudeOrigin: Double = 45.0
    /// 纬度跨度（画布纵向覆盖的纬度值）
    static let latitudeSpan: Double = 485.0
    /// 横向归一化取值范围（留出边缘余量，避免节点贴边）
    static let xRange: ClosedRange<Double> = 0.05...0.95
    /// 纵向归一化取值范围
    static let yRange: ClosedRange<Double> = 0.08...0.92

    /// 经度 → 画布横向比例
    static func normalizedX(longitude: Double) -> Double {
        min(max((longitude - longitudeOrigin) / longitudeSpan, xRange.lowerBound), xRange.upperBound)
    }

    /// 纬度 → 画布纵向比例
    static func normalizedY(latitude: Double) -> Double {
        min(max((latitude - latitudeOrigin) / latitudeSpan, yRange.lowerBound), yRange.upperBound)
    }
}

@MainActor
public struct CelestialAtlasCanvasView: View {
    let footprints: [Footprint]
    var onSelectCity: (String, String) -> Void

    private struct CityCluster: Identifiable {
        var id: String { code }
        let code: String
        let name: String
        let count: Int
        let x: Double
        let y: Double
    }

    /// 城市聚合（按行政代码归并足迹并取坐标）
    /// 下沉为普通方法，由 body 一次性求值后复用，避免同一份聚合在 body 内被反复计算。
    private func makeClusters() -> [CityCluster] {
        var map: [String: (name: String, count: Int)] = [:]
        for fp in footprints {
            let cur = map[fp.cityCode] ?? (name: fp.cityName, count: 0)
            map[fp.cityCode] = (name: fp.cityName, count: cur.count + 1)
        }
        return map.map { (code, info) in
            let pt = CityDictionary.coordinate(forCode: code, cityName: info.name)
            return CityCluster(code: code, name: info.name, count: info.count, x: pt.x, y: pt.y)
        }
    }

    public var body: some View {
        // 一次性聚合并复用：ForEach 与统计文案共用同一份结果
        let clusters = makeClusters()

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Canvas { context, size in
                    let cols = 8
                    let rows = 5
                    for i in 1..<cols {
                        let x = size.width * CGFloat(i) / CGFloat(cols)
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(ArchivePalette.borderDivider.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }
                    for j in 1..<rows {
                        let y = size.height * CGFloat(j) / CGFloat(rows)
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(ArchivePalette.borderDivider.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }
                }

                ForEach(clusters) { item in
                    let normX = CGFloat(CelestialProjection.normalizedX(longitude: item.x))
                    let normY = CGFloat(CelestialProjection.normalizedY(latitude: item.y))
                    let nodeColor = item.count >= 3 ? ArchivePalette.accentWarm : (item.count == 2 ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)

                    Button {
                        onSelectCity(item.code, item.name)
                    } label: {
                        VStack(spacing: ArchiveSpacing.xxs) {
                            ZStack {
                                Circle()
                                    .fill(nodeColor.opacity(0.18))
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .fill(nodeColor)
                                    .frame(width: 7, height: 7)
                            }
                            Text(item.name)
                                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.caption, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                                .padding(.horizontal, ArchiveSpacing.xs)
                                .padding(.vertical, 1)
                                .background(ArchivePalette.archivePaper.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name)，\(item.count) 程足迹")
                    .accessibilityHint("打开该城市的回忆抽屉")
                    // 悬停反馈：指针滑过时给出可点击的视觉暗示
                    .paperHover()
                    .position(x: w * normX, y: h * normY)
                }

                // 右下角古典罗盘玫瑰 (Compass Rose) 与四角星野裁切标
                VStack(spacing: 1) {
                    Text("N")
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.micro, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Image(systemName: "safari")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(ArchivePalette.inkSecondary.opacity(0.65))
                }
                .padding(ArchiveSpacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                    Text("CELESTIAL VOYAGE TOPOLOGY · 85°E — 125°E / 18°N — 50°N")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text("已点亮 \(clusters.count) 座城市")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: 360)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.7)
        )
    }
}
