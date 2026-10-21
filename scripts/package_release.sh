#!/bin/bash
# 统一打包入口：构建 → 打包 → 清理中间产物
#
# 为什么需要它：
#   此前 CI 与本机各跑各的 xcodebuild + ditto 命令，而 SYMROOT 固定指向
#   `build/Sym`。CI 跑在一次性 runner 上无所谓，**本机手动跑**却会一次次
#   往 `build/Sym/Release/` 里堆旧 zip 与 LooseLeaf.app —— 于是 Spotlight 里
#   能搜出七八个「LooseLeaf.app」，磁盘也白占好几个 G。
#
# 现在：
#   - 中间产物全部放进 mktemp 临时目录，用完即删（trap EXIT 兜底）
#   - 只有最终的 zip 交付到 --output-dir
#   - CI 与本机共用这一条路径，不会再各写各的
#
# 用法：
#   scripts/package_release.sh --tag v1.7.1 --output-dir dist
#   scripts/package_release.sh --clean-stale      # 只清理历史遗留的 build/ 目录

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

PROJECT="LooseLeaf.xcodeproj"
TARGET="LooseLeaf"
CONFIG="Release"
OUTPUT_DIR="${REPO_ROOT}/dist"
TAG=""
CLEAN_STALE=0

usage() {
    cat <<'EOF'
用法: scripts/package_release.sh [选项]

  --tag <tag>       版本标签（如 v1.7.1）。给了就产出 LooseLeaf-<tag>-arm64.zip
  --output-dir <d>  产物输出目录（默认 <repo>/dist）
  --clean-stale     额外清理历史遗留的 mac/build/ 目录（本机手动打包留下的）
  -h, --help        显示本帮助
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag)         TAG="${2:?--tag 需要一个值}"; shift 2 ;;
        --output-dir)  OUTPUT_DIR="${2:?--output-dir 需要一个值}"; shift 2 ;;
        --clean-stale) CLEAN_STALE=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "❌ 未知参数: $1"; echo; usage; exit 1 ;;
    esac
done

# ── 只清理历史遗留 ────────────────────────────────────────────────
if [ "${CLEAN_STALE}" -eq 1 ]; then
    if [ -d "${REPO_ROOT}/build" ]; then
        echo "🧹 清理历史遗留的 build/ 目录..."
        rm -rf "${REPO_ROOT}/build"
    fi
fi

# ── 构建 ─────────────────────────────────────────────────────────
WORK_DIR="$(mktemp -d -t looseleaf_package_XXXXXX)"
cleanup() {
    # 中间产物用完即删；本脚本不应在磁盘上留下任何构建残留
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "🔨 构建 ${TARGET} (${CONFIG})..."
xcodebuild -project "${PROJECT}" -target "${TARGET}" -configuration "${CONFIG}" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    SYMROOT="${WORK_DIR}/Sym" build > "${WORK_DIR}/build.log" 2>&1 || {
        echo "❌ 构建失败，日志末尾："
        tail -40 "${WORK_DIR}/build.log"
        exit 1
    }

APP_PATH="${WORK_DIR}/Sym/${CONFIG}/${TARGET}.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "❌ 构建产物缺失: ${APP_PATH}"
    exit 1
fi

# ── 打包 ─────────────────────────────────────────────────────────
mkdir -p "${OUTPUT_DIR}"
if [ -n "${TAG}" ]; then
    ZIP_NAME="${TARGET}-${TAG}-arm64.zip"
else
    ZIP_NAME="${TARGET}-macOS-arm64.zip"
fi
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

echo "📦 打包为 ${ZIP_NAME}..."
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "✅ 完成: ${ZIP_PATH}"
ls -lh "${ZIP_PATH}"
