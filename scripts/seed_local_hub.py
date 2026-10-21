#!/usr/bin/env python3
"""为本地中枢灌入**贴近真实使用**的档案，用于 UI 走查与性能剖析。

要点：
  - 60 条散页（内容有长有短，模拟真实写作）
  - 其中一部分带**图片附件**（走 multipart 上传）—— 图片路径是卡顿重灾区，
    必须用真实数据测才有意义
  - 心愿 / 造物 / 账目 / 足迹若干
  - 走查专用设备令牌（与 mac 走查测试同一个）

用法：
  python3 scripts/seed_local_hub.py --hub http://localhost:8088 --count 60
"""
import argparse
import json
import os
import random
import struct
import sys
import urllib.error
import urllib.request
import uuid

TOKEN = "lldt_walkthrough_test_token_0001"

BODIES = [
    "把书架靠到窗边，下午的光正好落在书脊上。顺手拍了一张，纸的味道还没散。",
    "今天走了很久的路，鞋底沾着傍晚的尘土。回来路上买了一支很便宜的钢笔。",
    "雨下了一整个下午。屋里很安静，听得见雨点打在玻璃上的声音。",
    "整理旧物，翻出来三年前的笔记本，字迹还很淡。有些事像是昨天才发生的。",
    "和朋友在街角的小店坐了很久，什么正经事也没聊，就是坐着。",
    "清晨五点醒，窗外还是灰蓝色。给自己煮了咖啡，等天亮。",
    "看完了一本很厚的书，合上的时候有点舍不得。\n\n最后三章写得极慢，像是作者也在犹豫要不要落笔。",
    "搬了家，把所有书重新码了一遍。新的排列方式看起来像另一批书。",
    "公园的银杏开始黄了，踩上去有很轻的脆响。\n\n风一吹，落下来的比我想的多。",
    "煮了一锅汤，厨房里全是热气。冬天就该这样过。",
    "开会时走了神，想起小时候河边的那条路。散会后才发现笔记只记了两行。",
    "给旧手机清了内存，删掉三千多张照片。留下的两百张，忽然都很舍不得。",
    "失眠。凌晨三点，把去年的日记从头翻了一遍，文字比记忆里陌生。",
    "在旧书店买到一本绝版的诗集。扉页上有人用钢笔写了一行字，不认识。",
]


def png_bytes(width: int, height: int, seed: int) -> bytes:
    """生成一张纯 Python 合成的 PNG（无需 Pillow）"""
    rnd = random.Random(seed)
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0
        for x in range(width):
            r = (x * 7 + seed * 13) % 200 + 40
            g = (y * 5 + seed * 29) % 200 + 40
            b = rnd.randint(30, 120)
            raw += bytes((r & 0xFF, g & 0xFF, b & 0xFF))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib_crc(tag + data)))

    import zlib
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))


def zlib_crc(data: bytes) -> int:
    import zlib
    return zlib.crc32(data) & 0xFFFFFFFF


def request(hub: str, path: str, method: str = "GET", body=None, headers=None):
    url = f"{hub}{path}"
    data = None
    hdrs = {"X-Device-Token": TOKEN}
    if headers:
        hdrs.update(headers)
    if body is not None:
        data = json.dumps(body).encode()
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode())


def upload_image(hub: str, blob: bytes, filename: str) -> int:
    """multipart/form-data 上传（与客户端同一条链路）"""
    boundary = f"----seed{uuid.uuid4().hex}"
    parts = bytearray()
    parts += f'--{boundary}\r\n'.encode()
    parts += b'Content-Disposition: form-data; name="folder"\r\n\r\nentries\r\n'
    parts += f'--{boundary}\r\n'.encode()
    parts += f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode()
    parts += b"Content-Type: image/png\r\n\r\n"
    parts += blob
    parts += f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(
        f"{hub}/api/v1/files/upload",
        data=bytes(parts),
        method="POST",
        headers={
            "X-Device-Token": TOKEN,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = json.loads(resp.read().decode())
    return payload["data"]["attachment_id"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hub", default="http://localhost:8088")
    ap.add_argument("--count", type=int, default=60)
    ap.add_argument("--images", type=int, default=12, help="带图片的散页数量")
    args = ap.parse_args()

    hub = args.hub.rstrip("/")

    try:
        request(hub, "/api/v1/config")
    except Exception as exc:
        print(f"❌ 本地中枢不可用：{exc}")
        sys.exit(1)

    print(f"📡 中枢: {hub}")

    # 先把图传上去，拿到 attachment_id
    attachment_ids = []
    for i in range(args.images):
        blob = png_bytes(320, 240, seed=i + 1)
        try:
            aid = upload_image(hub, blob, f"seed_{i + 1}.png")
            attachment_ids.append(aid)
            print(f"  🖼  上传图片 {i + 1}/{args.images} -> attachment {aid}")
        except urllib.error.HTTPError as exc:
            print(f"  ⚠️  图片上传失败：{exc.code} {exc.read()[:200]}")
            break
        except Exception as exc:
            print(f"  ⚠️  图片上传异常：{exc}")
            break

    created = 0
    for i in range(args.count):
        payload = {
            "type": "life",
            "title": f"第 {i + 1} 条随笔",
            "content": BODIES[i % len(BODIES)],
            "occurred_at": f"2026-09-{((i % 28) + 1):02d}T10:00:00+08:00",
            "city_code": "330100",
            "city_name": "杭州市",
        }
        if i < len(attachment_ids):
            payload["attachment_ids"] = [attachment_ids[i]]
        try:
            request(hub, "/api/v1/entries", "POST", payload)
            created += 1
        except Exception as exc:
            print(f"  ⚠️  第 {i + 1} 条创建失败：{exc}")
            break

    print(f"✅ 已创建 {created} 条散页（{len(attachment_ids)} 张图片附件）")

    for i in range(10):
        try:
            request(hub, "/api/v1/wishes", "POST", {
                "title": f"第 {i + 1} 个心愿",
                "kind": "item",
                "note": "走查笔记",
                "spec": "规格",
                "city_code": "330100",
                "city_name": "杭州市",
                "budget": 12800,
            })
        except Exception:
            break

    for i in range(6):
        try:
            request(hub, "/api/v1/projects", "POST", {
                "title": f"第 {i + 1} 个造物",
                "description": "走查描述",
                "category": "开源项目",
                "status": "持续维护",
            })
        except Exception:
            break

    for i in range(12):
        try:
            request(hub, "/api/v1/transactions", "POST", {
                "amount": 2500 + i * 137,
                "type": "expense" if i % 3 else "income",
                "category": "餐饮",
                "title": f"第 {i + 1} 笔",
                "note": "",
                "payment_method": "微信支付",
                "city_code": "330100",
                "occurred_at": f"2026-09-{((i % 28) + 1):02d}T12:00:00+08:00",
            })
        except Exception:
            break

    print("✅ 心愿 / 造物 / 账目 已灌入")


if __name__ == "__main__":
    main()
