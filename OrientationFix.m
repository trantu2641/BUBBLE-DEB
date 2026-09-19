#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static IMP BMOriginalSetFrame = NULL;
static IMP BMOriginalSetBounds = NULL;

static BOOL BMValidWindow(UIWindow *window)
{
    if (window == nil)
        return NO;

    if (window.windowScene == nil)
        return NO;

    CGRect b = window.bounds;

    return b.size.width > 0.0 &&
           b.size.height > 0.0;
}

static void BMRelayoutWindow(UIWindow *window)
{
    if (!BMValidWindow(window))
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
    UIApplication *app =
        UIApplication.sharedApplication;

    if (app == nil)
        return;

    @try {

        NSSet<UIScene *> *scenes =
            app.connectedScenes;

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
    dispatch_async(dispatch_get_main_queue(), ^{

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
    });
}

static void BMSetFrame(
    UIWindow *self,
    SEL selector,
    CGRect frame
)
{
    if (BMOriginalSetFrame != NULL) {

        ((void (*)(id, SEL, CGRect))
            BMOriginalSetFrame)(
                self,
                selector,
                frame
            );
    }

    if (self.windowScene != nil)
        BMScheduleRelayout();
}

static void BMSetBounds(
    UIWindow *self,
    SEL selector,
    CGRect bounds
)
{
    if (BMOriginalSetBounds != NULL) {

        ((void (*)(id, SEL, CGRect))
            BMOriginalSetBounds)(
                self,
                selector,
                bounds
            );
    }

    if (self.windowScene != nil)
        BMScheduleRelayout();
}

static void BMSwizzle(
    Class cls,
    SEL originalSelector,
    SEL replacementSelector,
    IMP *originalIMP
)
{
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
        replacementMethod == NULL)
        return;

    if (originalIMP != NULL)
        *originalIMP =
            method_getImplementation(originalMethod);

    method_exchangeImplementations(
        originalMethod,
        replacementMethod
    );
}

static void BMInstallHooks(void)
{
    Class windowClass =
        objc_getClass("UIWindow");

    if (windowClass == Nil)
        return;

    Method frameMethod =
        class_getInstanceMethod(
            windowClass,
            @selector(setFrame:)
        );

    if (frameMethod != NULL) {

        class_addMethod(
            windowClass,
            @selector(bm_orientationFix_setFrame:),
            (IMP)BMSetFrame,
            method_getTypeEncoding(frameMethod)
        );

        BMSwizzle(
            windowClass,
            @selector(setFrame:),
            @selector(bm_orientationFix_setFrame:),
            &BMOriginalSetFrame
        );
    }

    Method boundsMethod =
        class_getInstanceMethod(
            windowClass,
            @selector(setBounds:)
        );

    if (boundsMethod != NULL) {

        class_addMethod(
            windowClass,
            @selector(bm_orientationFix_setBounds:),
            (IMP)BMSetBounds,
            method_getTypeEncoding(boundsMethod)
        );

        BMSwizzle(
            windowClass,
            @selector(setBounds:),
            @selector(bm_orientationFix_setBounds:),
            &BMOriginalSetBounds
        );
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
              isEqualToString:@"com.apple.springboard"])
            return;

        BMInstallHooks();

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
