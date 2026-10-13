# Loose-Leaf (活页集) · macOS Native Workstation

> **暗房工作台与灵感捕捉器 (The Darkroom & Quick Capture Station)**  
> 活页集 (`Loose-Leaf`) 的原生 macOS 桌面客户端，基于 `SwiftUI + AppKit + WidgetKit` 构建。

---

## 核心特性

1. **纸张数字主义与暗房双模态 (`Paper & Darkroom`)**
   - 严格遵循跨端语义色彩资产表 (`Assets.xcassets`)，零硬编码十六进制色值。
   - **纸张模式 (Light)**：温润宣纸底色与宋刻衬线混排；**暗房模式 (Dark)**：炭黑底色与银盐文字，专为深夜修图与归档设计。
   - 支持 `.film-frame` 相纸装裱画框与 `NoiseBackground` 纸张纹理。

2. **全局极速捕捉 (`MenuBarExtra` & 全局快捷键)**
   - **极速记账 (`⌥Space` / `⌘⇧L`)**：支持类 Spotlight 自然语言解析（如输入 `42.5 午餐手冲咖啡` 自动拆解为 `4250` 分、`餐饮` 分类与备注）。
   - **手稿速记 (`⌘⇧Space` / `⌘N`)**：支持 `#标签` 自动提取、剪贴板截图/照片一键粘贴（`⌘⇧V`）与系统右键服务菜单摘录 (`Services Menu`)。

3. **桌面暗房流水线 (`DarkroomDropZone`)**
   - 原生 `ImageIO` 提取相机、镜头、光圈、快门、ISO 等 EXIF 元数据。
   - 客户端无损缩放至 4K (`3840px`) 与 85% JPEG 编码，通过预签名 URL 直传 Cloudflare R2（本地开发未配置 R2 时自动回退至 `/api/v1/files/upload`）。

4. **分位整数精度账本与联动装备库 (`Ledger & Gear`)**
   - 所有金额均以 `Int64` **分 (`cents`)** 存储与传输，彻底杜绝浮点数精度漂移。
   - 新增器物资产支持勾选 **`create_transaction = true`**，一键同步生成大额购置账单。

5. **离线发件箱与增量同步 (`SyncManager`)**
   - 本地快照 (`snapshot_v1.json`) 毫秒级冷启动渲染。
   - 断网状态下新建的手稿、账单与心愿自动进入持久化 `Outbox` 发件箱，`NWPathMonitor` 探测网络恢复后自动重放上云并刷新桌面 Widget。

6. **原生拟真声学与触觉反馈 (`AudioFeedback`)**
   - 内置快门声 (`shutter.wav`)、纸张翻页声 (`paper_flip.wav`) 与铅字敲击声 (`tink.wav`)，配合 Force Touch 触控板震动反馈，可在偏好设置中一键静音。

---

## 目录结构

```text
mac/
├── Package.swift                      # Swift Package Manager 构建与测试工程
├── LooseLeaf.xcodeproj/               # Xcode 原生工程配置
├── LooseLeaf/
│   ├── App/
│   │   ├── LooseLeafApp.swift         # @main 入口、MenuBarExtra、主窗口与菜单快捷键
│   │   ├── AppDelegate.swift          # 全局热键监听、浮动 NSPanel、URL Scheme 与系统服务
│   │   └── AppState.swift             # 跨窗口 UI 导航与模态框状态中心
│   ├── Models/
│   │   ├── EntryModel.swift           # LifeEntry / Attachment / GlobalStats 模型
│   │   ├── TransactionModel.swift     # Transaction (Int64 分) / GearItem / 信用渠道模型
│   │   └── ProfileModel.swift         # CuratorProfile / Wish / Footprint / 配对鉴权模型
│   ├── Services/
│   │   ├── APIClient.swift            # Async/Await 网络客户端（Bearer / X-Device-Token / ETag）
│   │   ├── KeychainManager.swift      # macOS Keychain 安全存储
│   │   ├── SyncManager.swift          # 增量同步、本地快照与 Offline Outbox 队列
│   │   ├── ImageProcessor.swift       # ImageIO EXIF 解析与 4K JPEG 压缩
│   │   ├── R2DirectUploader.swift     # R2 预签名 PUT 直传与本地回退上传器
│   │   ├── AudioFeedback.swift        # 机械快门/翻页/打字机声效与触控板反馈
│   │   └── FormatUtils.swift          # Int64 分转换、UTC+8 北京时间解析与自然语言记账解析
│   ├── Views/
│   │   ├── MenuBar/                   # QuickCaptureView & QuickLedgerView
│   │   ├── Main/                      # StreamView / DarkroomDropZone / LedgerAssetsView / ProjectsWishesView / SettingsView
│   │   └── Components/                # FilmFrameView / NoiseBackground / PaperComponents
│   └── Resources/
│       ├── Assets.xcassets/           # 跨端统一语义色板与图标资产
│       └── Audio/                     # shutter.wav / paper_flip.wav / tink.wav
├── LooseLeafWidget/                   # macOS 桌面小组件扩展 (Archive / Expense / Memory)
└── LooseLeafTests/                    # XCTest 单元测试套件
```

---

## 构建与运行

### 命令行构建与测试 (SwiftPM)

```bash
cd mac
swift build
swift test
```

### 使用 Xcode 打开

```bash
open LooseLeaf.xcodeproj
```
