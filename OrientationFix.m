#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - Safety

static BOOL BMValidWindow(UIWindow *window)
{
    if (window == nil) {
        return NO;
    }

    UIWindowScene *scene = window.windowScene;

    if (scene == nil) {
        return NO;
    }

    CGRect bounds = window.bounds;

    if (bounds.size.width <= 0.0 ||
        bounds.size.height <= 0.0) {
        return NO;
    }

    return YES;
}

#pragma mark - Safe relayout

static void BMRelayoutWindow(UIWindow *window)
{
    if (!BMValidWindow(window)) {
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
        /*
         * Never allow an exception to escape into SpringBoard.
         */
    }
}

#pragma mark - Relayout all windows

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

            UISceneActivationState state =
                windowScene.activationState;

            if (state == UISceneActivationStateUnattached) {
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
        /*
         * Fail safe.
         */
    }
}

#pragma mark - Delayed relayout

static void BMScheduleRelayout(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        @autoreleasepool {

            BMRelayoutAllWindows();

            /*
             * BubbleMe may update its hierarchy
             * one run-loop after UIKit.
             */

            dispatch_async(dispatch_get_main_queue(), ^{

                @autoreleasepool {
                    BMRelayoutAllWindows();
                }

            });
        }

    });
}

#pragma mark - UIWindow swizzling

static void BM_original_setFrame(
    UIWindow *self,
    SEL _cmd,
    CGRect frame
)
{
    /*
     * This function is replaced at runtime.
     * The original implementation is installed
     * as BM_original_setFrame.
     */
}

static void BM_swizzled_setFrame(
    UIWindow *self,
    SEL _cmd,
    CGRect frame
)
{
    /*
     * The original implementation is invoked
     * through the IMP stored below.
     */

    static void (*original)(id, SEL, CGRect) = NULL;

    if (original != NULL) {
        original(self, _cmd, frame);
    }

    if (self.windowScene != nil) {
        BMScheduleRelayout();
    }
}

#pragma mark - UIWindow bounds swizzling

static void BM_swizzled_setBounds(
    UIWindow *self,
    SEL _cmd,
    CGRect bounds
)
{
    static void (*original)(id, SEL, CGRect) = NULL;

    if (original != NULL) {
        original(self, _cmd, bounds);
    }

    if (self.windowScene != nil) {
        BMScheduleRelayout();
    }
}

#pragma mark - Runtime swizzle helper

static BOOL BMSwizzleMethod(
    Class cls,
    SEL originalSelector,
    SEL replacementSelector,
    IMP *originalIMP
)
{
    if (cls == Nil ||
        originalSelector == NULL ||
        replacementSelector == NULL) {
        return NO;
    }

    Method originalMethod =
        class_getInstanceMethod(
            cls,
            originalSelector
        );

    Method replacementMethod =
        class_getInstanceMethod(
            cls,
            replacementSelector
        );

    if (originalMethod == NULL ||
        replacementMethod == NULL) {
        return NO;
    }

    IMP original =
        method_getImplementation(originalMethod);

    if (originalIMP != NULL) {
        *originalIMP = original;
    }

    method_exchangeImplementations(
        originalMethod,
        replacementMethod
    );

    return YES;
}

#pragma mark - Correct swizzled implementations

static IMP BMOriginalSetFrame = NULL;
static IMP BMOriginalSetBounds = NULL;

static void BM_SetFrame(
    UIWindow *self,
    SEL _cmd,
    CGRect frame
)
{
    if (BMOriginalSetFrame != NULL) {

        ((void (*)(id, SEL, CGRect))
            BMOriginalSetFrame)(
                self,
                _cmd,
                frame
            );
    }

    if (self.windowScene != nil) {
        BMScheduleRelayout();
    }
}

static void BM_SetBounds(
    UIWindow *self,
    SEL _cmd,
    CGRect bounds
)
{
    if (BMOriginalSetBounds != NULL) {

        ((void (*)(id, SEL, CGRect))
            BMOriginalSetBounds)(
                self,
                _cmd,
                bounds
            );
    }

    if (self.windowScene != nil) {
        BMScheduleRelayout();
    }
}

#pragma mark - Install UIWindow hooks

static void BMInstallWindowHooks(void)
{
    Class windowClass = objc_getClass("UIWindow");

    if (windowClass == Nil) {
        return;
    }

    Method frameMethod =
        class_getInstanceMethod(
            windowClass,
            @selector(setFrame:)
        );

    Method boundsMethod =
        class_getInstanceMethod(
            windowClass,
            @selector(setBounds:)
        );

    if (frameMethod != NULL) {

        SEL selector =
            @selector(bm_orientationFix_setFrame:);

        class_addMethod(
            windowClass,
            selector,
            (IMP)BM_SetFrame,
            method_getTypeEncoding(frameMethod)
        );

        BMSwizzleMethod(
            windowClass,
            @selector(setFrame:),
            selector,
            &BMOriginalSetFrame
        );
    }

    if (boundsMethod != NULL) {

        SEL selector =
            @selector(bm_orientationFix_setBounds:);

        class_addMethod(
            windowClass,
            selector,
            (IMP)BM_SetBounds,
            method_getTypeEncoding(boundsMethod)
        );

        BMSwizzleMethod(
            windowClass,
            @selector(setBounds:),
            selector,
            &BMOriginalSetBounds
        );
    }
}

#pragma mark - Notifications

static void BMOrientationNotification(
    NSNotification *notification
)
{
    (void)notification;

    BMScheduleRelayout();
}

#pragma mark - Constructor

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void)
{
    @autoreleasepool {

        /*
         * Safety:
         * only run inside SpringBoard.
         */

        NSString *bundleIdentifier =
            NSBundle.mainBundle.bundleIdentifier;

        if (![bundleIdentifier
              isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        /*
         * Install runtime hooks.
         */

        BMInstallWindowHooks();

        /*
         * Observe device orientation.
         */

        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        if (center == nil) {
            return;
        }

        [center addObserverForName:
                    UIDeviceOrientationDidChangeNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(
                        __unused NSNotification *note
                    ) {

            BMOrientationNotification(note);
        }];

        /*
         * Observe scene activation.
         */

        [center addObserverForName:
                    UISceneDidActivateNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(
                        __unused NSNotification *note
                    ) {

            BMOrientationNotification(note);
        }];

        /*
         * Observe windows becoming visible.
         */

        [center addObserverForName:
                    UIWindowDidBecomeVisibleNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(
                        __unused NSNotification *note
                    ) {

            BMOrientationNotification(note);
        }];
    }
}
