#!/usr/bin/env bash
set -euo pipefail

# Loose-Leaf (活页集) macOS 极速一键安装与更新脚本
# 用法：/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Losse-Leaf/MacOS/main/install.sh)"

APP_NAME="LooseLeaf"
REPO="Losse-Leaf/MacOS"
TARGET_DIR="/Applications"
APP_PATH="${TARGET_DIR}/${APP_NAME}.app"

echo "🍃 正在获取 Loose-Leaf (活页集) 最新版本信息..."

# 1. 查询 GitHub Releases 最新版本信息
RELEASE_JSON=$(curl -sSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || echo "")

if [ -z "${RELEASE_JSON}" ] || echo "${RELEASE_JSON}" | grep -q '"message":'; then
    # 回退到已知稳定 tag
    TAG="v1.2.5"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/LooseLeaf-${TAG}-arm64.zip"
else
    TAG=$(echo "${RELEASE_JSON}" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    DOWNLOAD_URL=$(echo "${RELEASE_JSON}" | grep '"browser_download_url":' | grep -i "arm64.zip" | head -n 1 | cut -d '"' -f 4)
    if [ -z "${DOWNLOAD_URL}" ]; then
        DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/LooseLeaf-${TAG}-arm64.zip"
    fi
fi

echo "📦 准备安装版本: ${TAG}"
echo "🔗 下载地址: ${DOWNLOAD_URL}"

# 2. 创建临时工作目录
TMP_DIR=$(mktemp -d -t looseleaf_install_XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

ZIP_PATH="${TMP_DIR}/LooseLeaf.zip"

echo "⬇️  正在下载应用包..."
curl -# -L "${DOWNLOAD_URL}" -o "${ZIP_PATH}"

# 3. 解压产物
echo "📂 正在解压应用..."
unzip -q -o "${ZIP_PATH}" -d "${TMP_DIR}"

# 查找解压出的 .app 目录
EXTRACTED_APP=$(find "${TMP_DIR}" -name "${APP_NAME}.app" -maxdepth 3 | head -n 1)

if [ -z "${EXTRACTED_APP}" ] || [ ! -d "${EXTRACTED_APP}" ]; then
    echo "❌ 解压失败，未找到 ${APP_NAME}.app！"
    exit 1
fi

# 4. 如果旧应用正在运行，先退出
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "🔄 正在关闭运行中的旧版本..."
    pkill -x "${APP_NAME}" || true
    sleep 1
fi

# 5. 复制安装至 /Applications
echo "🚀 正在安装至 ${TARGET_DIR}..."
if [ -d "${APP_PATH}" ]; then
    rm -rf "${APP_PATH}"
fi

cp -R "${EXTRACTED_APP}" "${TARGET_DIR}/"

# 6. 核心：剥离 macOS Gatekeeper Quarantine 网络下载隔离属性，彻底杜绝“已损坏”提示
echo "🛡️  正在自动放行 Gatekeeper 安全隔离属性 (xattr -cr)..."
xattr -cr "${APP_PATH}" 2>/dev/null || true

echo "✨ Loose-Leaf (活页集) ${TAG} 安装更新成功！"

# 7. 自动启动应用
open "${APP_PATH}"
echo "🎉 应用已启动！"
