#!/usr/bin/env bash
set -euo pipefail

# Loose-Leaf (活页集) macOS 极速一键安装与更新脚本
# 用法：/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Losse-Leaf/MacOS/main/install.sh)"
#
# 安全说明：
# 1. 本脚本**不会**剥离 Gatekeeper 隔离属性（xattr -cr）。
#    未签名构建在首次打开时需要用户在「系统设置 → 隐私与安全性」中手动放行，
#    这是 macOS 的安全设计，脚本不应绕过它。
# 2. 下载产物会与 GitHub Release 提供的 sha256 摘要比对，不一致则中止安装。
# 3. 安装采用「临时目录 → 原子替换」，中途失败不会留下半安装状态。

APP_NAME="LooseLeaf"
REPO="Losse-Leaf/MacOS"
TARGET_DIR="${TARGET_DIR:-/Applications}"
APP_PATH="${TARGET_DIR}/${APP_NAME}.app"

echo "🍃 正在获取 Loose-Leaf (活页集) 最新版本信息..."

# 1. 查询 GitHub Releases 最新版本信息（优先通过重定向获取最新 Tag，完全规避 API 60次/小时频限）
TAG=""
EFFECTIVE_URL=$(curl -fsSLI -o /dev/null -w "%{url_effective}" "https://github.com/${REPO}/releases/latest" 2>/dev/null || echo "")
if [[ "${EFFECTIVE_URL}" == *"/releases/tag/"* ]]; then
    TAG=$(basename "${EFFECTIVE_URL}")
fi

if [ -z "$TAG" ]; then
    # 若重定向失败，回退至 API 接口
    RELEASE_JSON=$(curl -sSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || echo "")
    TAG=$(echo "$RELEASE_JSON" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
fi

if [ -z "$TAG" ]; then
    echo "❌ 无法获取最新版本信息，请检查网络连接。"
    exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/LooseLeaf-${TAG}-arm64.zip"

echo "📦 准备安装版本: ${TAG}"
echo "🔗 下载地址: ${DOWNLOAD_URL}"

# 2. 创建临时工作目录
TMP_DIR=$(mktemp -d -t looseleaf_install_XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

ZIP_PATH="${TMP_DIR}/LooseLeaf.zip"

echo "⬇️  正在下载应用包..."
curl -# -L "${DOWNLOAD_URL}" -o "${ZIP_PATH}"

# 2.1 校验下载产物完整性（GitHub Release 资产自带 sha256 digest）
EXPECTED_DIGEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${TAG}" 2>/dev/null \
    | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for asset in data.get('assets', []):
    if asset.get('name','').endswith('.zip'):
        digest = asset.get('digest') or ''
        if digest.startswith('sha256:'):
            print(digest[len('sha256:'):])
        break
" || true)

if [ -n "$EXPECTED_DIGEST" ]; then
    echo "🔐 正在校验下载包完整性 (SHA256)..."
    ACTUAL_DIGEST=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')
    if [ "${ACTUAL_DIGEST}" != "${EXPECTED_DIGEST}" ]; then
        echo "❌ 下载包校验失败（SHA256 不匹配），已中止安装。"
        exit 1
    fi
    echo "✅ 校验通过"
else
    echo "⚠️  该版本未提供 sha256 摘要，跳过完整性校验。"
fi

# 3. 解压产物
echo "📂 正在解压应用..."
unzip -q -o "${ZIP_PATH}" -d "${TMP_DIR}"

EXTRACTED_APP=$(find "${TMP_DIR}" -name "${APP_NAME}.app" -maxdepth 3 | head -n 1)

if [ -z "$EXTRACTED_APP" ] || [ ! -d "$EXTRACTED_APP" ]; then
    echo "❌ 解压失败，未找到 ${APP_NAME}.app！"
    exit 1
fi

# 4. 若旧应用正在运行，先请求其优雅退出（确保防抖窗口内的最后一次改动完成落盘）
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "🔄 正在关闭运行中的旧版本..."
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break
        sleep 0.2
    done
    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        echo "⚠️  旧版本未在 6 秒内退出，将强制结束（未落盘的改动可能丢失）"
        pkill -x "${APP_NAME}" || true
        sleep 1
    fi
fi

# 5. 安装：先在目标目录旁完成拷贝，再原子替换，避免中途失败留下半安装状态
echo "🚀 正在安装至 ${TARGET_DIR}..."
mkdir -p "${TARGET_DIR}"
STAGING_PATH="${TARGET_DIR}/.${APP_NAME}.installing.$$"
rm -rf "${STAGING_PATH}"
cp -R "${EXTRACTED_APP}" "${STAGING_PATH}"

BACKUP_PATH="${TARGET_DIR}/.${APP_NAME}.backup.$$"
if [ -d "${APP_PATH}" ]; then
    mv "${APP_PATH}" "${BACKUP_PATH}"
fi
if mv "${STAGING_PATH}" "${APP_PATH}"; then
    rm -rf "${BACKUP_PATH}"
else
    # 替换失败时回滚旧版本
    if [ -d "${BACKUP_PATH}" ]; then
        mv "${BACKUP_PATH}" "${APP_PATH}"
    fi
    rm -rf "${STAGING_PATH}"
    echo "❌ 安装失败，已回滚到原有版本。"
    exit 1
fi

# 6. 首次打开提示（不主动剥离隔离属性）
echo ""
echo "✨ Loose-Leaf (活页集) ${TAG} 安装更新成功！"
echo ""
echo "ℹ️  首次打开时，macOS 可能会提示「无法验证开发者」："
echo "    打开「系统设置 → 隐私与安全性」，在下方点击「仍要打开」即可。"
echo ""

# 7. 启动应用
open "${APP_PATH}"
echo "🎉 应用已启动！"
