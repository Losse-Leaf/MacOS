import Foundation
import AppKit

// MARK: - 设备配对、解绑全清、深链直达与 Handoff 接力

extension AppState {
    /// UI 测试用中枢地址（启动参数 `-UITestHubURL <url>` 或环境变量 `LOOSELEAF_HUB_URL`）
    nonisolated static var uiTestHubURL: String? {
        if let idx = CommandLine.arguments.firstIndex(of: "-UITestHubURL"),
           idx + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[idx + 1]
        }
        if let env = ProcessInfo.processInfo.environment["LOOSELEAF_HUB_URL"], !env.isEmpty {
            return env
        }
        return nil
    }

    /// 组装 Vesper Auth OIDC 跨端授权入口地址：`{hubURL}/api/v1/auth/oidc/login?platform=...&device_name=...`
    public nonisolated static func buildOIDCLoginURL(
        hubURL: String,
        platform: String = "macos",
        deviceName: String
    ) -> URL? {
        var base = hubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard !base.isEmpty,
              let parsedBase = URL(string: base),
              let scheme = parsedBase.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsedBase.host?.isEmpty == false,
              var comps = URLComponents(string: "\(base)/api/v1/auth/oidc/login") else {
            return nil
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "platform", value: platform)
        ]
        let cleanName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty {
            items.append(URLQueryItem(name: "device_name", value: cleanName))
        }
        comps.queryItems = items
        return comps.url
    }

    /// 解析配对深链文本：`looseleaf://pair?hub=<中枢地址>&ticket=<配对工单>`
    public nonisolated static func parsePairLink(_ raw: String) -> (hub: String, ticket: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme == "looseleaf",
              comps.host == "pair" else { return nil }
        let items = comps.queryItems ?? []
        let ticket = items.first(where: { $0.name == "ticket" })?.value ?? ""
        guard !ticket.isEmpty else { return nil }
        let hub = items.first(where: { $0.name == "hub" })?.value ?? ""
        return (hub, ticket)
    }

    public func pairWithTicket(_ ticket: String, hubURL: String) async throws {
        let cleanTicket = ticket.trimmingCharacters(in: .whitespacesAndNewlines)
        APIClient.shared.setBaseURL(hubURL)
        self.hubURLString = APIClient.shared.baseURLString
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        _ = try await APIClient.shared.confirmPairing(
            ticket: cleanTicket,
            deviceName: "\(hostName) · macOS",
            deviceModel: "Mac"
        )
        if redeemedPairTickets.count >= 64 {
            redeemedPairTickets.removeAll()
        }
        redeemedPairTickets.insert(cleanTicket)
        self.isPaired = true
        self.errorBanner = nil
        onThisDayCacheDateKey = nil
        showTemporaryBanner("配对工单握手成功，凭证已写入本机受保护档案")
        await refreshAll(forceFull: true)
    }

    public func disconnectDevice() async {
        if let devId = CredentialStore.getDeviceId() {
            do {
                try await APIClient.shared.revokeDevice(id: devId)
            } catch let apiErr as APIError {
                if case .serverError = apiErr {
                    // 4xx：服务端已不认识这台设备，等价于已吊销，继续本地清除
                } else {
                    showTemporaryBanner("解除失败：无法联系中枢，本机数据与待同步记录均未清除，请联网后重试")
                    return
                }
            } catch {
                showTemporaryBanner("解除失败：无法联系中枢，本机数据与待同步记录均未清除，请联网后重试")
                return
            }
        }
        CredentialStore.clearAllCredentials()
        self.isPaired = false
        wipeAllLocalDeviceData()
        showTemporaryBanner("已安全吊销凭证并彻底清除本机私密快照与缓存")
    }

    /// 彻底抹除本地快照、媒体缓存、HTTP 缓存、Spotlight 索引、接力活动与内存态（A3 全清策略）
    func wipeAllLocalDeviceData() {
        endHandoffActivity()
        SyncManager.shared.purgeAllLocalData()
        PaperImageCache.clearAllCaches()
        APIClient.removeAllCachedResponses()
        SpotlightIndexer.clearIndex()
        clearPrivateArchiveState()
    }

    /// 解除配对 / 401 吊销 / 切换中枢时清空一切属于旧中枢的内存状态。
    func clearPrivateArchiveState() {
        entries = []
        transactions = []
        wishes = []
        onThisDayEntries = []
        onThisDayCacheDateKey = nil
        clearGlobalSearchResult()
        transactionSummary = TransactionSummary()
        profile = CuratorProfile()
        siteConfig = SiteConfig()
        stats = GlobalStats()
        trustedDevices = []
        creditChannels = []
        outboxItems = []
        undoStack = []
        quickDraft.reset()
        highlightedEntry = nil
        detailWindowEntry = nil
        editingEntry = nil
        editingTransaction = nil
        lightboxAttachment = nil
        activeConfirmDialog = nil
        navigation.highlightedWishId = nil
        navigation.ledgerSubTab = .ledger
        pendingUploadCount = 0
        failedUploadCount = 0
        pendingEntriesCount = 0
        pendingTransactionsCount = 0
        banners.clearAll()
        entriesRevision += 1
        transactionsRevision += 1
        filteredMemo = nil
        streamRowsMemo = nil
        entryCountsMemo = nil
        entriesByDateMemo = nil
        transactionIndexMemo = nil
        searchCorpusMemo = nil
        appliedEntriesFingerprint = nil
        appliedTransactionsFingerprint = nil
    }

    /// 导航定位并打开指定散页（Spotlight 系统搜索 / 深链直达）
    public func navigateToEntry(id entryId: Int) {
        self.activeSection = .stream
        self.selectedCategory = .all
        self.searchQuery = ""
        self.keyboardFocusedEntryId = entryId

        if let found = entries.first(where: { $0.id == entryId }) {
            self.detailWindowEntry = found
            publishHandoffActivity(for: found)
        } else {
            Task { @MainActor in
                await self.loadEntries(forceFull: true)
                if let found = self.entries.first(where: { $0.id == entryId }) {
                    self.detailWindowEntry = found
                }
            }
        }
    }

    /// 处理自定义 URL Scheme:
    /// - looseleaf://pair?hub=https://...&ticket=pair_tk_...
    /// - looseleaf://entry/123
    public func handleIncomingURL(_ url: URL) {
        guard url.scheme == "looseleaf" else { return }
        if url.host == "pair" {
            guard let parsed = Self.parsePairLink(url.absoluteString) else { return }
            let cleanTicket = parsed.ticket.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTicket.isEmpty,
                  !inFlightPairTickets.contains(cleanTicket),
                  !redeemedPairTickets.contains(cleanTicket) else {
                return
            }
            inFlightPairTickets.insert(cleanTicket)
            isConfirmingIncomingPairTicket = true
            let hub = parsed.hub.isEmpty ? hubURLString : parsed.hub
            Task { @MainActor in
                defer {
                    self.inFlightPairTickets.remove(cleanTicket)
                    self.isConfirmingIncomingPairTicket = !self.inFlightPairTickets.isEmpty
                }
                do {
                    try await pairWithTicket(cleanTicket, hubURL: hub)
                    NSApp?.activate(ignoringOtherApps: true)
                } catch {
                    self.errorBanner = error.localizedDescription
                }
            }
        } else if url.host == "entry" {
            if let idStr = url.pathComponents.last, let entryId = Int(idStr) {
                navigateToEntry(id: entryId)
            }
        }
    }

    // MARK: - 接力 (Handoff / NSUserActivity)

    /// 把某条散页发布为当前接力活动（私密散页严禁广播至蓝牙/iCloud Handoff）
    public func publishHandoffActivity(for entry: LifeEntry) {
        guard !entry.isPrivate else {
            endHandoffActivity()
            return
        }
        let activity = NSUserActivity(activityType: Self.userActivityType)
        let baseTitle = entry.title.isEmpty ? "散页手稿" : entry.title
        if let place = entry.location, !place.isEmpty {
            activity.title = "\(baseTitle) · \(place)"
        } else {
            activity.title = baseTitle
        }
        activity.userInfo = ["entryId": entry.id]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.becomeCurrent()
        currentUserActivity = activity
    }

    /// 结束接力活动
    public func endHandoffActivity() {
        currentUserActivity?.resignCurrent()
        currentUserActivity = nil
    }

    /// 处理接力过来的活动（来自其它设备的「继续浏览」）
    public func handleHandoffActivity(_ activity: NSUserActivity) {
        guard activity.activityType == Self.userActivityType else { return }
        let raw = activity.userInfo?["entryId"] as? NSNumber
        let id = raw?.intValue ?? activity.userInfo?["entryId"] as? Int ?? -1
        guard id >= 0 else { return }
        navigateToEntry(id: id)
    }
}
