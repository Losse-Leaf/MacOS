#!/usr/bin/env python3
"""校验 Info.plist 是否包含应用运行所必需的关键键。

用法：python3 scripts/check_info_plist.py LooseLeaf/Info.plist

缺失关键键会直接导致运行时行为异常（例如未声明 NSSupportsSuddenTermination=false
会让系统在任意时刻静默终止进程，跳过 applicationWillTerminate 的快照落盘）。
"""
import plistlib
import sys

REQUIRED_KEYS = {
    "CFBundleIdentifier": "应用唯一标识",
    "CFBundleName": "应用名称",
    "CFBundleShortVersionString": "对外版本号",
    "CFBundleVersion": "构建号",
    "LSMinimumSystemVersion": "最低系统版本",
    "NSHighResolutionCapable": "Retina 支持",
    "NSSupportsSuddenTermination": "必须为 false，否则退出前快照可能不落盘",
    "NSSupportsAutomaticTermination": "必须为 false，否则后台任务可能被静默终止",
    "ITSAppUsesNonExemptEncryption": "App Store 上架必需",
    "NSAppTransportSecurity": "ATS 策略",
    "CFBundleURLTypes": "自定义 URL Scheme（looseleaf://）",
    "NSServices": "系统服务菜单（摘录到活页集）",
}

FORCED_VALUES = {
    "NSSupportsSuddenTermination": False,
    "NSSupportsAutomaticTermination": False,
    "ITSAppUsesNonExemptEncryption": False,
    "NSHighResolutionCapable": True,
}


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check_info_plist.py <path/to/Info.plist>")
        return 2
    path = sys.argv[1]
    with open(path, "rb") as handle:
        data = plistlib.load(handle)

    missing = []
    for key, reason in REQUIRED_KEYS.items():
        if key not in data:
            missing.append(f"  - 缺少 {key}（{reason}）")

    wrong = []
    for key, expected in FORCED_VALUES.items():
        if key in data and data[key] != expected:
            wrong.append(f"  - {key} 期望 {expected}，实际 {data[key]}")

    if missing or wrong:
        print("Info.plist 校验未通过：")
        for line in missing + wrong:
            print(line)
        return 1

    print(f"Info.plist 校验通过（{len(REQUIRED_KEYS)} 个关键键齐备）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
