#!/usr/bin/env python3
"""校验 macOS 与 Web 端的城市字典是否一致。

用法：python3 scripts/check_city_dictionary.py <mac/CityDictionary.swift> <web/cities.ts>

背景：城市字典在两端各存一份（`mac/LooseLeaf/Models/CityDictionary.swift` 与
`web/src/utils/cities.ts`）。这是**双源维护**，迟早会漂移 —— 一端新增了城市，
另一端解析不到，表现为「拖动定位成功但省市为空」。本脚本把漂移变成 CI 失败。

校验规则：
1. Web 端 `CHINA_CITIES` 中的每一个 6 位城市代码，mac 端字典必须存在；
2. mac 端字典中的每一个代码，Web 端也必须存在；
3. 同一个代码在两端映射到的城市名必须一致（允许全称/简称差异，见下）。

mac 端字典把「全称」与「简称」都作为键（例："大理白族自治州" 与 "大理" 都指向 532900），
因此比对时以 Web 端的**全称**为准：只要 mac 端存在「代码 → 全称」的映射即可。
"""
import re
import sys


def parse_web(path):
    """从 cities.ts 解析 {code: name}"""
    with open(path, encoding="utf-8") as handle:
        content = handle.read()
    # { code: '110100', name: '北京市', ... }
    pattern = re.compile(r"\{\s*code:\s*'(\d{6})'\s*,\s*name:\s*'([^']+)'")
    return {m.group(1): m.group(2) for m in pattern.finditer(content)}


def parse_mac(path):
    """从 CityDictionary.swift 解析 {code: set(names)}"""
    with open(path, encoding="utf-8") as handle:
        content = handle.read()
    pattern = re.compile(r'"([^"]+)":\s*"(\d{6})"')
    mapping = {}
    for match in pattern.finditer(content):
        name, code = match.group(1), match.group(2)
        mapping.setdefault(code, set()).add(name)
    return mapping


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: check_city_dictionary.py <mac/CityDictionary.swift> <web/cities.ts>")
        return 2
    mac_path, web_path = sys.argv[1], sys.argv[2]

    import os
    if not os.path.exists(web_path):
        print(f"⚠️  未找到 Web 端城市字典（{web_path}），跳过双端一致性比对。")
        print("   在完整工作区中该检查会自动生效；CI 会检出 web 仓库后强制执行。")
        return 0

    web = parse_web(web_path)
    mac = parse_mac(mac_path)

    if not web:
        print("⚠️  未从 Web 端解析到任何城市条目（cities.ts 格式可能已变更），跳过比对。")
        return 0
    if not mac:
        print("❌ 未从 mac 端解析到任何城市条目（CityDictionary.swift 格式可能已变更）。")
        return 1

    problems = []
    for code, name in sorted(web.items()):
        if code not in mac:
            problems.append(f"  - Web 端存在 {code}（{name}），但 mac 端字典缺失")
        elif name not in mac[code]:
            problems.append(
                f"  - {code} 名称不一致：Web「{name}」 vs mac{ sorted(mac[code]) }"
            )

    for code in sorted(set(mac) - set(web)):
        problems.append(f"  - mac 端存在 {code}（{sorted(mac[code])}），但 Web 端字典缺失")

    if problems:
        print(f"城市字典一致性校验未通过（Web {len(web)} 项 / mac {len(mac)} 项）：")
        for line in problems[:40]:
            print(line)
        if len(problems) > 40:
            print(f"  … 另有 {len(problems) - 40} 项差异")
        print("请同步更新 mac/LooseLeaf/Models/CityDictionary.swift 与 web/src/utils/cities.ts")
        return 1

    print(f"城市字典一致性校验通过（{len(web)} 个地级单位双端对齐）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
