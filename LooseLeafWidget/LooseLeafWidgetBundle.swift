import WidgetKit
import SwiftUI

/// 桌面小组件共享快照读取器 (`group.com.looseleaf.archive` / `Application Support`).
public enum WidgetArchiveReader {
    public static func loadSnapshot() -> LocalArchiveSnapshot? {
        let fm = FileManager.default
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.looseleaf.archive") {
            let fileURL = groupURL
                .appendingPathComponent("LooseLeafArchive", isDirectory: true)
                .appendingPathComponent("archive_snapshot_v1.json")
            if let data = try? Data(contentsOf: fileURL),
               let payload = try? JSONDecoder().decode(LocalArchiveSnapshot.self, from: data) {
                return payload
            }
        }
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = appSupport
                .appendingPathComponent("LooseLeafArchive", isDirectory: true)
                .appendingPathComponent("archive_snapshot_v1.json")
            if let data = try? Data(contentsOf: fileURL),
               let payload = try? JSONDecoder().decode(LocalArchiveSnapshot.self, from: data) {
                return payload
            }
        }
        return nil
    }
}

/// 活页集桌面小组件套件 (`docs/macos.md` §3.2).
@main
public struct LooseLeafWidgetBundle: WidgetBundle {
    public init() {}

    public var body: some Widget {
        ArchiveWidget()
        ExpenseWidget()
        MemoryWidget()
    }
}
