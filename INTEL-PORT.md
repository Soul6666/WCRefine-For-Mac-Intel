# Intel（x86_64）移植说明

这是 [plumblossom26/WCRefine-For-Mac](https://github.com/plumblossom26/WCRefine-For-Mac) 的
x86_64 移植分支。原项目仅支持 Apple Silicon（arm64），本分支让它能在 Intel Mac 上编译、
注入、启动。

> 上游 MIT 许可，版权归原作者所有。本分支只做架构移植，未改变上游的授权条款；
> 原始 `LICENSE` 与版权声明原样保留。**不是官方版本**，问题请报给本分支，不要打扰上游作者。

## 当前状态

| 分类 | 功能 | Intel 状态 |
| --- | --- | --- |
| 纯 swizzle（不吃锚点） | 禁用截图检测、原始 ID、联系人名称、桌宠、微信多开 | ✅ 可用 |
| 机器码补丁 | 静默防撤回、撤回原文、消息屏蔽、圆角头像、消息复读、朋友圈评论复读、多选突破、语音转发、会话置顶 | ❌ 未登记，功能自报不可用 |

未登记不会乱写内存：插件会返回「当前微信构建尚未登记」，对应菜单项置灰。

## 已经完成的移植改动

| # | 改动 | 文件 |
| --- | --- | --- |
| 1 | `-arch arm64` → `ARCH ?= arm64`，用 `make ARCH=x86_64` 出 Intel 版 | `Makefile` |
| 2 | x86_64 下 `std::function` 的 ABI 尺寸不同（0xA0 vs 0x70），断言按目标架构分开 | `Sources/WCRRecallNotify.mm` |
| 3 | 注入器按宿主架构选 Mach-O 切片，不再写死 `CPU_TYPE_ARM64` | `Sources/WCRMachOInjector.mm` |
| 4 | profile 模块里切片选择同样按架构参数化（否则会去读 arm64 切片） | `Sources/WCRPatchProfiles.mm` |
| 5 | 校验器与安装脚本放行 x86_64 | `Tools/wcrefine-check.m`、`Installer/install.sh` |
| 6 | 6 个使用 ARM64 内联汇编的功能先用同签名空壳顶住，保证能编译链接 | `Sources/WCRX64Stubs.mm` |

`Sources/WCRX64Stubs.mm` 里每个空壳都对应一个待移植的汇编钩子：
`WCRAvatarRound`、`WCRCommentRepeat`、`WCRMessageBlock`、`WCRMessageCapture`、
`WCRMessageRepeat`、`WCRSessionSelect`。重写完一个，就删掉对应空壳。

## 构建

需要 Xcode Command Line Tools。

```bash
make ARCH=x86_64 all          # build/WCRefineMac.dylib、wcrefine-check、管理 App
./build/wcrefine-check --app /Applications/WeChat.app
bash Installer/install.sh --app /Applications/WeChat.app
open -n ~/Applications/WCRefine-WeChat.app
```

arm64 仍可按上游方式构建（`ARCH` 默认 `arm64`）。

## 移植机器码锚点的注意事项（踩过的坑）

1. **入口跳板是架构相关的。** 上游在函数入口装的跳板写的是 arm64 指令字节。
   如果只为 x86_64 填了函数入口地址（`revokeParserAddress`、`messageFinalizerAddress`
   以及与之配套的 `*Prologue` 字段），插件会把 arm64 跳板写进 x86_64 代码，
   执行时 `EXC_BAD_INSTRUCTION / SIGILL` 直接崩溃。
   **跳板本身改成 x86_64 之前，这些字段必须留 0。** 只有纯 4 字节替换（`patchAddress` +
   `expectedBytes`/`replacementBytes`）在语义上不依赖指令编码，但要自己确认字节。
2. **消息结构体偏移在不同架构间一致。** 已在反汇编里确认 `0x1C8`（newmsgid）、
   `0x0C`（type）、`0x130`（content）、`0x258`、`0x220`、`0x230` 在两份切片里含义相同，
   因此 `messageServerIDOffset` / `messageContentOffset` 等可沿用上游数值。
3. **不要指望按函数序号或序言字节批量对齐两个架构。** 实测 arm64 与 x86_64 的函数数量
   不同（367,295 vs 370,511），漂移非线性；跨架构栈帧布局不同，`sub rsp,0x130`
   这类模式在另一侧根本不存在。只能逐个按语义定位。

## 许可

上游 MIT。见 `LICENSE` 与 `THIRD_PARTY_NOTICES.md`。修改微信客户端可能违反服务条款，
存在封号与数据风险，自担。
