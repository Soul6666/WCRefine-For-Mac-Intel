#import "WCRPatchProfiles.h"
#import "WCRCodePatch.h"

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld.h>
#import <arpa/inet.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <libkern/OSCacheControl.h>
#import <sys/mman.h>
#import <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr const char *kBundleIdentifier = "com.tencent.xinWeChat";
constexpr const char *kWeChatResourcesSuffix = "/Contents/Resources/wechat.dylib";

// 移植：按编译目标选切片，Intel 上就是 x86_64 那片。
#if defined(__x86_64__)
constexpr uint32_t kTargetCpuType = CPU_TYPE_X86_64;
constexpr const char *kTargetArchName = "x86_64";
#else
constexpr uint32_t kTargetCpuType = CPU_TYPE_ARM64;
constexpr const char *kTargetArchName = "arm64";
#endif

// Universal wechat.dylib SHA-256 evidence:
//   270135: 5f5a81c4d8b000dec1c7203738fc4dba75ce752b55874fc1b6b5869f9dfb1027
//   270351: 8b08e2f7af764ed4c3c28475d27fb3ebd74dd0de2515a5da677b07f02b88aebc
//   270353: d61eab4f61523936f84e3c98f57395edb15e45d3cd4291adb363e44e63375c98
//   270387: 47c8b5da00df9ec466bec50f04b99907c87fa06356924c6d0fc9003543e4f530
//   270390: 685914bfd55f9e102f3769d2f25e37a0735cd0ce41485b36d5df83de6eecd2b8
// 新构建只登记字节窗口唯一、且序言与字段访问都对得上的入口。
// 防撤回 cbz 在 0x4e79a44：两条 ADD 与 270135 相同，CBZ 立即数没变。
// 270351 到 270387 的解析器在补丁点前 0x270。270390 在前 0x278。
// 灰字仍写 +0x1D0、+0x218、+0x230。
const WCRPatchProfile kProfiles[] = {

    // ── x86_64 移植条目：微信 4.2.0 / build 270387（通用二进制）──
    // 定位依据见 INTEL-PORT.md。revokeParser 0x4e1a800（5216 B，对应 arm64
    // 0x464f498 / 4380 B）；静默点取 0x4e1aa87 的 `jne +0x50`
    // （对应 arm64 0x464f708 的 `cbz w0, skip` 强制跳走），
    // 改成 `jmp +0x50`：75 50 → EB 50，后两字节保持。
    // 消息字段偏移沿用 arm64；newmsgid 0x1C8 已在 x86_64 反汇编里亲眼见到
    // （movq %rax,0x1c8(%rbx)）。
    // messageFinalizerAddress 尚未定位 → 原文捕获会自报不可用。
    {
        .shortVersion = "4.2.0",
        .buildVersion = "270387",
        .displayVersion = "4.2.0.51-x86_64",
        .dylibSHA256 = "5fc03b1af653fcd1d5383ca6492e9263367a75374ddb6ef792e24e66a7bfb829",
        .patchAddress = 0,   // 2026-11-17 崩溃回退：插件入口跳板是 arm64 字节，x86_64 上会 SIGILL
        .expectedBytes = {0},
        .replacementBytes = {0},
        .revokeParserAddress = 0,
        .revokePrologue = {0xE5894855u, 0x56415741u, 0x54415541u, 0xEC814853u},
        .revokeNewMsgIdOffset = 0x1C8,
        .revokeReplaceMsgOffset = 0x1D0,
        // 2026-11-17 20:40 定位：messageFinalizer 0x4dbe110（272 字节）。
        // 形状与 arm64 0x45fc390 完全一致：
        //   movzbl 0x258(%rdi),%eax / xor $1 / or %sil / cmp $1 / jne
        // 之后 movq 0x220(%rbx),%rdi → callq *0x18(%rax) → movq 0xc(%rbx)，
        // 对应 arm64 的 ldr [x19,#0x220] / blr [x8,#0x18] / ldur [x19,#0xc]。
        // 续跑点 0x4dbe11e（arm64 取 0x45fc39c，即条件跳转那条）。
        .messageFinalizerAddress = 0,
        .messageFinalizerContinuation = 0x4dbe11e,
        .messageFinalizerPrologue = {0x5887B60Fu, 0x34000002u, 0xF0084001u, 0x850F013Cu},
        .messageServerIDOffset = 0xF8,
        .messageTypeOffset = 0x0C,
        .messageContentOffset = 0x130,
        .messageCreateTimeSecOffset = 0x114,
        .messageCreateTimeMsOffset = 0x100,
        .revokeDisplayCopyOffsetA = 0x218,
        .revokeDisplayCopyOffsetB = 0x230,
    },
    {
        .shortVersion = "4.1.15",
        .buildVersion = "270135",
        .displayVersion = "4.1.15.55",
        .dylibSHA256 = "5f5a81c4d8b000dec1c7203738fc4dba75ce752b55874fc1b6b5869f9dfb1027",
        .patchAddress = 0x4d1fb48,
        .expectedBytes = {0x40, 0x10, 0x00, 0x34},
        .replacementBytes = {0x82, 0x00, 0x00, 0x14},
        .revokeParserAddress = 0x4d1f8d8,
        .revokePrologue = {0xA9BC5FF8, 0xA90157F6, 0xA9024FF4, 0xA9037BFD},
        .revokeNewMsgIdOffset = 0x1C8,
        .revokeReplaceMsgOffset = 0x1D0,
        .messageFinalizerAddress = 0x4CBC3AC,
        .messageFinalizerContinuation = 0x4CBC3B8,
        .messageFinalizerPrologue = {0x39496008, 0x7100051F, 0x7A400820, 0x54000360},
        .messageServerIDOffset = 0xF8,
        .messageTypeOffset = 0x0C,
        .messageContentOffset = 0x130,
        // 构造函数 0x4cbb198 str w,[msg,#0x114]；紧接着 umull #1000 写入 #0x100。
        // 0x278 字节的消息数组按 #0x114 归并（0x3219c38）。只给消息捕获用。
        .messageCreateTimeSecOffset = 0x114,
        .messageCreateTimeMsOffset = 0x100,
        // sub_4D1F8D8 的 revoketime 路径：content → +0x1D0，再 operator= 到这两处。
        .revokeDisplayCopyOffsetA = 0x218,
        .revokeDisplayCopyOffsetB = 0x230,
        // 气泡「转发」可见性 sub_4D3AE38。类型在 x0+8。类型 34 原样返回 0。
        // 序言是普通建栈，可搬进 16 字节跳板。不是发送函数，voiceSendAddress 仍为 0。
        .voiceMenuGateAddress = 0x4D3AE38,
        .voiceMenuGatePrologue = {0xD10103FF, 0xA9024FF4, 0xA9037BFD, 0x9100C3FD},
        // 文本气泡右键菜单收口。复读只登记 270135；其它构建保持置灰。
        .repeatMenuBuilderAddress = 0xCF46AC,
        .repeatMenuBuilderPrologue = {0xA9BA6FFC, 0xA90167FA, 0xA9025FF8, 0xA90357F6},
        .avatarShapeAddress = 0x1f3c2cc,
        .avatarShapePrologue = {0xD104C3FF, 0x6D0C2BEB, 0x6D0D23E9, 0xA90E67FA},
        // mmui::ChatMasterView::OnSelectedSession。只改前 12 字节（sub/stp/add），
        // 第 4 条 adrp 留在 0x1361c4。序言不匹配就拒绝安装。
        .sessionSelectAddress = 0x1361b8,
        .sessionSelectPrologue = {0xD100C3FF, 0xA9027BFD, 0x910083FD},
        // IsNeedFilterMessage：ReceiveAddMsgList 在写库/刷新会话前调用。
        .messageFilterAddress = 0x31A1204,
        .messageFilterPrologue = {0xD10783FF, 0xA91A6FFC, 0xA91B57F6, 0xA91C4FF4},
    },
    {
        .shortVersion = "4.2.0",
        .buildVersion = "270351",
        .displayVersion = "4.2.0.15",
        .dylibSHA256 = "8b08e2f7af764ed4c3c28475d27fb3ebd74dd0de2515a5da677b07f02b88aebc",
        // 唯一的 ADD X0,X19,#0x10 / ADD X1,SP,#0xD8。前一条仍是 CBZ X0,+0x208。
        // 下一条 BL 立即数变了，整条 16 字节对不上；补丁只改这 4 字节。
        .patchAddress = 0x4e79a44,
        .expectedBytes = {0x40, 0x10, 0x00, 0x34},
        .replacementBytes = {0x82, 0x00, 0x00, 0x14},
        // 入口 = 补丁点 - 0x270。前 8 条与 270135 相同，跳板只搬前 16 字节。
        .revokeParserAddress = 0x4e797d4,
        .revokePrologue = {0xA9BC5FF8, 0xA90157F6, 0xA9024FF4, 0xA9037BFD},
        .revokeNewMsgIdOffset = 0x1C8,
        .revokeReplaceMsgOffset = 0x1D0,
        // 终结器 0x4e1638c。相对 270135 0x4cbc3ac 的前 0x64 字节相同，
        // 第一处不同是一条 BL 立即数。入口 b.eq 仍是 54000360，目标 = entry+0x78。
        .messageFinalizerAddress = 0x4e1638c,
        .messageFinalizerContinuation = 0x4e16398,
        .messageFinalizerPrologue = {0x39496008, 0x7100051F, 0x7A400820, 0x54000360},
        .messageServerIDOffset = 0xF8,
        .messageTypeOffset = 0x0C,
        .messageContentOffset = 0x130,
        // 构造函数 0x4e15168：str w,[x19,#0x114]；movz #1000；随后 str x,[x19,#0x100]。
        // 同函数 ldr x,[x19,#0x130]。终结器仍访问 +0x0C / +0xF8 / +0x218 / +0x230。
        .messageCreateTimeSecOffset = 0x114,
        .messageCreateTimeMsOffset = 0x100,
        // 0x4e7a420：ADD X0,X19,#0x218；ADD X1,X19,#0x1D0。下一条同样把 #0x230 赋过去。
        .revokeDisplayCopyOffsetA = 0x218,
        .revokeDisplayCopyOffsetB = 0x230,
        .voiceMenuGateAddress = 0x4e94da8,
        .voiceMenuGatePrologue = {0xD10103FF, 0xA9024FF4, 0xA9037BFD, 0x9100C3FD},
        // 长按菜单收口。前 16 字节与 270135 相同，内部窗口回推入口 0xd31de8。
        .repeatMenuBuilderAddress = 0xd31de8,
        .repeatMenuBuilderPrologue = {0xA9BA6FFC, 0xA90167FA, 0xA9025FF8, 0xA90357F6},
        .avatarShapeAddress = 0x1fabcd4,
        .avatarShapePrologue = {0xD104C3FF, 0x6D0C2BEB, 0x6D0D23E9, 0xA90E67FA},
        // 48 字节内部窗口在两份切片里都只命中一次，回推入口 0x135920。
        // 前 12 字节与 270135 相同。第 4 条仍是 adrp（b004da28），钩子留在原地。
        .sessionSelectAddress = 0x135920,
        .sessionSelectPrologue = {0xD100C3FF, 0xA9027BFD, 0x910083FD},
        // 270351：同一模板由 0x31A1204 编译位移到 0x32AAF68。
        .messageFilterAddress = 0x32AAF68,
        .messageFilterPrologue = {0xD10783FF, 0xA91A6FFC, 0xA91B57F6, 0xA91C4FF4},
        // 评论行 OnContextMenu 调用的菜单构建函数。前 16 字节是可搬走的 stp。
        // 第 5 条仍留在 0x1bfd68c。序言不匹配就拒绝安装。270135 不登记。
        .commentMenuBuilderAddress = 0x1bfd67c,
        .commentMenuBuilderPrologue = {0x6DB923E9, 0xA9016FFC, 0xA90267FA, 0xA9035FF8},
        // 多选控制器 0x7c9174：mov w8,#100；str w8,[x19,#0x38]。选择时和这个字段比。
        // 提示控件 0x7dc900：mov w8,#100；str w8,[x0,#0x200]。文案「最多选择%d条」。
        // 转发校验 0x49dab1c：向量字节长 >= 0x641（101×16）时错误码 2。
        // 三处窗口在 arm64 切片里都只出现一次。其它构建先不登记。
        .multiSelectControllerAddress = 0x7c9174,
        .multiSelectControllerWindow = {0x52800C88, 0xB9003A68, 0xF9400A60, 0x97EF9C9B},
        .multiSelectTipAddress = 0x7dc900,
        .multiSelectTipWindow = {0x52800C88, 0xB9020008, 0x52800021, 0x9463E2E2},
        .multiSelectForwardGateAddress = 0x49dab1c,
        .multiSelectForwardGateWindow = {
            0xA9402289, 0xCB090108, 0xF119051F, 0x54000063,
            0x52800048, 0x14000006, 0xAA1403E0, 0x52A80001},
        // 提示刷新 0x7dca64：ldr w8,[x19,#0x200] 后把这个数格式化进「最多选择%d条」。
        // 选择拒绝 0x7cc9bc、范围累加 0x7ccee8、溢出判断 0x7cd208 都是
        // ldr w8,[x19,#0x38] 再和已选条数比。对象若在补丁前建好，字段仍是 100。
        .multiSelectTooltipAddress = 0x7dca64,
        .multiSelectTooltipWindow = {0xB9420268, 0xF90003E8, 0x910043E8, 0x97E22C50},
        .multiSelectCountGateAddress = 0x7cc9bc,
        .multiSelectCountGateWindow = {0xB9403A68, 0x6B08001F, 0x54000E2A, 0xF9401260},
        .multiSelectRangeGateAddress = 0x7ccee8,
        .multiSelectRangeGateWindow = {0xB9403A68, 0x0B140014, 0x6B08029F, 0x540018AD},
        .multiSelectOverflowGateAddress = 0x7cd208,
        .multiSelectOverflowGateWindow = {0xB9403A68, 0x6B08029F, 0x1A9FD7E0, 0xF9405FF3},
        // 选择到这里 0x9459cc：虚调用 +0xc0 取出范围条数，cmp w0,#100，
        // b.lt 才继续。窗口在 arm64 切片里只出现一次。
        .multiSelectReachGateAddress = 0x9459cc,
        .multiSelectReachGateWindow = {
            0xF9400008, 0xF9406108, 0xAA0003F3, 0xD63F0100, 0x7101901F, 0x540004AB},
        // ChatVoiceItemViewModel 构造 0x78e98c。前 16 字节出现多次，44 字节只命中这一处。
        // 第 11 条是 bl，钩子只搬走前 4 条。
        .voiceAutoTextSetStateAddress = 0x78e98c,
        .voiceAutoTextSetStateWindow = {
            0xD10143FF, 0xA90257F6, 0xA9034FF4, 0xA9047BFD, 0x910103FD,
            0xAA0303F4, 0xAA0203F5, 0xAA0103F6, 0xAA0003F3, 0xD2800001,
            0x95A6C881},
        // sub_7954DC。菜单在视图模型 +256 那一位为 0 时用 w1=1 调用。
        // 32 字节只命中这一处。第 8 条是 adrp，只核对，不搬走。
        .voiceAutoTextOnClickAddress = 0x7954dc,
        .voiceAutoTextOnClickWindow = {
            0xD10483FF, 0xA90E6FFC, 0xA90F57F6, 0xA9104FF4, 0xA9117BFD,
            0x910443FD, 0xAA0003F3, 0xB004A728},
        .voiceAutoTextFeatureCheckAddress = 0,
    },
    {
        .shortVersion = "4.2.0",
        .buildVersion = "270353",
        .displayVersion = "4.2.0.17",
        .dylibSHA256 = "d61eab4f61523936f84e3c98f57395edb15e45d3cd4291adb363e44e63375c98",
        // 相对 270351 0x4e79a44 位移 +0x39c0。CBZ 立即数仍是 +0x208，
        // 后面两条仍是 ADD X0,X19,#0x10 和 ADD X1,SP,#0xD8。
        .patchAddress = 0x4e7d404,
        .expectedBytes = {0x40, 0x10, 0x00, 0x34},
        .replacementBytes = {0x82, 0x00, 0x00, 0x14},
        .revokeParserAddress = 0x4e7d194,
        .revokePrologue = {0xA9BC5FF8, 0xA90157F6, 0xA9024FF4, 0xA9037BFD},
        .revokeNewMsgIdOffset = 0x1C8,
        .revokeReplaceMsgOffset = 0x1D0,
        .messageFinalizerAddress = 0x4e19d4c,
        .messageFinalizerContinuation = 0x4e19d58,
        .messageFinalizerPrologue = {0x39496008, 0x7100051F, 0x7A400820, 0x54000360},
        .messageServerIDOffset = 0xF8,
        .messageTypeOffset = 0x0C,
        .messageContentOffset = 0x130,
        .messageCreateTimeSecOffset = 0x114,
        .messageCreateTimeMsOffset = 0x100,
        // 0x4e7dde0：ADD X0,X19,#0x218；ADD X1,X19,#0x1D0；再 ADD X0,X19,#0x230。
        .revokeDisplayCopyOffsetA = 0x218,
        .revokeDisplayCopyOffsetB = 0x230,
        .voiceMenuGateAddress = 0x4e98768,
        .voiceMenuGatePrologue = {0xD10103FF, 0xA9024FF4, 0xA9037BFD, 0x9100C3FD},
        .repeatMenuBuilderAddress = 0xd34fec,
        .repeatMenuBuilderPrologue = {0xA9BA6FFC, 0xA90167FA, 0xA9025FF8, 0xA90357F6},
        .avatarShapeAddress = 0x1faf0e0,
        .avatarShapePrologue = {0xD104C3FF, 0x6D0C2BEB, 0x6D0D23E9, 0xA90E67FA},
        // 前 12 字节与 270351 相同。第 4 条仍是 adrp，立即数变成 f004da28，钩子留在原地。
        .sessionSelectAddress = 0x137920,
        .sessionSelectPrologue = {0xD100C3FF, 0xA9027BFD, 0x910083FD},
        .messageFilterAddress = 0x32ae6ec,
        .messageFilterPrologue = {0xD10783FF, 0xA91A6FFC, 0xA91B57F6, 0xA91C4FF4},
        // 菜单入口序言与 270351 相同，但表情记录有两份相同函数体，评论复读不登记。
        .commentMenuBuilderAddress = 0x1c00a88,
        .commentMenuBuilderPrologue = {0x6DB923E9, 0xA9016FFC, 0xA90267FA, 0xA9035FF8},
    },
    {
        .shortVersion = "4.2.0",
        .buildVersion = "270387",
        .displayVersion = "4.2.0.51",
        .dylibSHA256 = "47c8b5da00df9ec466bec50f04b99907c87fa06356924c6d0fc9003543e4f530",
        // 解析器 0x464f498 后 0x270 仍是 CBZ W0,+0x208，
        // 接着 ADD X0,X19,#0x10 和 ADD X1,SP,#0xD8。整段只出现一次。
        .patchAddress = 0x464f708,
        .expectedBytes = {0x40, 0x10, 0x00, 0x34},
        .replacementBytes = {0x82, 0x00, 0x00, 0x14},
        .revokeParserAddress = 0x464f498,
        .revokePrologue = {0xA9BC5FF8, 0xA90157F6, 0xA9024FF4, 0xA9037BFD},
        .revokeNewMsgIdOffset = 0x1C8,
        .revokeReplaceMsgOffset = 0x1D0,
        .messageFinalizerAddress = 0x45fc390,
        .messageFinalizerContinuation = 0x45fc39c,
        .messageFinalizerPrologue = {0x39496008, 0x7100051F, 0x7A400820, 0x54000360},
        .messageServerIDOffset = 0xF8,
        .messageTypeOffset = 0x0C,
        .messageContentOffset = 0x130,
        .messageCreateTimeSecOffset = 0x114,
        .messageCreateTimeMsOffset = 0x100,
        // 解析器 +0xC4C：ADD X0,X19,#0x218；ADD X1,X19,#0x1D0；再 ADD X0,X19,#0x230。
        .revokeDisplayCopyOffsetA = 0x218,
        .revokeDisplayCopyOffsetB = 0x230,
        .voiceMenuGateAddress = 0x46684a4,
        .voiceMenuGatePrologue = {0xD10103FF, 0xA9024FF4, 0xA9037BFD, 0x9100C3FD},
        .repeatMenuBuilderAddress = 0xccbe90,
        .repeatMenuBuilderPrologue = {0xA9BA6FFC, 0xA90167FA, 0xA9025FF8, 0xA90357F6},
        // 绘制函数在 0x1dd2360，序言相同。XAvatar 虚表前几槽和大量控件共用，对不上，不登记。
        .sessionSelectAddress = 0x13561c,
        .sessionSelectPrologue = {0xD100C3FF, 0xA9027BFD, 0x910083FD},
        .messageFilterAddress = 0x2df0420,
        .messageFilterPrologue = {0xD10783FF, 0xA91A6FFC, 0xA91B57F6, 0xA91C4FF4},
        // 菜单序言对得上。表情记录仍有两份相同函数体，评论复读不登记。
        .commentMenuBuilderAddress = 0x1a6bfdc,
        .commentMenuBuilderPrologue = {0x6DB923E9, 0xA9016FFC, 0xA90267FA, 0xA9035FF8},
    },
    {
        .shortVersion = "4.2.0",
        .buildVersion = "270390",
        .displayVersion = "4.2.0.54",
        .dylibSHA256 = "685914bfd55f9e102f3769d2f25e37a0735cd0ce41485b36d5df83de6eecd2b8",
        // CBZ W0,+0x208 / ADD X0,X19,#0x10 / ADD X1,SP,#0xD8 只出现一次。
        // 解析器 0x4613ec4 后 0x278 就是这里。中间有一次提前返回，入口仍是这段序言。
        .patchAddress = 0x461413c,
        .expectedBytes = {0x40, 0x10, 0x00, 0x34},
        .replacementBytes = {0x82, 0x00, 0x00, 0x14},
        .revokeParserAddress = 0x4613ec4,
        .revokePrologue = {0xA9BC5FF8, 0xA90157F6, 0xA9024FF4, 0xA9037BFD},
        .revokeNewMsgIdOffset = 0x1C8,
        .revokeReplaceMsgOffset = 0x1D0,
        // 前 4 条与以往相同，而且这 4 条在切片里只出现一次。b.eq 仍是 54000360。
        .messageFinalizerAddress = 0x45c0b2c,
        .messageFinalizerContinuation = 0x45c0b38,
        .messageFinalizerPrologue = {0x39496008, 0x7100051F, 0x7A400820, 0x54000360},
        .messageServerIDOffset = 0xF8,
        .messageTypeOffset = 0x0C,
        .messageContentOffset = 0x130,
        .messageCreateTimeSecOffset = 0x114,
        .messageCreateTimeMsOffset = 0x100,
        // 0x4614904 把新消息 id 写到 +0x1C8。+0x1D0 仍是被替换的字符串。
        // 0x4614b50 起仍是 ADD #0x218、#0x1D0、#0x230。
        .revokeDisplayCopyOffsetA = 0x218,
        .revokeDisplayCopyOffsetB = 0x230,
        // 前 8 条与 270351 的语音菜单门完全相同，8 条只命中这一处。前 16 字节能搬走。
        .voiceMenuGateAddress = 0x462c82c,
        .voiceMenuGatePrologue = {0xD10103FF, 0xA9024FF4, 0xA9037BFD, 0x9100C3FD},
        // 长按菜单 0xccca9c。前 16 条与 270351 只差一条 adrp 和一条 ldr，16 条只命中这一处。
        .repeatMenuBuilderAddress = 0xccca9c,
        .repeatMenuBuilderPrologue = {0xA9BA6FFC, 0xA90167FA, 0xA9025FF8, 0xA90357F6},
        // 12 条归一化窗口只命中 0x1dcb5d8。前 4 条与 270351 相同。
        // 仍读 widget+0x1d4 的模式，以及 +0x1d8 / +0x1dc 的半径。
        // 三张虚表在 WCRAvatarRound 的 270390 行，+0x1c8 都指向这里。
        .avatarShapeAddress = 0x1dcb5d8,
        .avatarShapePrologue = {0xD104C3FF, 0x6D0C2BEB, 0x6D0D23E9, 0xA90E67FA},
        // 调用点 0x9ef46c：sturb wzr,[x29,#-0x38]；sub x1,x29,#0x38；mov x0,x19；bl。
        // 第 4 条是 adrp 9004bd48，钩子只改前 12 字节。
        .sessionSelectAddress = 0x135740,
        .sessionSelectPrologue = {0xD100C3FF, 0xA9027BFD, 0x910083FD},
        // 前 8 条与 270351 相同，调用点 0x2dd3c8c 仍是 add x1,sp,#0x210；mov x0,x27；bl。
        // x1 是消息。前 16 字节没有相对跳转。
        .messageFilterAddress = 0x2dd5228,
        .messageFilterPrologue = {0xD10783FF, 0xA91A6FFC, 0xA91B57F6, 0xA91C4FF4},
        // 解析器序言不是全库唯一，身份由唯一调用链确定。前 16 字节没有相对跳转。
        // 字符串赋值是解析器 0x45bf85c 和撤回灰字 0x4614b58 用的那一个。
        .messagePrepareAddress = 0x45bf724,
        .messagePreparePrologue = {0xD10643FF, 0xA9146FFC, 0xA9155FF8, 0xA91657F6},
        .messageStringAssignAddress = 0x6abcf78,
        // 两个评论长按入口都调用这里。辅助函数和虚表在 WCRCommentRepeat 的 270390 行。
        .commentMenuBuilderAddress = 0x1a66640,
        .commentMenuBuilderPrologue = {0x6DB923E9, 0xA9016FFC, 0xA90267FA, 0xA9035FF8},
        // 控制器 0x7a5508、提示 0x7b850c 仍是 mov w8,#100。转发 0x42264d4 的 b.lo 与 270351 相同。
        // 选择到这里 0x8fbf7c：虚调用槽从 +0xc0 挪到 +0xc8，cmp w0,#100 后的 b.lt 位移也变了。
        // 这 6 条只出现一次。安装时按实际 b.lt 改成同样位移的无条件跳转。
        .multiSelectControllerAddress = 0x7a5508,
        .multiSelectControllerWindow = {0x52800C88, 0xB9003A68, 0xF9400A60, 0x97EF9D80},
        .multiSelectTipAddress = 0x7b850c,
        .multiSelectTipWindow = {0x52800C88, 0xB9020008, 0x52800021, 0x945C4ED1},
        .multiSelectForwardGateAddress = 0x42264d4,
        .multiSelectForwardGateWindow = {
            0xA9402289, 0xCB090108, 0xF119051F, 0x54000063,
            0x52800048, 0x14000006, 0xAA1403E0, 0x52A80001},
        .multiSelectTooltipAddress = 0x7b8670,
        .multiSelectTooltipWindow = {0xB9420268, 0xF90003E8, 0x910043E8, 0x97E2C31F},
        .multiSelectCountGateAddress = 0x7a89ec,
        .multiSelectCountGateWindow = {0xB9403A68, 0x6B08001F, 0x54000D2A, 0xF9401260},
        .multiSelectRangeGateAddress = 0x7a8ed0,
        .multiSelectRangeGateWindow = {0xB9403A68, 0x0B140014, 0x6B08029F, 0x5400176D},
        .multiSelectOverflowGateAddress = 0x7a91c8,
        .multiSelectOverflowGateWindow = {0xB9403A68, 0x6B08029F, 0x1A9FD7E0, 0xF9405FF3},
        .multiSelectReachGateAddress = 0x8fbf7c,
        .multiSelectReachGateWindow = {
            0xF9400008, 0xF9406508, 0xAA0003F3, 0xD63F0100, 0x7101901F, 0x540003CB},
        // ChatVoiceItemViewModel 构造。前 10 条还有另一处，加上第 11 条 bl 后只命中这里。
        // 虚表 0x9552880 的槽和 270351 一样写到 +0x10、+0x4c0、+0x4c8、+0x500。
        // 前 16 字节是建栈，能搬走。
        .voiceAutoTextSetStateAddress = 0x77152c,
        .voiceAutoTextSetStateWindow = {
            0xD10143FF, 0xA90257F6, 0xA9034FF4, 0xA9047BFD, 0x910103FD,
            0xAA0303F4, 0xAA0203F5, 0xAA0103F6, 0xAA0003F3, 0xD2800001,
            0x9587624D},
        // 菜单在 +0x100 的最低位为 0 时，动作虚表 0x9553648 的槽尾调用这里，w1=1。
        // 32 字节只命中这一处。只核对，不改。
        .voiceAutoTextOnClickAddress = 0x777f1c,
        .voiceAutoTextOnClickWindow = {
            0xD10443FF, 0xA90E57F6, 0xA90F4FF4, 0xA9107BFD, 0x910403FD,
            0xAA0003F3, 0xD0048B28, 0xF9418108},
        .voiceAutoTextFeatureCheckAddress = 0,
        // 消息复制 0x3781ac 写入的 MessageData 虚表。和 270351 的 0xa002468 同一写法。
        .messageDataVtableAddress = 0x979f158,
    },

};

NSString *WCRErrorString(NSString *message) {
    return message ?: @"未知错误";
}

NSError *WCRError(NSString *message) {
    return [NSError errorWithDomain:@"WCRefineMac.Patch"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: WCRErrorString(message)}];
}

const WCRPatchProfile *WCRFindProfile(NSString *shortVersion, NSString *buildVersion) {
    for (const WCRPatchProfile &profile : kProfiles) {
        if (![shortVersion isEqualToString:@(profile.shortVersion)] ||
            ![buildVersion isEqualToString:@(profile.buildVersion)]) {
            continue;
        }
        return &profile;
    }
    return nullptr;
}

BOOL WCRFatArchArm64(const uint8_t *fileBytes,
                     size_t fileSize,
                     size_t *sliceOffset,
                     size_t *sliceSize,
                     NSError **error) {
    if (!fileBytes || fileSize < sizeof(uint32_t) || !sliceOffset || !sliceSize) {
        if (error) *error = WCRError(@"wechat.dylib 为空或长度不足");
        return NO;
    }
    uint32_t magicBE = 0;
    memcpy(&magicBE, fileBytes, sizeof(magicBE));
    magicBE = ntohl(magicBE);

    if (magicBE == FAT_MAGIC) {
        if (fileSize < 8) {
            if (error) *error = WCRError(@"FAT 头不完整");
            return NO;
        }
        uint32_t countBE = 0;
        memcpy(&countBE, fileBytes + 4, sizeof(countBE));
        uint32_t count = ntohl(countBE);
        if (count == 0 || count > 64) {
            if (error) *error = WCRError(@"FAT 架构数量非法");
            return NO;
        }
        size_t cursor = 8;
        for (uint32_t i = 0; i < count; ++i) {
            if (cursor > fileSize || fileSize - cursor < sizeof(fat_arch)) {
                if (error) *error = WCRError(@"FAT 架构表不完整");
                return NO;
            }
            fat_arch arch{};
            memcpy(&arch, fileBytes + cursor, sizeof(arch));
            cursor += sizeof(arch);
            uint32_t cpuType = ntohl(arch.cputype);
            uint32_t offset = ntohl(arch.offset);
            uint32_t size = ntohl(arch.size);
            if (cpuType != kTargetCpuType) continue;
            if (offset > fileSize || size > fileSize - offset) {
                if (error) *error = WCRError([NSString stringWithFormat:@"FAT %s 切片越界", kTargetArchName]);
                return NO;
            }
            *sliceOffset = offset;
            *sliceSize = size;
            return YES;
        }
        if (error) *error = WCRError([NSString stringWithFormat:@"微信不包含 %s 架构", kTargetArchName]);
        return NO;
    }

    if (fileSize < sizeof(mach_header_64)) {
        if (error) *error = WCRError(@"Mach-O 头不完整");
        return NO;
    }
    mach_header_64 header{};
    memcpy(&header, fileBytes, sizeof(header));
    if (header.magic != MH_MAGIC_64 || header.cputype != kTargetCpuType) {
        if (error) *error = WCRError([NSString stringWithFormat:@"wechat.dylib 不是 %s Mach-O", kTargetArchName]);
        return NO;
    }
    *sliceOffset = 0;
    *sliceSize = fileSize;
    return YES;
}

BOOL WCRFileOffsetForVA(const uint8_t *slice,
                        size_t sliceSize,
                        uint64_t targetVA,
                        uint64_t *fileOffset,
                        NSError **error) {
    if (!slice || sliceSize < sizeof(mach_header_64) || !fileOffset) {
        if (error) *error = WCRError(@"Mach-O 头不完整");
        return NO;
    }
    mach_header_64 header{};
    memcpy(&header, slice, sizeof(header));
    if (header.magic != MH_MAGIC_64 || header.cputype != kTargetCpuType) {
        if (error) *error = WCRError(@"不支持的 Mach-O 架构");
        return NO;
    }

    size_t commandOffset = sizeof(mach_header_64);
    for (uint32_t i = 0; i < header.ncmds; ++i) {
        if (commandOffset > sliceSize || sliceSize - commandOffset < sizeof(load_command)) {
            if (error) *error = WCRError(@"Mach-O load command 越界");
            return NO;
        }
        load_command command{};
        memcpy(&command, slice + commandOffset, sizeof(command));
        if (command.cmdsize < sizeof(load_command) ||
            commandOffset > sliceSize || command.cmdsize > sliceSize - commandOffset) {
            if (error) *error = WCRError(@"Mach-O load command 长度非法");
            return NO;
        }
        if (command.cmd == LC_SEGMENT_64) {
            if (command.cmdsize < sizeof(segment_command_64)) {
                if (error) *error = WCRError(@"LC_SEGMENT_64 长度非法");
                return NO;
            }
            segment_command_64 segment{};
            memcpy(&segment, slice + commandOffset, sizeof(segment));
            if (targetVA >= segment.vmaddr && targetVA - segment.vmaddr < segment.vmsize) {
                uint64_t delta = targetVA - segment.vmaddr;
                if (delta >= segment.filesize) {
                    if (error) *error = WCRError(@"补丁地址位于未映射文件区间");
                    return NO;
                }
                uint64_t offset = segment.fileoff + delta;
                if (offset > sliceSize || sliceSize - offset < 4) {
                    if (error) *error = WCRError(@"补丁地址映射越界");
                    return NO;
                }
                *fileOffset = offset;
                return YES;
            }
        }
        commandOffset += command.cmdsize;
    }

    if (error) *error = WCRError(@"未找到补丁地址所属的 Mach-O segment");
    return NO;
}

BOOL WCRVerifyDWordsAtVA(const uint8_t *slice,
                         size_t sliceSize,
                         uint64_t targetVA,
                         const uint32_t *expected,
                         size_t count,
                         NSString *label,
                         NSError **error) {
    if (!expected || count == 0) return YES;
    uint64_t offset = 0;
    if (!WCRFileOffsetForVA(slice, sliceSize, targetVA, &offset, error)) return NO;
    if (offset > sliceSize || count > (sliceSize - offset) / sizeof(uint32_t)) {
        if (error) *error = WCRError([NSString stringWithFormat:@"%@ 序言越界", label ?: @"入口"]);
        return NO;
    }
    for (size_t index = 0; index < count; ++index) {
        uint32_t actual = 0;
        memcpy(&actual, slice + offset + index * sizeof(uint32_t), sizeof(actual));
        if (actual != expected[index]) {
            if (error) {
                *error = WCRError([NSString stringWithFormat:
                    @"%@ 序言不匹配（0x%llX: 0x%08X != 0x%08X）",
                    label ?: @"入口",
                    (unsigned long long)(targetVA + index * 4),
                    actual,
                    expected[index]]);
            }
            return NO;
        }
    }
    return YES;
}

NSString *WCRDataSHA256(NSData *data) {
    if (!data) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    const uint8_t *bytes = static_cast<const uint8_t *>(data.bytes);
    size_t remaining = data.length;
    while (remaining > 0) {
        CC_LONG chunk = static_cast<CC_LONG>(std::min<size_t>(remaining, 1024 * 1024));
        CC_SHA256_Update(&context, bytes, chunk);
        bytes += chunk;
        remaining -= chunk;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {};
    CC_SHA256_Final(digest, &context);
    char hex[CC_SHA256_DIGEST_LENGTH * 2 + 1] = {};
    for (size_t index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) {
        snprintf(hex + index * 2, sizeof(hex) - index * 2, "%02x", digest[index]);
    }
    return @(hex);
}

BOOL WCRCheckDylibProfile(NSString *path,
                          const WCRPatchProfile *profile,
                          BOOL *matches,
                          BOOL *alreadyPatched,
                          NSString * _Nullable * _Nullable failureReason,
                          NSError **error) {
    if (!profile || !matches || !alreadyPatched) {
        if (error) *error = WCRError(@"缺少版本配置");
        return NO;
    }
    *matches = NO;
    *alreadyPatched = NO;
    if (failureReason) *failureReason = nil;

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path
                                         options:NSDataReadingMappedIfSafe
                                           error:&readError];
    if (!data) {
        if (error) *error = readError ?: WCRError(@"无法读取 wechat.dylib");
        return NO;
    }
    NSString *actualHash = WCRDataSHA256(data);
    NSString *expectedHash = profile->dylibSHA256 ? @(profile->dylibSHA256) : @"";
    if (expectedHash.length != 64) {
        if (error) *error = WCRError(@"版本配置缺少完整 wechat.dylib SHA-256");
        return NO;
    }
    if (![actualHash isEqualToString:expectedHash]) {
        if (failureReason) {
            *failureReason = [NSString stringWithFormat:
                @"wechat.dylib SHA-256 不匹配（当前 %@）", actualHash ?: @"未知"];
        }
        return YES;
    }

    size_t sliceOffset = 0;
    size_t sliceSize = 0;
    if (!WCRFatArchArm64(static_cast<const uint8_t *>(data.bytes),
                         data.length,
                         &sliceOffset,
                         &sliceSize,
                         error)) {
        return NO;
    }
    const uint8_t *slice = static_cast<const uint8_t *>(data.bytes) + sliceOffset;

    // 防撤回 cbz 还没对上时地址是 0。不能去读 VA 0（那是 Mach-O 头）。
    if (profile->patchAddress != 0) {
        uint64_t patchOffset = 0;
        if (!WCRFileOffsetForVA(slice, sliceSize, profile->patchAddress, &patchOffset, error)) {
            return NO;
        }
        if (patchOffset > sliceSize || sliceSize - patchOffset < sizeof(profile->expectedBytes)) {
            if (error) *error = WCRError(@"补丁地址映射越界");
            return NO;
        }
        const uint8_t *actual = slice + patchOffset;
        if (memcmp(actual, profile->expectedBytes, sizeof(profile->expectedBytes)) == 0) {
            *alreadyPatched = NO;
        } else if (memcmp(actual, profile->replacementBytes, sizeof(profile->replacementBytes)) == 0) {
            *alreadyPatched = YES;
        } else {
            NSMutableString *bytes = [NSMutableString string];
            for (size_t index = 0; index < sizeof(profile->expectedBytes); ++index) {
                [bytes appendFormat:@"%02X", actual[index]];
            }
            if (failureReason) {
                *failureReason = [NSString stringWithFormat:@"补丁点字节不匹配（当前 %@）", bytes];
            }
            return YES;
        }
    }

    struct EntryCheck {
        uint64_t address;
        const uint32_t *words;
        size_t count;
        NSString *label;
    };
    EntryCheck checks[] = {
        {profile->revokeParserAddress, profile->revokePrologue, 4, @"撤回解析入口"},
        {profile->messageFinalizerAddress, profile->messageFinalizerPrologue, 4, @"消息终结器"},
        {profile->voiceSendAddress, profile->voiceSendPrologue, 4, @"语音发送入口"},
        {profile->voiceMenuGateAddress, profile->voiceMenuGatePrologue, 4, @"语音菜单入口"},
        {profile->repeatMenuBuilderAddress, profile->repeatMenuBuilderPrologue, 4, @"复读菜单入口"},
        {profile->avatarShapeAddress, profile->avatarShapePrologue, 4, @"头像绘制入口"},
        {profile->sessionSelectAddress, profile->sessionSelectPrologue, 3, @"会话切换入口"},
        {profile->commentMenuBuilderAddress, profile->commentMenuBuilderPrologue, 4, @"朋友圈评论菜单入口"},
        {profile->messageFilterAddress, profile->messageFilterPrologue, 4, @"消息过滤入口"},
        {profile->messagePrepareAddress, profile->messagePreparePrologue, 4, @"消息解析入口"},
        {profile->multiSelectControllerAddress, profile->multiSelectControllerWindow, 4, @"多选上限"},
        {profile->multiSelectTipAddress, profile->multiSelectTipWindow, 4, @"多选提示上限"},
        {profile->multiSelectForwardGateAddress, profile->multiSelectForwardGateWindow, 8, @"多选转发条数"},
        {profile->multiSelectTooltipAddress, profile->multiSelectTooltipWindow, 4, @"多选提示条数"},
        {profile->multiSelectCountGateAddress, profile->multiSelectCountGateWindow, 4, @"多选条数拒绝"},
        {profile->multiSelectRangeGateAddress, profile->multiSelectRangeGateWindow, 4, @"多选范围累加"},
        {profile->multiSelectOverflowGateAddress, profile->multiSelectOverflowGateWindow, 4, @"多选溢出判断"},
        {profile->multiSelectReachGateAddress, profile->multiSelectReachGateWindow, 6, @"多选选择到这里"},
        {profile->voiceAutoTextSetStateAddress, profile->voiceAutoTextSetStateWindow, 11, @"语音视图构造"},
        {profile->voiceAutoTextOnClickAddress, profile->voiceAutoTextOnClickWindow, 8, @"语音转文字"},
        {profile->voiceAutoTextFeatureCheckAddress, profile->voiceAutoTextFeatureCheckWindow, 6, @"语音转文字开关"},
    };
    for (const EntryCheck &check : checks) {
        if (check.address == 0) continue;
        NSError *verifyError = nil;
        if (!WCRVerifyDWordsAtVA(slice, sliceSize, check.address, check.words, check.count,
                                 check.label, &verifyError)) {
            if (failureReason) *failureReason = verifyError.localizedDescription;
            return YES;
        }
    }

    *matches = YES;
    return YES;
}

BOOL WCREnsureArm64Dylib(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;
    size_t sliceOffset = 0;
    size_t sliceSize = 0;
    return WCRFatArchArm64(static_cast<const uint8_t *>(data.bytes),
                           data.length,
                           &sliceOffset,
                           &sliceSize,
                           error);
}

NSDictionary *WCRInfoPlist(NSString *appPath) {
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Contents/Info.plist"];
    return [NSDictionary dictionaryWithContentsOfFile:infoPath];
}

NSString *WCRDylibPath(NSString *appPath) {
    return [appPath stringByAppendingPathComponent:@"Contents/Resources/wechat.dylib"];
}

const void *WCRFindLoadedWeChatDylib(uintptr_t *slideOut) {
    for (uint32_t index = 0; index < _dyld_image_count(); ++index) {
        const char *imageName = _dyld_get_image_name(index);
        if (!imageName) continue;
        std::string path(imageName);
        if (path.size() < strlen(kWeChatResourcesSuffix) ||
            path.compare(path.size() - strlen(kWeChatResourcesSuffix),
                         strlen(kWeChatResourcesSuffix),
                         kWeChatResourcesSuffix) != 0) {
            continue;
        }
        if (slideOut) *slideOut = (uintptr_t)_dyld_get_image_vmaddr_slide(index);
        return _dyld_get_image_header(index);
    }
    return nullptr;
}

BOOL WCRWriteProcessBytes(uint8_t *target,
                          const uint8_t *bytes,
                          size_t length,
                          NSError **error) {
    return WCRPatchCodeBytes(target, bytes, length, error);
}

const WCRPatchProfile *WCRProfileForMainBundle(NSError **error) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleID = bundle.bundleIdentifier ?: @"";
    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    const char *selfTestValue = getenv("WCR_MAC_SELFTEST");
    BOOL selfTest = selfTestValue && strcmp(selfTestValue, "1") == 0;
    if (!WCRHostBundleIdentifierAllowed(bundleID, selfTest)) {
        if (error) *error = WCRError(@"插件只能加载到微信进程");
        return nullptr;
    }
    const WCRPatchProfile *profile = WCRFindProfile(shortVersion, buildVersion);
    if (!profile) {
        if (error) {
            *error = WCRError([NSString stringWithFormat:@"暂不支持当前微信构建 %@（%@）", buildVersion, shortVersion]);
        }
        return nullptr;
    }
    return profile;
}

BOOL WCRCheckCurrentProcessBytes(const WCRPatchProfile *profile,
                                 WCRPatchState *state,
                                 NSError **error) {
    if (!profile) {
        if (error) *error = WCRError(@"缺少版本配置");
        return NO;
    }
    if (profile->patchAddress == 0) {
        // 未登记不是“字节坏了”，也不是已经打上。调用方禁止就此写入。
        if (state) *state = WCRPatchStatePristine;
        return YES;
    }
    uintptr_t slide = 0;
    if (!WCRFindLoadedWeChatDylib(&slide)) {
        if (error) *error = WCRError(@"wechat.dylib 尚未加载");
        return NO;
    }
    uint8_t *address = (uint8_t *)(slide + profile->patchAddress);
    std::array<uint8_t, 4> current{};
    memcpy(current.data(), address, current.size());
    if (memcmp(current.data(), profile->expectedBytes, current.size()) == 0) {
        if (state) *state = WCRPatchStatePristine;
        return YES;
    }
    if (memcmp(current.data(), profile->replacementBytes, current.size()) == 0) {
        if (state) *state = WCRPatchStateApplied;
        return YES;
    }
    if (error) {
        NSMutableString *actual = [NSMutableString string];
        for (uint8_t byte : current) [actual appendFormat:@"%02X", byte];
        *error = WCRError([NSString stringWithFormat:@"补丁点字节不匹配（当前 %@）", actual]);
    }
    if (state) *state = WCRPatchStateInvalidBytes;
    return NO;
}

}  // namespace

BOOL WCRHostBundleIdentifierAllowed(NSString *bundleIdentifier, BOOL selfTest) {
    if (bundleIdentifier.length == 0) return NO;
    if ([bundleIdentifier isEqualToString:@(kBundleIdentifier)]) return YES;
    if ([bundleIdentifier hasPrefix:@"com.tencent.xinWeChat.WCRefineMulti"]) return YES;
    return selfTest && [bundleIdentifier hasPrefix:@"com.tencent.xinWeChat.WCRefineTest"];
}

const WCRPatchProfile *WCRCurrentProcessProfile(NSError **error) {
    return WCRProfileForMainBundle(error);
}

BOOL WCRInspectWeChatApp(NSString *appPath, WCRAppInspection *inspection, NSError **error) {
    if (!inspection) {
        if (error) *error = WCRError(@"缺少检查结果");
        return NO;
    }
    *inspection = {};
    inspection->shortVersion = @"";
    inspection->buildVersion = @"";
    inspection->wechatDylibPath = @"";
    inspection->failureReason = @"";

    NSDictionary *info = WCRInfoPlist(appPath);
    if (!info) {
        if (error) *error = WCRError(@"找不到微信 Info.plist");
        return NO;
    }
    NSString *bundleID = info[@"CFBundleIdentifier"] ?: @"";
    NSString *shortVersion = info[@"CFBundleShortVersionString"] ?: @"";
    NSString *buildVersion = info[@"CFBundleVersion"] ?: @"";
    inspection->shortVersion = shortVersion;
    inspection->buildVersion = buildVersion;
    if (![bundleID isEqualToString:@(kBundleIdentifier)]) {
        if (error) *error = WCRError(@"目标不是微信（bundle id 不匹配）");
        return NO;
    }

    NSString *dylibPath = WCRDylibPath(appPath);
    if (![[NSFileManager defaultManager] fileExistsAtPath:dylibPath]) {
        if (error) *error = WCRError(@"找不到 Contents/Resources/wechat.dylib");
        return NO;
    }
    inspection->wechatDylibPath = dylibPath;
    if (!WCREnsureArm64Dylib(dylibPath, error)) return NO;

    const WCRPatchProfile *profile = WCRFindProfile(shortVersion, buildVersion);
    if (!profile) {
        inspection->supported = NO;
        inspection->failureReason = [NSString stringWithFormat:@"暂不支持微信 %@（%@）", buildVersion, shortVersion];
        return YES;
    }

    BOOL matches = NO;
    BOOL alreadyPatched = NO;
    NSString *failureReason = nil;
    if (!WCRCheckDylibProfile(dylibPath, profile, &matches, &alreadyPatched,
                              &failureReason, error)) {
        return NO;
    }
    inspection->profile = *profile;
    inspection->supported = matches;
    inspection->alreadyPatched = alreadyPatched;
    inspection->failureReason = failureReason ?: @"";
    return YES;
}

BOOL WCRApplyAntiRevokePatch(NSError **error) {
    const WCRPatchProfile *profile = WCRProfileForMainBundle(error);
    if (!profile) return NO;
    if (profile->patchAddress == 0) {
        if (error) *error = WCRError(@"当前微信构建未登记防撤回补丁点");
        return NO;
    }
    WCRPatchState state = WCRPatchStateUnavailable;
    if (!WCRCheckCurrentProcessBytes(profile, &state, error)) return NO;
    if (state == WCRPatchStateApplied) return YES;

    uintptr_t slide = 0;
    if (!WCRFindLoadedWeChatDylib(&slide)) {
        if (error) *error = WCRError(@"wechat.dylib 尚未加载");
        return NO;
    }
    return WCRWriteProcessBytes((uint8_t *)(slide + profile->patchAddress),
                                profile->replacementBytes,
                                sizeof(profile->replacementBytes),
                                error);
}

BOOL WCRRestoreAntiRevokePatch(NSError **error) {
    const WCRPatchProfile *profile = WCRProfileForMainBundle(error);
    if (!profile) return NO;
    // 没登记补丁点就没有可恢复的 4 字节。关掉开关必须成功，否则勾着就关不掉。
    if (profile->patchAddress == 0) return YES;
    WCRPatchState state = WCRPatchStateUnavailable;
    if (!WCRCheckCurrentProcessBytes(profile, &state, error)) return NO;
    if (state == WCRPatchStatePristine) return YES;

    uintptr_t slide = 0;
    if (!WCRFindLoadedWeChatDylib(&slide)) {
        if (error) *error = WCRError(@"wechat.dylib 尚未加载");
        return NO;
    }
    return WCRWriteProcessBytes((uint8_t *)(slide + profile->patchAddress),
                                profile->expectedBytes,
                                sizeof(profile->expectedBytes),
                                error);
}

WCRPatchState WCRCurrentProcessPatchState(NSError **error) {
    const WCRPatchProfile *profile = WCRProfileForMainBundle(error);
    if (!profile) return WCRPatchStateUnavailable;
    WCRPatchState state = WCRPatchStateUnavailable;
    if (!WCRCheckCurrentProcessBytes(profile, &state, error)) return state;
    return state;
}

NSArray<NSString *> *WCRSupportedBuildDescriptions(void) {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (const WCRPatchProfile &profile : kProfiles) {
        [rows addObject:[NSString stringWithFormat:@"%@（%@）",
                                                   @(profile.displayVersion),
                                                   @(profile.buildVersion)]];
    }
    return rows;
}
