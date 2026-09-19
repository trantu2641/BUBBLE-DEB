#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL BMIsLandscapeInterfaceOrientation(UIInterfaceOrientation orientation)
{
    return orientation == UIInterfaceOrientationLandscapeLeft ||
           orientation == UIInterfaceOrientationLandscapeRight;
}

static UIInterfaceOrientation BMInterfaceOrientationFromDeviceOrientation(
    UIDeviceOrientation orientation
)
{
    switch (orientation) {

        case UIDeviceOrientationLandscapeLeft:
            return UIInterfaceOrientationLandscapeRight;

        case UIDeviceOrientationLandscapeRight:
            return UIInterfaceOrientationLandscapeLeft;

        case UIDeviceOrientationPortrait:
            return UIInterfaceOrientationPortrait;

        case UIDeviceOrientationPortraitUpsideDown:
            return UIInterfaceOrientationPortraitUpsideDown;

        default:
            return UIInterfaceOrientationUnknown;
    }
}

static UIInterfaceOrientation BMCurrentInterfaceOrientation(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (application == nil) {
        return UIInterfaceOrientationUnknown;
    }

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        UIInterfaceOrientation orientation =
            windowScene.interfaceOrientation;

        if (orientation != UIInterfaceOrientationUnknown) {
            return orientation;
        }
    }

    return UIInterfaceOrientationUnknown;
}

static BOOL BMIsOurProcessSpringBoard(void)
{
    NSString *identifier =
        NSBundle.mainBundle.bundleIdentifier;

    return [identifier isEqualToString:@"com.apple.springboard"];
}

static BOOL BMIsOrientationCapableController(UIViewController *controller)
{
    if (controller == nil) {
        return NO;
    }

    if ([controller respondsToSelector:
         @selector(supportedInterfaceOrientations)]) {
        return YES;
    }

    return NO;
}

static UIViewController *BMFindOrientationController(
    UIViewController *controller
)
{
    if (controller == nil) {
        return nil;
    }

    if (BMIsOrientationCapableController(controller)) {
        return controller;
    }

    NSArray *children =
        controller.children;

    for (UIViewController *child in children) {

        UIViewController *result =
            BMFindOrientationController(child);

        if (result != nil) {
            return result;
        }
    }

    UIViewController *presented =
        controller.presentedViewController;

    if (presented != nil) {

        UIViewController *result =
            BMFindOrientationController(presented);

        if (result != nil) {
            return result;
        }
    }

    return nil;
}

static void BMInvalidateControllerOrientation(
    UIViewController *controller
)
{
    if (controller == nil) {
        return;
    }

    SEL selector =
        NSSelectorFromString(
            @"setNeedsUpdateOfSupportedInterfaceOrientations"
        );

    if ([controller respondsToSelector:selector]) {

        ((void (*)(id, SEL))
            objc_msgSend)(
                controller,
                selector
            );
    }

    SEL legacySelector =
        NSSelectorFromString(
            @"attemptRotationToDeviceOrientation"
        );

    Class applicationClass =
        objc_getClass("UIApplication");

    if (applicationClass != Nil &&
        [UIApplication.sharedApplication
         respondsToSelector:legacySelector]) {

        ((void (*)(id, SEL))
            objc_msgSend)(
                UIApplication.sharedApplication,
                legacySelector
            );
    }
}

static void BMUpdateWindow(
    UIWindow *window,
    UIInterfaceOrientation orientation
)
{
    if (window == nil) {
        return;
    }

    UIViewController *root =
        window.rootViewController;

    if (root == nil) {
        return;
    }

    UIViewController *controller =
        BMFindOrientationController(root);

    if (controller == nil) {
        controller = root;
    }

    BMInvalidateControllerOrientation(controller);

    [controller.view setNeedsLayout];
    [controller.view layoutIfNeeded];

    [window setNeedsLayout];
    [window layoutIfNeeded];

    if (@available(iOS 16.0, *)) {

        UIWindowScene *scene =
            window.windowScene;

        if (scene == nil) {
            return;
        }

        UIInterfaceOrientation current =
            scene.interfaceOrientation;

        if (current == orientation) {
            return;
        }

        Class preferencesClass =
            NSClassFromString(
                @"UIWindowSceneGeometryPreferencesIOS"
            );

        if (preferencesClass == Nil) {
            return;
        }

        SEL initSelector =
            NSSelectorFromString(
                @"initWithInterfaceOrientations:"
            );

        if (![preferencesClass
              instancesRespondToSelector:initSelector]) {
            return;
        }

        id preferences =
            ((id (*)(id, SEL, UIInterfaceOrientationMask))
                objc_msgSend)(
                    [preferencesClass alloc],
                    initSelector,
                    (UIInterfaceOrientationMask)orientation
                );

        if (preferences == nil) {
            return;
        }

        SEL requestSelector =
            NSSelectorFromString(
                @"requestGeometryUpdateWithPreferences:errorHandler:"
            );

        if (![scene respondsToSelector:requestSelector]) {
            return;
        }

        void (^errorHandler)(NSError *) =
            ^(NSError *error) {

                if (error != nil) {

                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{
                            [controller.view setNeedsLayout];
                            [controller.view layoutIfNeeded];
                        }
                    );
                }
            };

        ((void (*)(id, SEL, id, id))
            objc_msgSend)(
                scene,
                requestSelector,
                preferences,
                errorHandler
            );
    }
}

static void BMUpdateAllWindows(
    UIInterfaceOrientation orientation
)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (application == nil) {
        return;
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

        NSArray<UIWindow *> *windows =
            windowScene.windows;

        for (UIWindow *window in windows) {

            if (window.hidden) {
                continue;
            }

            BMUpdateWindow(
                window,
                orientation
            );
        }
    }
}

static void BMForceCurrentOrientation(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            @autoreleasepool {

                UIDeviceOrientation deviceOrientation =
                    UIDevice.currentDevice.orientation;

                UIInterfaceOrientation orientation =
                    BMInterfaceOrientationFromDeviceOrientation(
                        deviceOrientation
                    );

                if (orientation == UIInterfaceOrientationUnknown) {
                    orientation =
                        BMCurrentInterfaceOrientation();
                }

                if (orientation == UIInterfaceOrientationUnknown) {
                    return;
                }

                BMUpdateAllWindows(
                    orientation
                );
            }
        }
    );
}

static void BMDeviceOrientationChanged(
    __unused NSNotification *notification
)
{
    BMForceCurrentOrientation();

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.15 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            BMForceCurrentOrientation();
        }
    );

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.40 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            BMForceCurrentOrientation();
        }
    );
}

static void BMSceneActivated(
    __unused NSNotification *notification
)
{
    BMForceCurrentOrientation();
}

static void BMWindowVisible(
    __unused NSNotification *notification
)
{
    BMForceCurrentOrientation();
}

static void BMApplicationDidBecomeActive(
    __unused NSNotification *notification
)
{
    BMForceCurrentOrientation();
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

        BMDeviceOrientationChanged(notification);
    }];

    [center addObserverForName:
                UISceneDidActivateNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMSceneActivated(notification);
    }];

    [center addObserverForName:
                UIWindowDidBecomeVisibleNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMWindowVisible(notification);
    }];

    [center addObserverForName:
                UIApplicationDidBecomeActiveNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
        ^(__unused NSNotification *notification) {

        BMApplicationDidBecomeActive(notification);
    }];
}

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void)
{
    @autoreleasepool {

        /*
         * Chạy trong SpringBoard vì BubbleMe được
         * nạp ở SpringBoard.
         */
        if (!BMIsOurProcessSpringBoard()) {
            return;
        }

        BMInstallNotifications();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                BMForceCurrentOrientation();
            }
        );
    }
}
