#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>

static BOOL BMOrientationFixInstalled = NO;

static BOOL (*BMOriginalBundleNeedsLandscape)(id bundleID) = NULL;

static NSMutableDictionary *BMLandscapeCache = nil;

static BOOL BMLandscapeCacheInitialized = NO;

static BOOL BMIsSpringBoard(void)
{
    NSString *identifier =
        NSBundle.mainBundle.bundleIdentifier;

    if (identifier == nil) {
        return NO;
    }

    return [identifier isEqualToString:
            @"com.apple.springboard"];
}

static void BMEnsureCache(void)
{
    if (BMLandscapeCacheInitialized) {
        return;
    }

    BMLandscapeCacheInitialized = YES;

    BMLandscapeCache =
        [[NSMutableDictionary alloc] init];
}

static BOOL BMDeviceIsLandscape(void)
{
    UIDeviceOrientation orientation =
        UIDevice.currentDevice.orientation;

    if (orientation == UIDeviceOrientationLandscapeLeft ||
        orientation == UIDeviceOrientationLandscapeRight) {

        return YES;
    }

    UIApplication *application =
        UIApplication.sharedApplication;

    if (application == nil) {
        return NO;
    }

    NSSet *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        UIInterfaceOrientation interfaceOrientation =
            windowScene.interfaceOrientation;

        if (interfaceOrientation ==
                UIInterfaceOrientationLandscapeLeft ||
            interfaceOrientation ==
                UIInterfaceOrientationLandscapeRight) {

            return YES;
        }
    }

    return NO;
}

static NSString *BMBundleIdentifierFromObject(
    id bundleID
)
{
    if (bundleID == nil) {
        return nil;
    }

    if ([bundleID isKindOfClass:[NSString class]]) {
        return (NSString *)bundleID;
    }

    if ([bundleID respondsToSelector:
         @selector(bundleIdentifier)]) {

        NSString *identifier =
            ((NSString *(*)(id, SEL))
                objc_msgSend)(
                    bundleID,
                    @selector(bundleIdentifier)
                );

        if ([identifier isKindOfClass:
             [NSString class]]) {

            return identifier;
        }
    }

    return nil;
}

static BOOL BMReadLandscapeSupport(
    NSString *bundleIdentifier
)
{
    if (bundleIdentifier == nil ||
        bundleIdentifier.length == 0) {

        return NO;
    }

    /*
     * LaunchServices lookup chỉ thực hiện một lần
     * cho mỗi bundle ID.
     */
    Class proxyClass =
        objc_getClass("LSApplicationProxy");

    if (proxyClass == Nil) {
        return NO;
    }

    SEL proxySelector =
        NSSelectorFromString(
            @"applicationProxyForIdentifier:"
        );

    if (![proxyClass
          respondsToSelector:proxySelector]) {

        return NO;
    }

    id proxy =
        ((id (*)(id, SEL, id))
            objc_msgSend)(
                proxyClass,
                proxySelector,
                bundleIdentifier
            );

    if (proxy == nil) {
        return NO;
    }

    SEL bundleURLSelector =
        NSSelectorFromString(
            @"bundleURL"
        );

    if (![proxy
         respondsToSelector:bundleURLSelector]) {

        return NO;
    }

    NSURL *bundleURL =
        ((NSURL *(*)(id, SEL))
            objc_msgSend)(
                proxy,
                bundleURLSelector
            );

    if (bundleURL == nil) {
        return NO;
    }

    NSURL *infoURL =
        [bundleURL
         URLByAppendingPathComponent:
         @"Info.plist"];

    NSDictionary *info =
        [NSDictionary
         dictionaryWithContentsOfURL:
         infoURL];

    if (![info isKindOfClass:
          [NSDictionary class]]) {

        return NO;
    }

    NSArray *orientations =
        info[@"UISupportedInterfaceOrientations"];

    if (![orientations isKindOfClass:
          [NSArray class]]) {

        /*
         * Không có khai báo orientation.
         *
         * Không tự ý ép Landscape.
         */
        return NO;
    }

    for (NSString *orientation in orientations) {

        if (![orientation isKindOfClass:
              [NSString class]]) {

            continue;
        }

        if ([orientation isEqualToString:
             @"UIInterfaceOrientationLandscapeLeft"]) {

            return YES;
        }

        if ([orientation isEqualToString:
             @"UIInterfaceOrientationLandscapeRight"]) {

            return YES;
        }
    }

    return NO;
}

static BOOL BMApplicationSupportsLandscape(
    NSString *bundleIdentifier
)
{
    if (bundleIdentifier == nil ||
        bundleIdentifier.length == 0) {

        return NO;
    }

    BMEnsureCache();

    NSNumber *cached =
        BMLandscapeCache[bundleIdentifier];

    if (cached != nil) {

        return cached.boolValue;
    }

    BOOL supported =
        BMReadLandscapeSupport(
            bundleIdentifier
        );

    /*
     * Cache kết quả.
     *
     * Sau lần đầu tiên, hook không còn
     * phải truy vấn LaunchServices nữa.
     */
    BMLandscapeCache[bundleIdentifier] =
        @(supported);

    return supported;
}

static BOOL BMOriginalSupportsLandscape(
    id bundleID
)
{
    if (BMOriginalBundleNeedsLandscape == NULL) {
        return NO;
    }

    return BMOriginalBundleNeedsLandscape(
        bundleID
    );
}

static BOOL BMHookedBundleNeedsLandscape(
    id bundleID
)
{
    /*
     * Lấy bundle ID trước.
     */
    NSString *identifier =
        BMBundleIdentifierFromObject(
            bundleID
        );

    /*
     * Không xác định được app:
     * giữ nguyên BubbleMe.
     */
    if (identifier == nil) {

        return BMOriginalSupportsLandscape(
            bundleID
        );
    }

    /*
     * Kiểm tra cache.
     */
    BOOL supportsLandscape =
        BMApplicationSupportsLandscape(
            identifier
        );

    /*
     * App không hỗ trợ Landscape:
     *
     * TUYỆT ĐỐI không ép.
     */
    if (!supportsLandscape) {

        return BMOriginalSupportsLandscape(
            bundleID
        );
    }

    /*
     * App có hỗ trợ Landscape.
     *
     * Chỉ ép YES khi thiết bị thực sự ngang.
     */
    if (BMDeviceIsLandscape()) {

        return YES;
    }

    /*
     * Khi đang dọc, để BubbleMe xử lý
     * theo logic gốc.
     */
    return BMOriginalSupportsLandscape(
        bundleID
    );
}

static void BMInstallFunctionHook(void)
{
    if (BMOrientationFixInstalled) {
        return;
    }

    void *symbol =
        MSFindSymbol(
            NULL,
            "_BMBundleNeedsLandscapeMiniPhone"
        );

    if (symbol == NULL) {

        void *handle =
            dlopen(
                NULL,
                RTLD_NOW
            );

        if (handle != NULL) {

            symbol =
                dlsym(
                    handle,
                    "_BMBundleNeedsLandscapeMiniPhone"
                );
        }
    }

    if (symbol == NULL) {
        return;
    }

    MSHookFunction(
        symbol,
        (void *)BMHookedBundleNeedsLandscape,
        (void **)&BMOriginalBundleNeedsLandscape
    );

    if (BMOriginalBundleNeedsLandscape != NULL) {

        BMOrientationFixInstalled = YES;
    }
}

static void BMInstallNotifications(void)
{
    NSNotificationCenter *center =
        NSNotificationCenter.defaultCenter;

    if (center == nil) {
        return;
    }

    /*
     * Chỉ dùng notification để BubbleMe
     * biết orientation đã thay đổi.
     *
     * Không refresh Live Scene liên tục.
     */
    [center addObserverForName:
                UIDeviceOrientationDidChangeNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMInstallFunctionHook();
    }];

    [center addObserverForName:
                UISceneDidActivateNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMInstallFunctionHook();
    }];
}

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void)
{
    @autoreleasepool {

        if (!BMIsSpringBoard()) {
            return;
        }

        /*
         * Khởi tạo cache trước.
         */
        BMEnsureCache();

        /*
         * Cài hook ngay lập tức.
         */
        BMInstallFunctionHook();

        /*
         * Chỉ cài notification nhẹ.
         */
        BMInstallNotifications();
    }
}
