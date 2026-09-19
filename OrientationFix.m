#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>

static BOOL BMOrientationFixInstalled = NO;

static BOOL (*BMOriginalBundleNeedsLandscape)(id bundleID) = NULL;

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

static NSString *BMBundleIdentifierFromObject(id bundleID)
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

        if ([identifier isKindOfClass:[NSString class]]) {
            return identifier;
        }
    }

    return nil;
}

static NSDictionary *BMApplicationInfoForBundleIdentifier(
    NSString *bundleIdentifier
)
{
    if (bundleIdentifier == nil ||
        bundleIdentifier.length == 0) {

        return nil;
    }

    Class proxyClass =
        objc_getClass("LSApplicationProxy");

    if (proxyClass != Nil) {

        SEL proxySelector =
            NSSelectorFromString(
                @"applicationProxyForIdentifier:"
            );

        if ([proxyClass
             respondsToSelector:proxySelector]) {

            id proxy =
                ((id (*)(id, SEL, id))
                    objc_msgSend)(
                        proxyClass,
                        proxySelector,
                        bundleIdentifier
                    );

            if (proxy != nil) {

                NSURL *bundleURL = nil;

                SEL bundleURLSelector =
                    NSSelectorFromString(
                        @"bundleURL"
                    );

                if ([proxy
                     respondsToSelector:bundleURLSelector]) {

                    bundleURL =
                        ((NSURL *(*)(id, SEL))
                            objc_msgSend)(
                                proxy,
                                bundleURLSelector
                            );
                }

                if (bundleURL != nil) {

                    NSURL *infoURL =
                        [bundleURL
                         URLByAppendingPathComponent:
                         @"Info.plist"];

                    NSDictionary *info =
                        [NSDictionary
                         dictionaryWithContentsOfURL:
                         infoURL];

                    if ([info isKindOfClass:
                         [NSDictionary class]]) {

                        return info;
                    }
                }
            }
        }
    }

    return nil;
}

static BOOL BMApplicationSupportsLandscape(
    NSString *bundleIdentifier
)
{
    NSDictionary *info =
        BMApplicationInfoForBundleIdentifier(
            bundleIdentifier
        );

    if (info == nil) {
        return NO;
    }

    NSArray *orientations =
        info[@"UISupportedInterfaceOrientations"];

    if (![orientations isKindOfClass:
          [NSArray class]]) {

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
    BOOL originalResult =
        BMOriginalSupportsLandscape(
            bundleID
        );

    NSString *identifier =
        BMBundleIdentifierFromObject(
            bundleID
        );

    if (identifier == nil) {

        return originalResult;
    }

    /*
     * Nếu app không khai báo Landscape,
     * tuyệt đối không ép nó sang ngang.
     */
    BOOL applicationSupportsLandscape =
        BMApplicationSupportsLandscape(
            identifier
        );

    if (!applicationSupportsLandscape) {

        return originalResult;
    }

    /*
     * App có hỗ trợ Landscape.
     *
     * Khi thiết bị đang ngang, cho phép
     * BubbleMe tạo Live Scene ở Landscape.
     */
    if (BMDeviceIsLandscape()) {

        return YES;
    }

    /*
     * Khi thiết bị không ngang, giữ nguyên
     * logic gốc của BubbleMe.
     */
    return originalResult;
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

static void BMRefreshBubbleOrientation(void)
{
    Class managerClass =
        objc_getClass("BMBubbleManager");

    if (managerClass == Nil) {
        return;
    }

    id manager = nil;

    SEL sharedSelector =
        NSSelectorFromString(
            @"sharedManager"
        );

    if ([managerClass
         respondsToSelector:sharedSelector]) {

        manager =
            ((id (*)(id, SEL))
                objc_msgSend)(
                    managerClass,
                    sharedSelector
                );
    }

    if (manager == nil) {

        SEL sharedInstanceSelector =
            NSSelectorFromString(
                @"sharedInstance"
            );

        if ([managerClass
             respondsToSelector:sharedInstanceSelector]) {

            manager =
                ((id (*)(id, SEL))
                    objc_msgSend)(
                        managerClass,
                        sharedInstanceSelector
                    );
        }
    }

    if (manager == nil) {
        return;
    }

    SEL applySelector =
        NSSelectorFromString(
            @"bm_applyChromeForCurrentOrientation"
        );

    if ([manager respondsToSelector:applySelector]) {

        ((void (*)(id, SEL))
            objc_msgSend)(
                manager,
                applySelector
            );
    }

    SEL refreshSelector =
        NSSelectorFromString(
            @"bm_refreshLiveContentHostView"
        );

    if ([manager respondsToSelector:refreshSelector]) {

        ((void (*)(id, SEL))
            objc_msgSend)(
                manager,
                refreshSelector
            );
    }
}

static void BMOrientationChanged(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            @autoreleasepool {

                BMInstallFunctionHook();

                BMRefreshBubbleOrientation();

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.15 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        BMInstallFunctionHook();
                        BMRefreshBubbleOrientation();
                    }
                );

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.40 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        BMInstallFunctionHook();
                        BMRefreshBubbleOrientation();
                    }
                );
            }
        }
    );
}

static void BMInstallNotifications(void)
{
    NSNotificationCenter *center =
        NSNotificationCenter.defaultCenter;

    if (center == nil) {
        return;
    }

    [center addObserverForName:
                UIDeviceOrientationDidChangeNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMOrientationChanged();
    }];

    [center addObserverForName:
                UISceneDidActivateNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMOrientationChanged();
    }];

    [center addObserverForName:
                UISceneWillDeactivateNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMOrientationChanged();
    }];

    [center addObserverForName:
                UIApplicationDidBecomeActiveNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMOrientationChanged();
    }];
}

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void)
{
    @autoreleasepool {

        if (!BMIsSpringBoard()) {
            return;
        }

        BMInstallFunctionHook();

        BMInstallNotifications();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                BMInstallFunctionHook();
                BMRefreshBubbleOrientation();
            }
        );

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(
                    1.0 *
                    NSEC_PER_SEC
                )
            ),
            dispatch_get_main_queue(),
            ^{
                BMInstallFunctionHook();
            }
        );
    }
}
