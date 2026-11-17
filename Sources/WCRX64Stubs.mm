// x86_64 移植用的空实现：这 6 个功能的正文本体是 arm64 内联汇编，
// 在 Intel 上要按 x86_64 重写钩子。先给出同签名的空壳，
// 让 dylib 能编译链接、其余功能可用；重写完一个就删一个空壳。
#if defined(__x86_64__)
#import "WCRAvatarRound.h"
#import "WCRCommentRepeat.h"
#import "WCRMessageBlock.h"
#import "WCRMessageCapture.h"
#import "WCRMessageRepeat.h"
#import "WCRSessionSelect.h"

NSInteger WCRAvatarRoundRadiusPercent(void) { return 0; }
void WCRAvatarRoundSetRadiusPercent(NSInteger percent) {}
BOOL WCRAvatarRoundSupportsProfile(const WCRPatchProfile *profile) { return NO; }
BOOL WCRAvatarRoundInstall(NSError **error) { return NO; }
BOOL WCRAvatarRoundUninstall(NSError **error) { return NO; }
BOOL WCRAvatarRoundIsInstalled(void) { return NO; }
void WCRAvatarRoundRefreshPrefs(void) {}
BOOL WCRCommentRepeatSupportsProfile(const WCRPatchProfile * _Nullable profile) { return NO; }
BOOL WCRCommentRepeatInstall(const WCRPatchProfile *profile, NSError **error) { return NO; }
BOOL WCRCommentRepeatUninstall(NSError **error) { return NO; }
BOOL WCRCommentRepeatIsInstalled(void) { return NO; }
BOOL WCRMessageBlockSupportsProfile(const WCRPatchProfile * _Nullable profile) { return NO; }
BOOL WCRMessageBlockInstall(const WCRPatchProfile *profile, NSError **error) { return NO; }
BOOL WCRMessageBlockUninstall(NSError **error) { return NO; }
BOOL WCRMessageBlockIsInstalled(void) { return NO; }
BOOL WCRMessageBlockEnabled(void) { return NO; }
void WCRMessageBlockSetEnabled(BOOL enabled) {}
BOOL WCRMessageBlockIsSessionBlocked(NSString *session) { return NO; }
BOOL WCRMessageBlockValidSessionID(NSString * _Nullable session) { return NO; }
BOOL WCRMessageBlockSetSessionBlocked(NSString *session, BOOL blocked) { return NO; }
BOOL WCRMessageBlockReplaceSessions(NSArray<NSString *> * _Nullable sessions) { return NO; }
void WCRMessageBlockClearSessions(void) {}
void WCRMessageBlockSetSelectedTypes(NSArray<NSString *> * _Nullable types) {}
BOOL WCRMessageBlockTypeIsSelected(NSString * _Nullable typeKey) { return NO; }
BOOL WCRMessageBlockSessionUsesCustomTypes(NSString * _Nullable session) { return NO; }
NSArray<NSString *> * _Nullable WCRMessageBlockCustomTypesForSession(NSString * _Nullable session) { return nil; }
void WCRMessageBlockSetCustomTypesForSession(NSString *session,
                                             NSArray<NSString *> * _Nullable types) {}
BOOL WCRMessageBlockTypeIsSelectedForSession(NSString * _Nullable session,
                                             NSString * _Nullable typeKey) { return NO; }
BOOL WCRMessageBlockShowTip(void) { return NO; }
void WCRMessageBlockSetShowTip(BOOL show) {}
NSString * _Nullable WCRMessageBlockTypeKeyForMessageType(uint32_t messageType,
                                                         NSString * _Nullable content) { return nil; }
NSString * _Nullable WCRMessageBlockResolveSession(NSString * _Nullable fromUser,
                                                   NSString * _Nullable toUser,
                                                   NSString * _Nullable selfUser) { return nil; }
BOOL WCRMessageBlockShouldFilterMessageObject(const void * _Nullable message) { return NO; }
void WCRMessageBlockPrepareSource(void * _Nullable source) {}
BOOL WCRMessageCaptureSupportsProfile(const WCRPatchProfile *profile) { return NO; }
BOOL WCRMessageCaptureInstall(const WCRPatchProfile *profile, NSError **error) { return NO; }
BOOL WCRMessageCaptureUninstall(NSError **error) { return NO; }
BOOL WCRMessageCaptureIsInstalled(void) { return NO; }
void WCRMessageCaptureSetContentCaptureEnabled(BOOL enabled) {}
void WCRMessageCaptureSetObjectObserver(WCRMessageCaptureObjectObserver _Nullable observer) {}
NSString * _Nullable WCRMessageCaptureContent(uint64_t serverID) { return nil; }
NSUInteger WCRMessageCaptureType(uint64_t serverID) { return 0; }
uint32_t WCRMessageCaptureCreateTime(uint64_t serverID) { return 0; }
BOOL WCRMessageRepeatSupportsProfile(const WCRPatchProfile * _Nullable profile) { return NO; }
BOOL WCRMessageRepeatInstall(const WCRPatchProfile *profile, NSError **error) { return NO; }
BOOL WCRMessageRepeatUninstall(NSError **error) { return NO; }
BOOL WCRMessageRepeatIsInstalled(void) { return NO; }
BOOL WCRSessionSelectInstall(const WCRPatchProfile *profile, NSError **error) { return NO; }
BOOL WCRSessionSelectUninstall(NSError **error) { return NO; }
BOOL WCRSessionSelectIsInstalled(void) { return NO; }
#endif

// 容器类返回值和那个全局常量，生成器没覆盖到，手补。
#if defined(__x86_64__)
NSArray<NSString *> *WCRMessageBlockSessions(void) { return @[]; }
NSArray<NSString *> *WCRMessageBlockAllTypeKeys(void) { return @[]; }
NSString *WCRMessageBlockTitleForTypeKey(NSString * _Nullable typeKey) { return typeKey ?: @""; }
NSString *WCRMessageBlockTypeSummary(void) { return @""; }
NSArray<NSString *> *WCRMessageBlockSelectedTypes(void) { return @[]; }
NSString *const kWCRMessageBlockTypeText = @"text";
#endif
