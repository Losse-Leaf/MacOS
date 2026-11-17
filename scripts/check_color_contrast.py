#!/usr/bin/env python3
"""校验 Assets.xcassets 语义色板的 WCAG 对比度。

用法：python3 scripts/check_color_contrast.py LooseLeaf/Resources/Assets.xcassets

规则：
1. 所有文本与强调语义色在浅色 / 深色两档下，都必须同时与对应档位的
   `ArchivePaper`（主纸面背景）和 `ArchiveSubtle`（卡片/输入框背景）
   达到正文 AA 级对比度（≥ 4.5:1）。
2. 关键令牌（含应用全局品牌强调色 `AccentColor`）不得缺失。

任何一项不达标即以非零退出码结束，可直接接入 CI 作为门禁。
"""
import json
import os
import sys

MIN_RATIO = 4.5

REQUIRED_COLORS = [
    "AccentColor",
    "InkPrimary",
    "InkSecondary",
    "InkMuted",
    "AccentMoss",
    "AccentWarm",
    "ArchivePaper",
    "ArchiveSubtle",
    "BorderSubtle",
    "BorderDivider",
]

NON_TEXT_COLORS = {"BorderSubtle", "BorderDivider", "ArchiveSubtle", "ArchivePaper"}


def hex_to_rgb(value: str):
    value = value.replace("0x", "")
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))


def relative_luminance(rgb):
    def channel(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast_ratio(a, b):
    la, lb = relative_luminance(a), relative_luminance(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def read_colorset(path: str):
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    variants = {}
    for entry in payload.get("colors", []):
        appearances = entry.get("appearances") or []
        is_high_contrast = any(
            ap.get("appearance") == "contrast" and ap.get("value") == "high"
            for ap in appearances
        )
        if is_high_contrast:
            continue
        is_dark = any(
            ap.get("appearance") == "luminosity" and ap.get("value") == "dark"
            for ap in appearances
        )
        components = entry["color"]["components"]
        rgb = hex_to_rgb(str(components["red"]) + str(components["green"]) + str(components["blue"]))
        key = "dark" if is_dark else "light"
        variants[key] = rgb
    return variants


def main() -> int:
    if len(sys.argv) < 2:
        root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "LooseLeaf/Resources/Assets.xcassets")
    else:
        root = sys.argv[1]

    colorsets = {}
    for entry in sorted(os.listdir(root)):
        if not entry.endswith(".colorset"):
            continue
        path = os.path.join(root, entry, "Contents.json")
        if not os.path.exists(path):
            continue
        colorsets[entry[: -len(".colorset")]] = read_colorset(path)

    problems = []
    for name in REQUIRED_COLORS:
        if name not in colorsets:
            problems.append(f"  - 缺少语义色 {name}")
    if problems:
        print("色彩对比度校验未通过：")
        for line in problems:
            print(line)
        return 1

    paper = colorsets["ArchivePaper"]
    subtle = colorsets["ArchiveSubtle"]
    for name, variants in sorted(colorsets.items()):
        if name in NON_TEXT_COLORS:
            continue
        for mode in ("light", "dark"):
            if mode not in variants:
                continue
            for bg_name, bg_set in (("ArchivePaper", paper), ("ArchiveSubtle", subtle)):
                ratio = contrast_ratio(variants[mode], bg_set[mode])
                if ratio < MIN_RATIO:
                    problems.append(
                        f"  - {name} 在 {mode} 模式下对 {bg_name} 对比度仅 {ratio:.2f}:1（要求 ≥ {MIN_RATIO}:1）"
                    )

    if problems:
        print("色彩对比度校验未通过（WCAG AA 正文级 · ArchivePaper + ArchiveSubtle）：")
        for line in problems:
            print(line)
        return 1

    print(
        f"色彩对比度校验通过（{len(colorsets)} 个语义色，浅/深双档对 ArchivePaper 与 ArchiveSubtle 均 ≥ {MIN_RATIO}:1）"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
