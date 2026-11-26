import Foundation
import AppKit

// MARK: - OAuth2 / OIDC 账号登录、退出全清、深链直达与 Handoff 接力

extension AppState {
    /// UI 测试用服务器地址（启动参数 `-UITestHubURL <url>` 或环境变量 `LOOSELEAF_HUB_URL`）
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

    /// 组装 Vesper Auth OIDC 跨端登录入口地址：`{hubURL}/api/v1/auth/oidc/login?platform=...&device_name=...`
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

    /// 解析 OAuth2 回调深链（同时兼容旧版 `looseleaf://pair?hub=...&ticket=...`）：
    /// - 标准格式：`looseleaf://auth/callback?hub=<服务器地址>&code=<一次性授权码>`
    /// - 兼容格式：`looseleaf://pair?hub=<服务器地址>&ticket=<工单>`
    public nonisolated static func parsePairLink(_ raw: String) -> (hub: String, ticket: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme == "looseleaf" else { return nil }
        let host = (comps.host ?? "").lowercased()
        let isOAuthCallback = (host == "auth")
        let isLegacyPair = (host == "pair")
        guard isOAuthCallback || isLegacyPair else { return nil }

        let items = comps.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
            ?? items.first(where: { $0.name == "ticket" })?.value
            ?? ""
        guard !code.isEmpty else { return nil }
        let hub = items.first(where: { $0.name == "hub" })?.value ?? ""
        return (hub, code)
    }

    /// 用一次性 OAuth2 授权码建立本机登录会话
    public func pairWithTicket(_ ticket: String, hubURL: String) async throws {
        let cleanCode = ticket.trimmingCharacters(in: .whitespacesAndNewlines)
        APIClient.shared.setBaseURL(hubURL)
        self.hubURLString = APIClient.shared.baseURLString
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let resp = try await APIClient.shared.exchangeOIDCCode(
            code: cleanCode,
            deviceName: "\(hostName) · macOS",
            deviceModel: "Mac"
        )
        if redeemedPairTickets.count >= 64 {
            redeemedPairTickets.removeAll()
        }
        redeemedPairTickets.insert(cleanCode)
        self.accountName = resp.account?.name ?? ""
        self.accountEmail = resp.account?.email ?? ""
        self.isPaired = true
        self.errorBanner = nil
        onThisDayCacheDateKey = nil
        let label = self.accountName.isEmpty ? self.accountEmail : self.accountName
        showTemporaryBanner(label.isEmpty ? "登录成功" : "欢迎回来，\(label)")
        await refreshAll(forceFull: true)
    }

    /// 静默刷新当前登录账号摘要（兼容旧会话自动补齐账号名与邮箱）
    public func refreshAccountSession() async {
        guard isPaired else { return }
        if let session = try? await APIClient.shared.fetchSession(),
           let acct = session.account {
            let name = (acct.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let email = (acct.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { self.accountName = name }
            if !email.isEmpty { self.accountEmail = email }
            CredentialStore.saveAccountIdentity(
                sub: acct.sub,
                name: self.accountName.isEmpty ? nil : self.accountName,
                email: self.accountEmail.isEmpty ? nil : self.accountEmail
            )
        }
    }

    /// 退出账号登录：向服务端注销会话并彻底清除本机缓存
    public func disconnectDevice() async {
        let hasUnsynced = !outboxItems.isEmpty
        do {
            try await APIClient.shared.logout()
        } catch let apiErr as APIError {
            if case .serverError = apiErr {
                // 4xx：服务端已不认识当前会话，继续本地清除
            } else if hasUnsynced {
                showTemporaryBanner("退出失败：无法连接服务器，待同步记录尚未清除，请联网同步后重试")
                return
            }
        } catch {
            if hasUnsynced {
                showTemporaryBanner("退出失败：无法连接服务器，待同步记录尚未清除，请联网同步后重试")
                return
            }
        }
        CredentialStore.clearAllCredentials()
        self.isPaired = false
        self.accountName = ""
        self.accountEmail = ""
        wipeAllLocalDeviceData()
        showTemporaryBanner("已退出登录并清除本机缓存")
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

    /// 退出登录 / 401 过期 / 切换服务器时清空一切内存状态。
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
                if let remote = try? await APIClient.shared.fetchEntry(id: entryId) {
                    self.detailWindowEntry = remote
                    self.publishHandoffActivity(for: remote)
                    await self.loadEntries(forceFull: false)
                    return
                }
                await self.loadEntries(forceFull: true)
                if let found = self.entries.first(where: { $0.id == entryId }) {
                    self.detailWindowEntry = found
                    self.publishHandoffActivity(for: found)
                }
            }
        }
    }

    /// 处理自定义 URL Scheme:
    /// - looseleaf://auth/callback?hub=https://...&code=auth_code_...
    /// - looseleaf://pair?hub=https://...&ticket=pair_tk_...（历史兼容）
    /// - looseleaf://entry/123
    public func handleIncomingURL(_ url: URL) {
        guard url.scheme == "looseleaf" else { return }
        let host = (url.host ?? "").lowercased()
        if host == "auth" || host == "pair" {
            guard let parsed = Self.parsePairLink(url.absoluteString) else { return }
            let cleanCode = parsed.ticket.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanCode.isEmpty,
                  !inFlightPairTickets.contains(cleanCode),
                  !redeemedPairTickets.contains(cleanCode) else {
                return
            }
            inFlightPairTickets.insert(cleanCode)
            isConfirmingIncomingPairTicket = true
            let hub = parsed.hub.isEmpty ? hubURLString : parsed.hub
            Task { @MainActor in
                defer {
                    self.inFlightPairTickets.remove(cleanCode)
                    self.isConfirmingIncomingPairTicket = !self.inFlightPairTickets.isEmpty
                }
                do {
                    try await pairWithTicket(cleanCode, hubURL: hub)
                    NSApp?.activate(ignoringOtherApps: true)
                } catch {
                    self.errorBanner = error.localizedDescription
                }
            }
        } else if host == "entry" {
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
