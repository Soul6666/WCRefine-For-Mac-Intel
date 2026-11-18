#!/bin/bash
# 修复注入／重装／升级微信后 macOS「屏幕录制（截图）」授权失效的问题。
#
# 原理：macOS 把屏幕录制授权绑定在可执行文件的 cdhash 上。安装器注入 dylib 后会
# 重新签名（adhoc），cdhash 变化，旧授权记录与正在运行的二进制对不上，于是微信
# 一直提示"请前往系统偏好设置允许微信访问录屏"，而设置面板里勾还在。
# 本脚本清掉那条失效记录，让微信下次截图时重新走一遍授权。
#
# 用法：
#   bash Installer/fix-screen-recording.sh [bundle-id]
#
# 不传 bundle-id 时默认原版／主副本使用的 com.tencent.xinWeChat。
# 多开副本请显式传自己的 id，例如：
#   bash Installer/fix-screen-recording.sh com.tencent.xinWeChat.WCRefineMulti2

set -euo pipefail

BUNDLE_ID="${1:-com.tencent.xinWeChat}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误: 这个脚本只能在 macOS 上运行。" >&2
    exit 1
fi

echo "→ 退出微信（bundle id: ${BUNDLE_ID}）…"

# 先礼貌地请微信自己退出，能保存会话
osascript -e 'tell application id "com.tencent.xinWeChat" to quit' >/dev/null 2>&1 || true
sleep 1

# 微信有多个进程，主进程退出后 helper 可能还挂着
for proc in WeChat WeChatAppEx XPlayer; do
    killall "$proc" 2>/dev/null || true
done
sleep 1

if pgrep -x WeChat >/dev/null 2>&1; then
    echo "  仍有进程残留，强制退出…"
    for proc in WeChat WeChatAppEx XPlayer; do
        killall -9 "$proc" 2>/dev/null || true
    done
    sleep 1
fi

if pgrep -x WeChat >/dev/null 2>&1; then
    echo "错误: 微信没能退出，请手动 ⌘Q 后再运行本脚本。" >&2
    exit 1
fi

echo "→ 清除「屏幕录制」授权记录…"
tccutil reset ScreenCapture "$BUNDLE_ID"

echo
echo "完成。现在重新打开微信，并随便截一次图："
echo "  系统会弹出「想要录制此电脑的屏幕」——点【允许】。"
echo
if [[ -d "${HOME}/Applications/WCRefine-WeChat.app" ]]; then
    echo "  副本:  open -n \"${HOME}/Applications/WCRefine-WeChat.app\""
fi
if [[ -d "/Applications/WeChat.app" ]]; then
    echo "  原版:  open -a /Applications/WeChat.app"
fi
echo
echo "若没有弹窗，去 系统设置 → 隐私与安全性 → 屏幕录制，"
echo "把「微信」那一项用 − 删掉，重新打开微信后再截一次图。"
