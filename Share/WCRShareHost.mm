#import "../Sources/WCROtherApps.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static NSString *const kWCRShareGeneratorVersion = @"2";
static NSString *const kWCRSharePluginkit = @"/usr/bin/pluginkit";
static NSString *const kWCRShareLsregister =
    @"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

static BOOL gHasEnabledList = NO;
static NSString *gEnabledList = nil;
static BOOL gWantsDeliver = NO;

static NSString *WCRShareSupportDirectory(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/WCRefine"];
}

static NSString *WCRShareEntriesDirectory(void) {
    return [WCRShareSupportDirectory() stringByAppendingPathComponent:@"Share Entries"];
}

static NSString *WCRShareRelayDirectory(void) {
    return [WCRShareSupportDirectory() stringByAppendingPathComponent:@"Relay"];
}

static void WCRShareLog(NSString *message) {
    if (message.length == 0) return;
    NSString *directory = WCRShareSupportDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSString *path = [directory stringByAppendingPathComponent:@"share.log"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static void WCRShareWriteStatus(NSString *message) {
    NSString *directory = WCRShareSupportDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"share-status.plist"]];
    if (message.length == 0) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        return;
    }
    [@{@"message" : message} writeToURL:url atomically:YES];
}

static void WCRShareNotify(NSString *message) {
    if (message.length == 0) return;
    NSString *escaped = [message stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/osascript";
    task.arguments = @[@"-e",
        [NSString stringWithFormat:@"display notification \"%@\" with title \"WCRefine\"", escaped]];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        WCRShareLog(exception.reason);
    }
}

static NSString *WCRShareRun(NSString *launchPath, NSArray<NSString *> *arguments, int *status) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments ?: @[];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (status) *status = 1;
        return exception.reason ?: @"命令没有启动";
    }
    if (status) *status = task.terminationStatus;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *WCRShareIconSource(NSURL *applicationURL) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:
        [applicationURL URLByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *iconFile = [info[@"CFBundleIconFile"] isKindOfClass:[NSString class]] ? info[@"CFBundleIconFile"] : nil;
    if (iconFile.length > 0 && iconFile.pathExtension.length == 0) {
        iconFile = [iconFile stringByAppendingPathExtension:@"icns"];
    }
    NSString *resources = [applicationURL.path stringByAppendingPathComponent:@"Contents/Resources"];
    if (iconFile.length > 0) {
        NSString *candidate = [resources stringByAppendingPathComponent:iconFile];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    }
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:resources error:nil];
    for (NSString *name in names) {
        if ([name.pathExtension.lowercaseString isEqualToString:@"icns"]) {
            return [resources stringByAppendingPathComponent:name];
        }
    }
    return nil;
}

static BOOL WCRShareWriteIcon(NSURL *applicationURL, NSURL *destination, NSError **error) {
    NSString *existing = WCRShareIconSource(applicationURL);
    if (existing.length > 0) {
        return [[NSFileManager defaultManager] copyItemAtPath:existing toPath:destination.path error:error];
    }
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:applicationURL.path];
    if (!icon) {
        if (error) *error = [NSError errorWithDomain:@"com.wcrefine.mac.other-apps" code:10 userInfo:@{
            NSLocalizedDescriptionKey : @"没有拿到应用图标。"
        }];
        return NO;
    }
    NSString *png = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"wcrefine-icon-%@.tiff", NSUUID.UUID.UUIDString]];
    NSData *tiff = [icon TIFFRepresentation];
    if (![tiff writeToFile:png atomically:YES]) return NO;
    int status = 0;
    WCRShareRun(@"/usr/bin/sips", @[@"-s", @"format", @"icns", png, @"--out", destination.path], &status);
    [[NSFileManager defaultManager] removeItemAtPath:png error:nil];
    return status == 0 && [[NSFileManager defaultManager] fileExistsAtPath:destination.path];
}

static NSDictionary *WCRShareExtensionInfo(const WCROtherAppSpec *spec,
                                           NSString *appexIdentifier,
                                           NSString *targetBundleIdentifier) {
    NSString *rule =
        @"SUBQUERY (\n"
        @"                extensionItems,\n"
        @"                $extensionItem,\n"
        @"                SUBQUERY (\n"
        @"                    $extensionItem.attachments,\n"
        @"                    $attachment,\n"
        @"                    ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO \"public.zip-archive\"\n"
        @"                ).@count == 1\n"
        @"            ).@count == 1";
    return @{
        @"CFBundleDevelopmentRegion" : @"zh-Hans",
        @"CFBundleDisplayName" : spec->title,
        @"CFBundleExecutable" : @"WCRefineShare",
        @"CFBundleIdentifier" : appexIdentifier,
        @"CFBundleInfoDictionaryVersion" : @"6.0",
        @"CFBundleName" : spec->title,
        @"CFBundlePackageType" : @"XPC!",
        @"CFBundleShortVersionString" : @"2.0.0",
        @"CFBundleVersion" : @"1",
        @"LSMinimumSystemVersion" : @"12.0",
        @"WCRTargetBundleIdentifier" : targetBundleIdentifier,
        @"WCRTargetDisplayName" : spec->title,
        @"NSExtension" : @{
            @"NSExtensionAttributes" : @{@"NSExtensionActivationRule" : rule},
            @"NSExtensionPointIdentifier" : @"com.apple.share-services",
            @"NSExtensionPrincipalClass" : @"WCRShareViewController",
        },
    };
}

static NSDictionary *WCRShareHostInfo(const WCROtherAppSpec *spec, NSString *hostIdentifier) {
    return @{
        @"CFBundleDevelopmentRegion" : @"zh-Hans",
        @"CFBundleDisplayName" : spec->title,
        @"CFBundleExecutable" : @"WCRefineShareHost",
        @"CFBundleIconFile" : @"AppIcon",
        @"CFBundleIdentifier" : hostIdentifier,
        @"CFBundleInfoDictionaryVersion" : @"6.0",
        @"CFBundleName" : spec->title,
        @"CFBundlePackageType" : @"APPL",
        @"CFBundleShortVersionString" : @"2.0.0",
        @"CFBundleVersion" : @"1",
        @"LSMinimumSystemVersion" : @"12.0",
        @"LSUIElement" : @YES,
        @"NSHighResolutionCapable" : @YES,
    };
}

static BOOL WCRShareElected(NSString *appexIdentifier) {
    int status = 0;
    NSString *output = WCRShareRun(kWCRSharePluginkit, @[@"-m", @"-i", appexIdentifier], &status);
    for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if ([line containsString:appexIdentifier] && [line hasPrefix:@"+"]) return YES;
    }
    return NO;
}

static void WCRShareRemoveEntry(NSString *appPath) {
    NSString *appex = [appPath stringByAppendingPathComponent:@"Contents/PlugIns/WCRefineShare.appex"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:appex]) {
        int status = 0;
        WCRShareRun(kWCRSharePluginkit, @[@"-r", appex], &status);
    }
    int status = 0;
    WCRShareRun(kWCRShareLsregister, @[@"-u", appPath], &status);
    [[NSFileManager defaultManager] removeItemAtPath:appPath error:nil];
}

static NSString *WCRShareStamp(const WCROtherAppSpec *spec,
                               NSString *templatePath,
                               NSString *targetBundleIdentifier) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:templatePath error:nil];
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
        kWCRShareGeneratorVersion, spec->identifier, spec->title, targetBundleIdentifier,
        attributes[NSFileModificationDate] ?: @0];
}

static BOOL WCRShareInstall(const WCROtherAppSpec *spec, NSString **errorMessage) {
    NSBundle *host = [NSBundle mainBundle];
    NSString *templateAppex = [host.bundlePath stringByAppendingPathComponent:
        @"Contents/Helpers/WCRefineShare.appex"];
    NSString *templateBinary = [templateAppex stringByAppendingPathComponent:@"Contents/MacOS/WCRefineShare"];
    NSString *stub = [host.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/WCRefineShareHost"];
    NSString *entitlements = [host.bundlePath stringByAppendingPathComponent:@"Contents/Resources/Share.entitlements"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:templateBinary] ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:stub]) {
        if (errorMessage) *errorMessage = @"其他应用扩展缺少入口文件，请重新覆盖安装。";
        return NO;
    }
    NSURL *targetApp = WCROtherAppApplicationURL(spec);
    NSString *targetBundleIdentifier = targetApp
        ? [[NSBundle bundleWithURL:targetApp] bundleIdentifier] : nil;
    if (!targetApp || targetBundleIdentifier.length == 0) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"没有找到 %@。", spec->applicationName];
        return NO;
    }
    NSString *hostIdentifier = [@"com.wcrefine.mac.entry." stringByAppendingString:spec->identifier];
    NSString *appexIdentifier = [@"com.wcrefine.mac.share." stringByAppendingString:spec->identifier];
    NSString *entries = WCRShareEntriesDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:entries
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *destination = [entries stringByAppendingPathComponent:
        [spec->identifier stringByAppendingPathExtension:@"app"]];
    NSString *stamp = WCRShareStamp(spec, templateBinary, targetBundleIdentifier);
    NSString *stampPath = [destination stringByAppendingPathComponent:@"Contents/Resources/stamp.txt"];
    NSString *currentStamp = [NSString stringWithContentsOfFile:stampPath encoding:NSUTF8StringEncoding error:nil];
    if ([currentStamp isEqualToString:stamp]) {
        if (!WCRShareElected(appexIdentifier)) {
            NSString *appex = [destination stringByAppendingPathComponent:@"Contents/PlugIns/WCRefineShare.appex"];
            int status = 0;
            WCRShareRun(kWCRSharePluginkit, @[@"-a", appex], &status);
            WCRShareRun(kWCRSharePluginkit, @[@"-e", @"use", @"-i", appexIdentifier], &status);
        }
        return YES;
    }

    NSString *staging = [entries stringByAppendingPathComponent:
        [NSString stringWithFormat:@".%@.building", spec->identifier]];
    [[NSFileManager defaultManager] removeItemAtPath:staging error:nil];
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *contents = [staging stringByAppendingPathComponent:@"Contents"];
    NSString *appex = [contents stringByAppendingPathComponent:@"PlugIns/WCRefineShare.appex"];
    for (NSString *relative in @[@"MacOS", @"Resources", @"PlugIns"]) {
        [files createDirectoryAtPath:[contents stringByAppendingPathComponent:relative]
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
    }
    NSError *copyError = nil;
    if (![files copyItemAtPath:stub toPath:[contents stringByAppendingPathComponent:@"MacOS/WCRefineShareHost"] error:&copyError] ||
        ![files copyItemAtPath:templateAppex toPath:appex error:&copyError]) {
        [files removeItemAtPath:staging error:nil];
        if (errorMessage) *errorMessage = @"没能生成共享入口。";
        return NO;
    }
    NSError *iconError = nil;
    if (!WCRShareWriteIcon(targetApp,
            [NSURL fileURLWithPath:[contents stringByAppendingPathComponent:@"Resources/AppIcon.icns"]],
            &iconError)) {
        WCRShareLog(iconError.localizedDescription ?: @"图标没能写入");
    }
    NSDictionary *hostInfo = WCRShareHostInfo(spec, hostIdentifier);
    NSDictionary *appexInfo = WCRShareExtensionInfo(spec, appexIdentifier, targetBundleIdentifier);
    if (![hostInfo writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES] ||
        ![appexInfo writeToFile:[appex stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES] ||
        ![stamp writeToFile:[contents stringByAppendingPathComponent:@"Resources/stamp.txt"]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil]) {
        [files removeItemAtPath:staging error:nil];
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"没能写好「%@」的入口。", spec->title];
        return NO;
    }
    int status = 0;
    NSString *signedOutput = WCRShareRun(@"/usr/bin/codesign",
        @[@"--force", @"--sign", @"-", @"--timestamp=none", @"--entitlements", entitlements, appex], &status);
    if (status != 0) {
        [files removeItemAtPath:staging error:nil];
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"没能签名「%@」的入口。%@", spec->title, signedOutput];
        return NO;
    }
    signedOutput = WCRShareRun(@"/usr/bin/codesign",
        @[@"--force", @"--sign", @"-", @"--timestamp=none", staging], &status);
    if (status != 0) {
        [files removeItemAtPath:staging error:nil];
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"没能签名「%@」。%@", spec->title, signedOutput];
        return NO;
    }
    WCRShareRun(@"/usr/bin/xattr", @[@"-dr", @"com.apple.quarantine", staging], &status);
    if ([files fileExistsAtPath:destination]) WCRShareRemoveEntry(destination);
    if (![files moveItemAtPath:staging toPath:destination error:&copyError]) {
        [files removeItemAtPath:staging error:nil];
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"没能放好「%@」的入口。", spec->title];
        return NO;
    }
    WCRShareRun(kWCRShareLsregister, @[@"-f", destination], &status);
    NSString *installedAppex = [destination stringByAppendingPathComponent:@"Contents/PlugIns/WCRefineShare.appex"];
    NSString *pluginOutput = WCRShareRun(kWCRSharePluginkit, @[@"-a", installedAppex], &status);
    if (status != 0) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"系统没有收下「%@」。%@", spec->title, pluginOutput];
        return NO;
    }
    WCRShareRun(kWCRSharePluginkit, @[@"-e", @"use", @"-i", appexIdentifier], &status);
    WCRShareLog([NSString stringWithFormat:@"installed %@ (%@ -> %@)", spec->title, targetBundleIdentifier, appexIdentifier]);
    return YES;
}

static void WCRShareSynchronizeList(NSString *csv) {
    NSMutableSet<NSString *> *enabled = [NSMutableSet set];
    for (NSString *raw in [csv componentsSeparatedByString:@","]) {
        NSString *identifier = [raw stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (identifier.length == 0 || !WCROtherAppSpecForIdentifier(identifier)) continue;
        [enabled addObject:identifier];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:WCRShareRelayDirectory()
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions : @0755}
                                                    error:nil];
    NSUInteger count = 0;
    const WCROtherAppSpec *specs = WCROtherAppSpecs(&count);
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    for (NSUInteger index = 0; index < count; ++index) {
        const WCROtherAppSpec *spec = &specs[index];
        BOOL on = [enabled containsObject:spec->identifier];
        BOOL installed = WCROtherAppApplicationURL(spec) != nil;
        NSString *entry = [WCRShareEntriesDirectory() stringByAppendingPathComponent:
            [spec->identifier stringByAppendingPathExtension:@"app"]];
        if (!on || !installed) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:entry]) WCRShareRemoveEntry(entry);
            if (on && !installed) {
                [problems addObject:[NSString stringWithFormat:@"没有找到 %@。", spec->applicationName]];
            }
            continue;
        }
        NSString *problem = nil;
        if (!WCRShareInstall(spec, &problem) && problem.length) [problems addObject:problem];
    }
    // 登记失败时留下上一份还能用的入口。这里只清掉已经不在名单里的旧入口。
    NSArray<NSString *> *existing = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:WCRShareEntriesDirectory() error:nil];
    for (NSString *name in existing) {
        if (![name.pathExtension isEqualToString:@"app"]) continue;
        NSString *identifier = name.stringByDeletingPathExtension;
        if (WCROtherAppSpecForIdentifier(identifier)) continue;
        WCRShareRemoveEntry([WCRShareEntriesDirectory() stringByAppendingPathComponent:name]);
    }
    WCRShareWriteStatus(problems.count ? [problems componentsJoinedByString:@" "] : nil);
    if (problems.count) WCRShareNotify(problems.firstObject);
}

static BOOL WCRShareFileIsZip(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attributes fileSize] < 30) return NO;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return NO;
    NSData *magic = [handle readDataOfLength:4];
    [handle closeFile];
    if (magic.length < 4) return NO;
    const unsigned char *bytes = (const unsigned char *)magic.bytes;
    return bytes[0] == 'P' && bytes[1] == 'K' && bytes[2] == 3 && bytes[3] == 4;
}

static void WCRShareHandOff(NSString *bundleIdentifier, NSString *displayName, NSArray<NSURL *> *files) {
    if (files.count == 0) return;
    NSURL *applicationURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:files];
    if (!applicationURL) {
        WCRShareNotify([NSString stringWithFormat:@"没有找到 %@。文件已经放进剪贴板，可以自己粘贴。", displayName ?: @"目标应用"]);
        return;
    }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    configuration.addsToRecentItems = NO;
    __block BOOL opened = NO;
    [[NSWorkspace sharedWorkspace] openURLs:files
                       withApplicationAtURL:applicationURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication *app, NSError *error) {
        (void)app;
        if (error) WCRShareLog(error.localizedDescription);
        opened = YES;
    }];
    for (int attempt = 0; attempt < 40 && !opened; ++attempt) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    for (int attempt = 0; attempt < 40; ++attempt) {
        if ([[NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier isEqualToString:bundleIdentifier]) break;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        WCRShareNotify([NSString stringWithFormat:@"文件已交给 %@，也放进了剪贴板。若输入框里没有，请按 ⌘V。自动粘贴需要在系统设置里允许「WCRefine 其他应用扩展」使用辅助功能。", displayName ?: @"目标应用"]);
        WCRShareLog([NSString stringWithFormat:@"handoff %@ without paste", displayName ?: bundleIdentifier]);
        return;
    }
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef down = CGEventCreateKeyboardEvent(source, (CGKeyCode)9, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, (CGKeyCode)9, false);
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    if (source) CFRelease(source);
    WCRShareLog([NSString stringWithFormat:@"handoff %@ files=%lu", displayName ?: bundleIdentifier, (unsigned long)files.count]);
}

static void WCRShareExpireOldBatches(void) {
    NSString *relay = WCRShareRelayDirectory();
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-(24 * 60 * 60)];
    NSArray<NSString *> *batches = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:relay error:nil];
    for (NSString *name in batches) {
        if ([name hasPrefix:@"."]) continue;
        NSString *batch = [relay stringByAppendingPathComponent:name];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:batch error:nil];
        NSDate *modified = attributes[NSFileModificationDate];
        if (modified && [modified compare:cutoff] == NSOrderedAscending) {
            [[NSFileManager defaultManager] removeItemAtPath:batch error:nil];
        }
    }
}

static void WCRShareMarkDelivered(NSString *batch) {
    [@"1" writeToFile:[batch stringByAppendingPathComponent:@".delivered"]
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];
}

/// 交给对方之后仍把压缩包留在 Relay 里一天。对方如果只记下路径，过后还能读到。
static NSUInteger WCRShareDrainRelay(void) {
    WCRShareExpireOldBatches();
    NSString *relay = WCRShareRelayDirectory();
    NSArray<NSString *> *batches = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:relay error:nil];
    NSUInteger finished = 0;
    for (NSString *name in batches) {
        if ([name hasPrefix:@"."]) continue;
        NSString *batch = [relay stringByAppendingPathComponent:name];
        BOOL directory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:batch isDirectory:&directory] || !directory) continue;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[batch stringByAppendingPathComponent:@".delivered"]]) continue;
        NSString *intentPath = [batch stringByAppendingPathComponent:@"intent.json"];
        NSData *data = [NSData dataWithContentsOfFile:intentPath];
        if (!data) continue;
        NSDictionary *intent = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![intent isKindOfClass:[NSDictionary class]]) continue;
        NSString *bundleIdentifier = [intent[@"bundleIdentifier"] isKindOfClass:[NSString class]] ? intent[@"bundleIdentifier"] : nil;
        NSString *displayName = [intent[@"displayName"] isKindOfClass:[NSString class]] ? intent[@"displayName"] : bundleIdentifier;
        NSArray *fileNames = [intent[@"files"] isKindOfClass:[NSArray class]] ? intent[@"files"] : @[];
        NSMutableArray<NSURL *> *files = [NSMutableArray array];
        BOOL emptyZip = NO;
        for (id fileName in fileNames) {
            if (![fileName isKindOfClass:[NSString class]]) continue;
            NSString *base = [(NSString *)fileName lastPathComponent];
            if (base.length == 0 || [base isEqualToString:@"."] || [base isEqualToString:@".."] ||
                [base isEqualToString:@"intent.json"] || [base isEqualToString:@".delivered"]) continue;
            NSString *path = [[batch stringByAppendingPathComponent:base] stringByStandardizingPath];
            if (![path hasPrefix:[[batch stringByStandardizingPath] stringByAppendingString:@"/"]]) continue;
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
            if (!WCRShareFileIsZip(path)) {
                emptyZip = YES;
                WCRShareLog([NSString stringWithFormat:@"skip empty zip %@", path]);
                continue;
            }
            [files addObject:[NSURL fileURLWithPath:path]];
        }
        if (bundleIdentifier.length == 0 || files.count == 0) {
            if (emptyZip) {
                WCRShareNotify(@"聊天记录是空的，没有交给应用。");
                WCRShareMarkDelivered(batch);
                finished += 1;
            }
            continue;
        }
        WCRShareHandOff(bundleIdentifier, displayName, files);
        WCRShareMarkDelivered(batch);
        finished += 1;
    }
    return finished;
}

@interface WCRShareHostApp : NSObject <NSApplicationDelegate>
@property(nonatomic, assign) BOOL scheduled;
@end

@implementation WCRShareHostApp

- (void)noteURL:(NSURL *)url {
    if ([url.host isEqualToString:@"deliver"]) {
        gWantsDeliver = YES;
        return;
    }
    if (![url.host isEqualToString:@"sync"]) return;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![item.name isEqualToString:@"on"]) continue;
        gEnabledList = item.value.stringByRemovingPercentEncoding ?: @"";
        gHasEnabledList = YES;
    }
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    (void)application;
    for (NSURL *url in urls) [self noteURL:url];
    [self scheduleWork];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self scheduleWork];
}

- (void)scheduleWork {
    if (self.scheduled) return;
    self.scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @autoreleasepool {
            if (gHasEnabledList) WCRShareSynchronizeList(gEnabledList ?: @"");
            if (gWantsDeliver) {
                for (int attempt = 0; attempt < 20; ++attempt) {
                    if (WCRShareDrainRelay() > 0) break;
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                }
            } else {
                WCRShareDrainRelay();
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    });
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        WCRShareHostApp *delegate = [[WCRShareHostApp alloc] init];
        for (NSString *argument in NSProcessInfo.processInfo.arguments) {
            if ([argument hasPrefix:@"--on="]) {
                gEnabledList = [argument substringFromIndex:@"--on=".length];
                gHasEnabledList = YES;
            }
        }
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
