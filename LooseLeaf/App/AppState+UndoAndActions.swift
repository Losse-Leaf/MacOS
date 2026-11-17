import Foundation

// MARK: - 撤销栈、增删动作、快速捕捉提交与待发重传

extension AppState {
    /// 一次可撤销的操作
    public struct UndoAction: Identifiable {
        public let id = UUID()
        public let label: String
        let perform: () async -> Bool

        public init(label: String, perform: @escaping () async -> Bool) {
            self.label = label
            self.perform = perform
        }
    }

    /// 撤销栈容量上限
    public static let maxUndoStackSize = 20

    /// 是否存在可撤销的操作（供菜单项启用/禁用）
    public var canUndo: Bool { !undoStack.isEmpty }

    /// 最近一次可撤销操作的名称（供界面展示）
    public var undoActionLabel: String? { undoStack.last?.label }

    /// 登记一次可撤销操作
    public func registerUndo(label: String, perform: @escaping () async -> Bool) {
        undoStack.append(UndoAction(label: label, perform: perform))
        if undoStack.count > Self.maxUndoStackSize {
            undoStack.removeFirst(undoStack.count - Self.maxUndoStackSize)
        }
    }

    /// 执行并弹出最近一次撤销操作
    public func performUndo() async {
        guard !isUndoing, let action = undoStack.popLast() else { return }
        isUndoing = true
        defer { isUndoing = false }
        if await action.perform() {
            showTemporaryBanner("已撤销「\(action.label)」")
        } else {
            undoStack.append(action)
            if undoStack.count > Self.maxUndoStackSize {
                undoStack.removeFirst(undoStack.count - Self.maxUndoStackSize)
            }
        }
    }

    /// 统一纸墨风格确认弹窗交互
    public func askConfirm(
        title: String = "请确认",
        message: String,
        confirmText: String = "确认",
        cancelText: String = "取消",
        danger: Bool = true,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        activeConfirmDialog = ConfirmDialogRequest(
            title: title,
            message: message,
            confirmText: confirmText,
            cancelText: cancelText,
            danger: danger,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    public func dismissConfirm() {
        activeConfirmDialog?.onCancel?()
        activeConfirmDialog = nil
    }

    // MARK: - 可撤销删除动作

    public func deleteEntryAction(_ entry: LifeEntry) {
        if entry.id < 0 {
            SyncManager.shared.removeOptimisticEntry(localTempId: entry.id)
            showTemporaryBanner("已删除该条待同步记录")
            return
        }
        guard entry.id > 0 else { return }
        let restoreRequest = entry.toCreateRequest()
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteEntry(id: entry.id)
            } catch {
                if !SyncManager.shared.isOnline {
                    SyncManager.shared.enqueueDelete(
                        kind: .deleteEntry,
                        localTempId: entry.id,
                        targetServerId: entry.id
                    )
                    self.showTemporaryBanner("当前离线，删除请求已排入发件箱，网络恢复后自动执行")
                } else {
                    self.showTemporaryBanner("删除失败：\(error.localizedDescription)")
                }
                return
            }
            await self.loadEntries(forceFull: false)
            await self.loadConfigAndProfile()
            if self.highlightedEntry?.id == entry.id {
                self.highlightedEntry = nil
            }
            self.registerUndo(label: "删除手稿「\(entry.title.isEmpty ? "未命名" : entry.title)」") {
                do {
                    _ = try await APIClient.shared.createEntry(restoreRequest)
                    await self.loadEntries(forceFull: false)
                    return true
                } catch {
                    self.showTemporaryBanner("撤销失败：\(error.localizedDescription)")
                    return false
                }
            }
            self.showTemporaryBanner("已删除手稿 · 可按 ⌘Z 撤销")
        }
    }

    public func deleteGearAction(_ gear: GearItem) async {
        let originalIndex = profile.edcGear.firstIndex { $0.id == gear.id } ?? -1
        do {
            try await APIClient.shared.deleteGearAsset(id: gear.id)
            await loadConfigAndProfile()
            await loadTransactionsAndAssets(forceFull: false)
            await loadEntries(forceFull: false)
        } catch {
            errorBanner = error.localizedDescription
            return
        }
        registerUndo(label: "删除器物「\(gear.name)」") {
            do {
                try await APIClient.shared.restoreGearAsset(gear, index: originalIndex)
                await self.loadConfigAndProfile()
                await self.loadTransactionsAndAssets(forceFull: false)
                await self.loadEntries(forceFull: false)
                return true
            } catch {
                self.showTemporaryBanner("撤销失败：\(error.localizedDescription)")
                return false
            }
        }
        showTemporaryBanner("已删除器物 · 可按 ⌘Z 撤销")
    }

    public func deleteTransactionAction(_ tx: Transaction) {
        if tx.id < 0 {
            SyncManager.shared.removeOptimisticTransaction(localTempId: tx.id)
            showTemporaryBanner("已删除该条待同步账目")
            return
        }
        guard tx.id > 0 else { return }
        let restoreRequest = tx.toCreateRequest()
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteTransaction(id: tx.id)
            } catch {
                if !SyncManager.shared.isOnline {
                    SyncManager.shared.enqueueDelete(
                        kind: .deleteTransaction,
                        localTempId: tx.id,
                        targetServerId: tx.id
                    )
                    self.showTemporaryBanner("当前离线，删除请求已排入发件箱，网络恢复后自动执行")
                } else {
                    self.showTemporaryBanner("删除账目失败：\(error.localizedDescription)")
                }
                return
            }
            await self.loadTransactionsAndAssets(forceFull: false)
            await self.loadEntries(forceFull: false)
            await self.loadConfigAndProfile()
            if self.highlightedEntry?.id == tx.id {
                self.highlightedEntry = nil
            }
            self.registerUndo(label: "删除账目「\(tx.title.isEmpty ? tx.category : tx.title)」") {
                do {
                    _ = try await APIClient.shared.createTransaction(restoreRequest)
                    await self.loadTransactionsAndAssets(forceFull: false)
                    return true
                } catch {
                    self.showTemporaryBanner("撤销失败：\(error.localizedDescription)")
                    return false
                }
            }
            self.showTemporaryBanner("已删除账目 · 可按 ⌘Z 撤销")
        }
    }

    public func deleteWishAction(_ wish: Wish) async throws {
        try await APIClient.shared.deleteWish(id: wish.id)
        await refreshAfterSecondaryWrite()
        showTemporaryBanner("已移除心愿「\(wish.title)」（可按 ⌘Z 撤销）")
        registerUndo(label: "删除心愿「\(wish.title)」") { [weak self] in
            guard let self else { return false }
            do {
                let req = CreateWishRequest(
                    title: wish.title,
                    kind: wish.kind,
                    note: wish.note,
                    spec: wish.spec,
                    cityCode: wish.cityCode,
                    cityName: wish.cityName,
                    budget: wish.budget,
                    targetDate: wish.targetDate,
                    plantedAt: wish.plantedAt,
                    attachmentIds: wish.attachments.isEmpty ? nil : wish.attachments.map(\.id),
                    isPrivate: wish.isPrivate
                )
                _ = try await APIClient.shared.createWish(req)
                await self.refreshAfterSecondaryWrite()
                return true
            } catch {
                self.errorBanner = "撤销删除心愿失败：\(error.localizedDescription)"
                return false
            }
        }
    }

    public func deleteProjectAction(_ proj: Project) async throws {
        try await APIClient.shared.deleteProject(id: proj.id)
        await refreshAfterSecondaryWrite()
        showTemporaryBanner("已移除造物项目「\(proj.title)」（可按 ⌘Z 撤销）")
        registerUndo(label: "删除项目「\(proj.title)」") { [weak self] in
            guard let self else { return false }
            do {
                let req = CreateProjectRequest(
                    title: proj.title,
                    subtitle: proj.subtitle,
                    description: proj.description,
                    story: proj.story,
                    category: proj.category,
                    status: proj.status,
                    githubUrl: proj.githubUrl,
                    order: proj.order,
                    isPrivate: proj.isPrivate
                )
                _ = try await APIClient.shared.createProject(req)
                await self.refreshAfterSecondaryWrite()
                return true
            } catch {
                self.errorBanner = "撤销删除项目失败：\(error.localizedDescription)"
                return false
            }
        }
    }

    public func deleteFootprintAction(_ fp: Footprint) async throws {
        try await APIClient.shared.deleteFootprint(id: fp.id)
        await refreshAfterSecondaryWrite()
        showTemporaryBanner("已移除「\(fp.cityName)」足迹票根（可按 ⌘Z 撤销）")
        registerUndo(label: "删除足迹「\(fp.cityName)」") { [weak self] in
            guard let self else { return false }
            do {
                let req = CreateFootprintRequest(
                    cityCode: fp.cityCode,
                    cityName: fp.cityName,
                    title: fp.title,
                    visitedAt: fp.visitedAt,
                    departedAt: fp.departedAt,
                    note: fp.note,
                    attachmentIds: fp.attachments.isEmpty ? nil : fp.attachments.map(\.id),
                    isPrivate: fp.isPrivate
                )
                _ = try await APIClient.shared.createFootprint(req)
                await self.refreshAfterSecondaryWrite()
                return true
            } catch {
                self.errorBanner = "撤销删除足迹失败：\(error.localizedDescription)"
                return false
            }
        }
    }

    // MARK: - 极速闪念与快速记账提交 (Quick Capture & Quick Ledger)

    public func submitQuickCapture(
        title: String,
        content: String,
        type: EntryType = .life,
        location: String? = nil,
        cityCode: String? = nil,
        cityName: String? = nil,
        footprintId: Int? = nil,
        attachmentIds: [Int] = [],
        attachments: [Attachment] = [],
        occurredAt: String? = nil,
        isPrivate: Bool = false
    ) async throws -> Bool {
        let finalLocation = (location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? location!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (profile.displayCity.isEmpty ? nil : profile.displayCity)

        var resolvedCode = cityCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedCode?.isEmpty == true { resolvedCode = nil }
        var resolvedCityName = cityName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedCityName?.isEmpty == true { resolvedCityName = nil }

        if resolvedCode != nil && resolvedCityName == nil {
            resolvedCityName = CityDictionary.standardCities.first(where: { $0.code == resolvedCode })?.name
        }

        let req = CreateEntryRequest(
            type: type.rawValue,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            occurredAt: occurredAt ?? FormatUtils.beijingISOString(),
            location: finalLocation,
            cityCode: resolvedCode,
            cityName: resolvedCityName,
            footprintId: footprintId,
            isPrivate: isPrivate,
            attachmentIds: attachmentIds
        )

        let (_, queuedOffline) = try await SyncManager.shared.submitEntry(req, attachments: attachments)
        if queuedOffline {
            showTemporaryBanner("已暂存至本地发件箱，网络恢复后自动同步")
        } else {
            showTemporaryBanner("已归入散页时间流")
            await loadConfigAndProfile()
        }
        return queuedOffline
    }

    public func submitQuickLedger(
        amountCents: Int64,
        type: String = "expense",
        category: String,
        title: String,
        note: String? = nil,
        paymentMethod: String? = nil,
        cityCode: String? = nil,
        occurredAt: String? = nil
    ) async throws -> Bool {
        let req = CreateTransactionRequest(
            amount: amountCents,
            type: type,
            category: category,
            title: title,
            note: note,
            paymentMethod: paymentMethod ?? paymentMethods.first ?? "微信支付",
            cityCode: cityCode,
            occurredAt: occurredAt ?? FormatUtils.beijingISOString()
        )

        let (_, queuedOffline) = try await SyncManager.shared.submitTransaction(req)
        let amountText = FormatUtils.formattedYuan(cents: amountCents, includeSymbol: true)
        if queuedOffline {
            showTemporaryBanner("已暂存至本地发件箱：\(amountText)（网络恢复后自动上传）")
            return true
        }
        showTemporaryBanner("已记入账本：\(amountText)")
        await loadTransactionsAndAssets(forceFull: false)
        await loadConfigAndProfile()
        return false
    }

    // MARK: - 待同步 / 失败内容重传

    /// 统计需要重新上传的条目数（待同步 + 同步失败，O(1) 读取）
    public var entriesNeedingUpload: Int {
        pendingEntriesCount
    }

    /// 统计需要重新上传的账目数（O(1) 读取）
    public var transactionsNeedingUpload: Int {
        pendingTransactionsCount
    }

    /// 重新上传一条散页（无论它是「待同步」还是「同步失败」）
    public func reuploadEntry(id: Int) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        SyncManager.shared.resyncEntry(id: id, req: entry.toCreateRequest(), attachments: entry.attachments)
    }

    /// 重新上传一条账目（完整透传分期字段）
    public func reuploadTransaction(id: Int) {
        guard let tx = transactions.first(where: { $0.id == id }) else { return }
        SyncManager.shared.resyncTransaction(id: id, req: tx.toCreateRequest())
    }

    /// 批量重新上传所有待同步 / 同步失败的内容
    @discardableResult
    public func reuploadAllPending() -> Int {
        let pendingEntries = entries.filter { ($0.syncStatus ?? "synced") != "synced" }
        let pendingTransactions = transactions.filter { ($0.syncStatus ?? "synced") != "synced" }
        let count = pendingEntries.count + pendingTransactions.count
        guard count > 0 else { return 0 }

        SyncManager.shared.resetPausedOutboxItems()

        guard !SyncManager.shared.isFlushingOutbox else {
            showTemporaryBanner("同步队列正在上传中（共 \(count) 条待同步内容）")
            return count
        }

        for entry in pendingEntries { reuploadEntry(id: entry.id) }
        for tx in pendingTransactions { reuploadTransaction(id: tx.id) }

        showTemporaryBanner("已重新上传 \(count) 条待同步内容")
        return count
    }
}
