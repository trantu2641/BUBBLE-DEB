#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static IMP BMOriginalSetInterfaceOrientation = NULL;
static IMP BMOriginalSetDeviceOrientation = NULL;
static IMP BMOriginalSetLandscapeLocked = NULL;

static UIInterfaceOrientation BMCurrentInterfaceOrientation(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (application == nil) {
        return UIInterfaceOrientationPortrait;
    }

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached) {
            continue;
        }

        UIInterfaceOrientation orientation =
            windowScene.interfaceOrientation;

        if (orientation != UIInterfaceOrientationUnknown) {
            return orientation;
        }
    }

    return UIInterfaceOrientationPortrait;
}

static BOOL BMIsLandscape(
    UIInterfaceOrientation orientation
)
{
    return orientation ==
               UIInterfaceOrientationLandscapeLeft ||
           orientation ==
               UIInterfaceOrientationLandscapeRight;
}

static void BMRelayoutWindow(
    UIWindow *window
)
{
    if (window == nil) {
        return;
    }

    if (window.windowScene == nil) {
        return;
    }

    CGRect bounds = window.bounds;

    if (bounds.size.width <= 0.0 ||
        bounds.size.height <= 0.0) {
        return;
    }

    @try {

        [window setNeedsLayout];
        [window layoutIfNeeded];

        UIViewController *root =
            window.rootViewController;

        if (root != nil) {

            UIView *view = root.view;

            if (view != nil) {
                [view setNeedsLayout];
                [view layoutIfNeeded];
            }
        }

    }
    @catch (__unused NSException *exception) {
    }
}

static void BMRelayoutAllWindows(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (application == nil) {
        return;
    }

    @try {

        NSSet<UIScene *> *scenes =
            application.connectedScenes;

        for (UIScene *scene in scenes) {

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            if (windowScene.activationState ==
                UISceneActivationStateUnattached) {
                continue;
            }

            NSArray<UIWindow *> *windows =
                windowScene.windows;

            for (UIWindow *window in windows) {
                BMRelayoutWindow(window);
            }
        }

    }
    @catch (__unused NSException *exception) {
    }
}

static void BMScheduleRelayout(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            @autoreleasepool {

                BMRelayoutAllWindows();

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        @autoreleasepool {
                            BMRelayoutAllWindows();
                        }
                    }
                );
            }
        }
    );
}

static void BMSetInterfaceOrientation(
    id self,
    SEL selector,
    UIInterfaceOrientation orientation
)
{
    IMP original =
        BMOriginalSetInterfaceOrientation;

    if (original == NULL) {
        return;
    }

    UIInterfaceOrientation current =
        BMCurrentInterfaceOrientation();

    if (BMIsLandscape(current)) {

        ((void (*)(id, SEL, UIInterfaceOrientation))
            original)(
                self,
                selector,
                current
            );

        BMScheduleRelayout();

        return;
    }

    ((void (*)(id, SEL, UIInterfaceOrientation))
        original)(
            self,
            selector,
            orientation
        );
}

static void BMSetDeviceOrientation(
    id self,
    SEL selector,
    UIDeviceOrientation orientation
)
{
    IMP original =
        BMOriginalSetDeviceOrientation;

    if (original == NULL) {
        return;
    }

    UIInterfaceOrientation current =
        BMCurrentInterfaceOrientation();

    if (BMIsLandscape(current)) {

        UIDeviceOrientation deviceOrientation;

        if (current ==
            UIInterfaceOrientationLandscapeLeft) {

            deviceOrientation =
                UIDeviceOrientationLandscapeRight;

        } else {

            deviceOrientation =
                UIDeviceOrientationLandscapeLeft;
        }

        ((void (*)(id, SEL, UIDeviceOrientation))
            original)(
                self,
                selector,
                deviceOrientation
            );

        BMScheduleRelayout();

        return;
    }

    ((void (*)(id, SEL, UIDeviceOrientation))
        original)(
            self,
            selector,
            orientation
        );
}

static UIInterfaceOrientationMask
BMSupportedInterfaceOrientations(
    __unused id self,
    __unused SEL selector
)
{
    return UIInterfaceOrientationMaskAll;
}

static BOOL
BMShouldAutorotate(
    __unused id self,
    __unused SEL selector
)
{
    return YES;
}

static UIInterfaceOrientation
BMPreferredInterfaceOrientation(
    __unused id self,
    __unused SEL selector
)
{
    UIInterfaceOrientation current =
        BMCurrentInterfaceOrientation();

    if (BMIsLandscape(current)) {
        return current;
    }

    return UIInterfaceOrientationPortrait;
}

static void BMSetLandscapeLocked(
    id self,
    SEL selector,
    __unused BOOL locked
)
{
    IMP original =
        BMOriginalSetLandscapeLocked;

    if (original == NULL) {
        return;
    }

    ((void (*)(id, SEL, BOOL))
        original)(
            self,
            selector,
            NO
        );

    BMScheduleRelayout();
}

static void BMSwizzle(
    Class cls,
    SEL selector,
    IMP replacement,
    IMP *originalIMP
)
{
    if (cls == Nil) {
        return;
    }

    if (selector == NULL) {
        return;
    }

    Method method =
        class_getInstanceMethod(
            cls,
            selector
        );

    if (method == NULL) {
        return;
    }

    IMP original =
        method_getImplementation(method);

    if (originalIMP != NULL) {
        *originalIMP = original;
    }

    method_setImplementation(
        method,
        replacement
    );
}

static void BMInstallBubbleWindowHooks(void)
{
    Class cls =
        objc_getClass("BMBubbleWindow");

    if (cls == Nil) {
        return;
    }

    BMSwizzle(
        cls,
        @selector(setInterfaceOrientation:),
        (IMP)BMSetInterfaceOrientation,
        &BMOriginalSetInterfaceOrientation
    );

    BMSwizzle(
        cls,
        @selector(setDeviceOrientation:),
        (IMP)BMSetDeviceOrientation,
        &BMOriginalSetDeviceOrientation
    );
}

static void BMInstallRootControllerHooks(void)
{
    Class cls =
        objc_getClass("BMBubbleRootViewController");

    if (cls == Nil) {
        return;
    }

    BMSwizzle(
        cls,
        @selector(supportedInterfaceOrientations),
        (IMP)BMSupportedInterfaceOrientations,
        NULL
    );

    BMSwizzle(
        cls,
        @selector(shouldAutorotate),
        (IMP)BMShouldAutorotate,
        NULL
    );

    BMSwizzle(
        cls,
        @selector(preferredInterfaceOrientationForPresentation),
        (IMP)BMPreferredInterfaceOrientation,
        NULL
    );
}

static void BMInstallLandscapeLockHook(void)
{
    Class cls =
        objc_getClass("BMBubbleManager");

    if (cls == Nil) {
        return;
    }

    BMSwizzle(
        cls,
        @selector(setLandscapeLocked:),
        (IMP)BMSetLandscapeLocked,
        &BMOriginalSetLandscapeLocked
    );
}

static void BMLockWindowToPortraitNoop(
    __unused id self,
    __unused SEL selector
)
{
}

static void BMInstallPortraitLockHook(void)
{
    const char *classes[] = {
        "BMBubbleManager",
        "BMBubbleWindow",
        "BMBubbleRootViewController",
        "BMBubbleLayoutContainer",
        "BMLiveSceneContainer",
        NULL
    };

    for (NSInteger i = 0;
         classes[i] != NULL;
         i++) {

        Class cls =
            objc_getClass(classes[i]);

        if (cls == Nil) {
            continue;
        }

        SEL selector =
            @selector(bm_lockWindowToPortrait);

        Method method =
            class_getInstanceMethod(
                cls,
                selector
            );

        if (method == NULL) {
            continue;
        }

        method_setImplementation(
            method,
            (IMP)BMLockWindowToPortraitNoop
        );

        break;
    }
}

static void BMOrientationChanged(
    __unused NSNotification *notification
)
{
    BMScheduleRelayout();
}

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void)
{
    @autoreleasepool {

        NSString *bundleIdentifier =
            NSBundle.mainBundle.bundleIdentifier;

        if (![bundleIdentifier
              isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        BMInstallBubbleWindowHooks();

        BMInstallRootControllerHooks();

        BMInstallLandscapeLockHook();

        BMInstallPortraitLockHook();

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
            ^(__unused NSNotification *note) {

            BMOrientationChanged(note);
        }];

        [center addObserverForName:
                    UISceneDidActivateNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:
            ^(__unused NSNotification *note) {

            BMOrientationChanged(note);
        }];

        [center addObserverForName:
                    UIWindowDidBecomeVisibleNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:
            ^(__unused NSNotification *note) {

            BMOrientationChanged(note);
        }];
    }
}
