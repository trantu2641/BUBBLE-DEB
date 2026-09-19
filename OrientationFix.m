#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>

static BOOL BMOrientationFixInstalled = NO;

static BOOL (*BMOriginalBundleNeedsLandscape)(id bundleID) = NULL;

static NSInteger BMCurrentDeviceOrientation(void)
{
    UIDeviceOrientation orientation =
        UIDevice.currentDevice.orientation;

    if (orientation == UIDeviceOrientationLandscapeLeft) {
        return UIInterfaceOrientationLandscapeRight;
    }

    if (orientation == UIDeviceOrientationLandscapeRight) {
        return UIInterfaceOrientationLandscapeLeft;
    }

    if (orientation == UIDeviceOrientationPortrait) {
        return UIInterfaceOrientationPortrait;
    }

    if (orientation == UIDeviceOrientationPortraitUpsideDown) {
        return UIInterfaceOrientationPortraitUpsideDown;
    }

    UIApplication *application =
        UIApplication.sharedApplication;

    if (application != nil) {

        NSSet *scenes =
            application.connectedScenes;

        for (UIScene *scene in scenes) {

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            UIInterfaceOrientation orientation2 =
                windowScene.interfaceOrientation;

            if (orientation2 !=
                UIInterfaceOrientationUnknown) {

                return orientation2;
            }
        }
    }

    return UIInterfaceOrientationPortrait;
}

static BOOL BMIsLandscapeNow(void)
{
    NSInteger orientation =
        BMCurrentDeviceOrientation();

    return orientation ==
               UIInterfaceOrientationLandscapeLeft ||
           orientation ==
               UIInterfaceOrientationLandscapeRight;
}

static BOOL BMHookedBundleNeedsLandscape(
    id bundleID
)
{
    BOOL landscape =
        BMIsLandscapeNow();

    if (landscape) {

        return YES;
    }

    if (BMOriginalBundleNeedsLandscape != NULL) {

        return BMOriginalBundleNeedsLandscape(
            bundleID
        );
    }

    return NO;
}

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

        ((BOOL (*)(id, SEL))
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
