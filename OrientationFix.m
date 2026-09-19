#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - Original IMP storage

static IMP BMOriginalLockWindowToPortrait = NULL;
static IMP BMOriginalSetLandscapeLocked = NULL;
static IMP BMOriginalSetInterfaceOrientation = NULL;
static IMP BMOriginalSetDeviceOrientation = NULL;
static IMP BMOriginalSupportedInterfaceOrientations = NULL;
static IMP BMOriginalShouldAutorotate = NULL;
static IMP BMOriginalPreferredInterfaceOrientation = NULL;

#pragma mark - Current orientation

static UIInterfaceOrientation BMCurrentInterfaceOrientation(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (application == nil)
        return UIInterfaceOrientationPortrait;

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        UIInterfaceOrientation orientation =
            windowScene.interfaceOrientation;

        if (orientation != UIInterfaceOrientationUnknown)
            return orientation;
    }

    return UIInterfaceOrientationPortrait;
}

#pragma mark - Orientation test

static BOOL BMIsLandscapeOrientation(
    UIInterfaceOrientation orientation
)
{
    return orientation ==
               UIInterfaceOrientationLandscapeLeft ||
           orientation ==
               UIInterfaceOrientationLandscapeRight;
}

#pragma mark - Safe relayout

static void BMRelayoutWindow(UIWindow *window)
{
    if (window == nil)
        return;

    if (window.windowScene == nil)
        return;

    CGRect bounds = window.bounds;

    if (bounds.size.width <= 0.0 ||
        bounds.size.height <= 0.0)
        return;

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

    if (application == nil)
        return;

    @try {

        NSSet<UIScene *> *scenes =
            application.connectedScenes;

        for (UIScene *scene in scenes) {

            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            if (windowScene.activationState ==
                UISceneActivationStateUnattached)
                continue;

            for (UIWindow *window in windowScene.windows) {
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

#pragma mark - BMBubbleWindow
#
# This is the important part.
#
# BubbleMe contains BMBubbleWindow and exposes
# setInterfaceOrientation: / setDeviceOrientation:.
#
# We allow the actual device orientation instead
# of allowing BubbleMe to force Portrait.

static void BM_BubbleWindow_setInterfaceOrientation(
    id self,
    SEL selector,
    UIInterfaceOrientation orientation
)
{
    if (BMOriginalSetInterfaceOrientation == NULL)
        return;

    UIInterfaceOrientation current =
        BMCurrentInterfaceOrientation();

    /*
     * If UIKit is already in Landscape, do NOT allow
     * BubbleMe to replace it with Portrait.
     */

    if (BMIsLandscapeOrientation(current)) {

        ((void (*)(id, SEL, UIInterfaceOrientation))
            BMOriginalSetInterfaceOrientation)(
                self,
                selector,
                current
            );

        return;
    }

    /*
     * Otherwise preserve the orientation requested
     * by BubbleMe.
     */

    ((void (*)(id, SEL, UIInterfaceOrientation))
        BMOriginalSetInterfaceOrientation)(
            self,
            selector,
            orientation
        );
}

#pragma mark - BMBubbleWindow device orientation

static void BM_BubbleWindow_setDeviceOrientation(
    id self,
    SEL selector,
    UIDeviceOrientation orientation
)
{
    if (BMOriginalSetDeviceOrientation == NULL)
        return;

    UIInterfaceOrientation current =
        BMCurrentInterfaceOrientation();

    /*
     * When UIKit has already switched to Landscape,
     * pass a matching landscape orientation instead of
     * allowing BubbleMe to reset itself to Portrait.
     */

    if (BMIsLandscapeOrientation(current)) {

        UIDeviceOrientation deviceOrientation;

        if (current == UIInterfaceOrientationLandscapeLeft) {
            deviceOrientation =
                UIDeviceOrientationLandscapeRight;
        }
        else {
            deviceOrientation =
                UIDeviceOrientationLandscapeLeft;
        }

        ((void (*)(id, SEL, UIDeviceOrientation))
            BMOriginalSetDeviceOrientation)(
                self,
                selector,
                deviceOrientation
            );

        return;
    }

    ((void (*)(id, SEL, UIDeviceOrientation))
        BMOriginalSetDeviceOrientation)(
            self,
            selector,
            orientation
        );
}

#pragma mark - BMBubbleRootViewController
#
# Tell UIKit that BubbleMe's root controller is
# allowed to rotate.

static UIInterfaceOrientationMask
BM_BubbleRoot_supportedInterfaceOrientations(
    id self,
    SEL selector
)
{
    (void)self;
    (void)selector;

    /*
     * Allow all normal iPhone orientations.
     *
     * This prevents BubbleMe's root controller from
     * advertising Portrait-only support.
     */

    return UIInterfaceOrientationMaskAll;
}

static BOOL
BM_BubbleRoot_shouldAutorotate(
    id self,
    SEL selector
)
{
    (void)self;
    (void)selector;

    return YES;
}

static UIInterfaceOrientation
BM_BubbleRoot_preferredInterfaceOrientationForPresentation(
    id self,
    SEL selector
)
{
    (void)self;
    (void)selector;

    UIInterfaceOrientation current =
        BMCurrentInterfaceOrientation();

    /*
     * Do not advertise Portrait when the device is
     * already in Landscape.
     */

    if (BMIsLandscapeOrientation(current))
        return current;

    return UIInterfaceOrientationPortrait;
}

#pragma mark - BubbleMe landscape lock
#
# BubbleMe exposes:
#
#   landscapeLocked
#   setLandscapeLocked:
#
# We force the internal lock OFF.
#
# This is much more targeted than changing every
# UIWindow in SpringBoard.

static void BM_BubbleManager_setLandscapeLocked(
    id self,
    SEL selector,
    BOOL locked
)
{
    if (BMOriginalSetLandscapeLocked == NULL)
        return;

    /*
     * Never allow BubbleMe to enable its orientation lock.
     */

    ((void (*)(id, SEL, BOOL))
        BMOriginalSetLandscapeLocked)(
            self,
            selector,
            NO
        );

    BMScheduleRelayout();
}

#pragma mark - bm_lockWindowToPortrait
#
# BubbleMe has an explicit method with this name.
#
# Instead of patching the binary, we replace this
# method with a no-op.
#
# If the method does not exist on the installed version,
# nothing happens.

static void BM_Bubble_lockWindowToPortrait(
    id self,
    SEL selector
)
{
    (void)self;
    (void)selector;

    /*
     * INTENTIONALLY EMPTY.
     *
     * BubbleMe must not lock its window to Portrait.
     */
}

#pragma mark - Runtime swizzle

static BOOL BMSwizzleExistingMethod(
    Class cls,
    SEL selector,
    IMP replacement,
    IMP *originalIMP
)
{
    if (cls == Nil)
        return NO;

    if (selector == NULL)
        return NO;

    Method method =
        class_getInstanceMethod(
            cls,
            selector
        );

    if (method == NULL)
        return NO;

    IMP original =
        method_getImplementation(method);

    if (originalIMP != NULL)
        *originalIMP = original;

    method_setImplementation(
        method,
        replacement
    );

    return YES;
}

#pragma mark - Install BMBubbleWindow hooks

static void BMInstallBubbleWindowHooks(void)
{
    Class cls =
        objc_getClass("BMBubbleWindow");

    if (cls == Nil)
        return;

    BMSwizzleExistingMethod(
        cls,
        @selector(setInterfaceOrientation:),
        (IMP)BM_BubbleWindow_setInterfaceOrientation,
        &BMOriginalSetInterfaceOrientation
    );

    BMSwizzleExistingMethod(
        cls,
        @selector(setDeviceOrientation:),
        (IMP)BM_BubbleWindow_setDeviceOrientation,
        &BMOriginalSetDeviceOrientation
    );
}

#pragma mark - Install RootViewController hooks

static void BMInstallRootControllerHooks(void)
{
    Class cls =
        objc_getClass("BMBubbleRootViewController");

    if (cls == Nil)
        return;

    BMSwizzleExistingMethod(
        cls,
        @selector(supportedInterfaceOrientations),
        (IMP)BM_BubbleRoot_supportedInterfaceOrientations,
        &BMOriginalSupportedInterfaceOrientations
    );

    BMSwizzleExistingMethod(
        cls,
        @selector(shouldAutorotate),
        (IMP)BM_BubbleRoot_shouldAutorotate,
        &BMOriginalShouldAutorotate
    );

    BMSwizzleExistingMethod(
        cls,
        @selector(preferredInterfaceOrientationForPresentation),
        (IMP)BM_BubbleRoot_preferredInterfaceOrientationForPresentation,
        &BMOriginalPreferredInterfaceOrientation
    );
}

#pragma mark - Install landscape lock hook

static void BMInstallLandscapeLockHook(void)
{
    /*
     * Try BMBubbleManager first.
     */

    Class manager =
        objc_getClass("BMBubbleManager");

    if (manager != Nil) {

        BMSwizzleExistingMethod(
            manager,
            @selector(setLandscapeLocked:),
            (IMP)BM_BubbleManager_setLandscapeLocked,
            &BMOriginalSetLandscapeLocked
        );
    }
}

#pragma mark - Install portrait lock hook

static void BMInstallPortraitLockHook(void)
{
    /*
     * Search the known BubbleMe classes.
     *
     * The symbol exists in the binary, but its exact
     * owning class can vary between builds.
     */

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

        if (cls == Nil)
            continue;

        Method method =
            class_getInstanceMethod(
                cls,
                @selector(bm_lockWindowToPortrait)
            );

        if (method == NULL)
            continue;

        BMSwizzleExistingMethod(
            cls,
            @selector(bm_lockWindowToPortrait),
            (IMP)BM_Bubble_lockWindowToPortrait,
            &BMOriginalLockWindowToPortrait
        );

        /*
         * One implementation is enough.
         */

        break;
    }
}

#pragma mark - Orientation notifications

static void BMOrientationChanged(
    __unused NSNotification *notification
)
{
    BMScheduleRelayout();
}

#pragma mark - Constructor

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void)
{
    @autoreleasepool {

        /*
         * Safety:
         *
         * This dylib only operates inside SpringBoard.
         */

        NSString *bundleIdentifier =
            NSBundle.mainBundle.bundleIdentifier;

        if (![bundleIdentifier
              isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        /*
         * Install only targeted BubbleMe hooks.
         */

        BMInstallBubbleWindowHooks();

        BMInstallRootControllerHooks();

        BMInstallLandscapeLockHook();

        BMInstallPortraitLockHook();

        /*
         * Orientation notification.
         */

        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        if (center == nil)
            return;

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
