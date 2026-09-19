#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL BMIsLandscapeInterfaceOrientation(
    UIInterfaceOrientation orientation
)
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

    NSSet *scenes =
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

static BOOL BMIsSpringBoardProcess(void)
{
    NSString *identifier =
        NSBundle.mainBundle.bundleIdentifier;

    return [identifier isEqualToString:
            @"com.apple.springboard"];
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
}

static void BMRefreshViewController(
    UIViewController *controller
)
{
    if (controller == nil) {
        return;
    }

    BMInvalidateControllerOrientation(controller);

    UIView *view =
        controller.view;

    if (view != nil) {

        [view setNeedsLayout];
        [view layoutIfNeeded];
    }
}

static void BMRefreshWindow(
    UIWindow *window
)
{
    if (window == nil) {
        return;
    }

    UIViewController *root =
        window.rootViewController;

    if (root != nil) {
        BMRefreshViewController(root);
    }

    [window setNeedsLayout];
    [window layoutIfNeeded];
}

static void BMRequestSceneOrientation(
    UIWindowScene *windowScene,
    UIInterfaceOrientation orientation
)
{
    if (windowScene == nil) {
        return;
    }

    if (@available(iOS 16.0, *)) {

        UIInterfaceOrientationMask mask;

        switch (orientation) {

            case UIInterfaceOrientationLandscapeLeft:
                mask =
                    UIInterfaceOrientationMaskLandscapeLeft;
                break;

            case UIInterfaceOrientationLandscapeRight:
                mask =
                    UIInterfaceOrientationMaskLandscapeRight;
                break;

            case UIInterfaceOrientationPortraitUpsideDown:
                mask =
                    UIInterfaceOrientationMaskPortraitUpsideDown;
                break;

            case UIInterfaceOrientationPortrait:
            default:
                mask =
                    UIInterfaceOrientationMaskPortrait;
                break;
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
                    mask
                );

        if (preferences == nil) {
            return;
        }

        SEL requestSelector =
            NSSelectorFromString(
                @"requestGeometryUpdateWithPreferences:errorHandler:"
            );

        if (![windowScene
              respondsToSelector:requestSelector]) {
            return;
        }

        void (^errorHandler)(NSError *) =
            ^(__unused NSError *error) {
            };

        ((void (*)(id, SEL, id, id))
            objc_msgSend)(
                windowScene,
                requestSelector,
                preferences,
                errorHandler
            );
    }
}

static void BMUpdateAllScenes(
    UIInterfaceOrientation orientation
)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (application == nil) {
        return;
    }

    NSSet *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        UISceneActivationState state =
            windowScene.activationState;

        if (state ==
            UISceneActivationStateUnattached) {
            continue;
        }

        NSArray *windows =
            windowScene.windows;

        for (UIWindow *window in windows) {

            if (window == nil) {
                continue;
            }

            if (window.hidden) {
                continue;
            }

            BMRefreshWindow(window);
        }

        BMRequestSceneOrientation(
            windowScene,
            orientation
        );
    }
}

static void BMForceOrientation(void)
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

                if (orientation ==
                    UIInterfaceOrientationUnknown) {

                    orientation =
                        BMCurrentInterfaceOrientation();
                }

                if (orientation ==
                    UIInterfaceOrientationUnknown) {
                    return;
                }

                BMUpdateAllScenes(
                    orientation
                );
            }
        }
    );
}

static void BMForceOrientationDelayed(void)
{
    BMForceOrientation();

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.15 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            BMForceOrientation();
        }
    );

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.40 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            BMForceOrientation();
        }
    );

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.80 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            BMForceOrientation();
        }
    );
}

static void BMDeviceOrientationChanged(
    __unused NSNotification *notification
)
{
    BMForceOrientationDelayed();
}

static void BMSceneActivated(
    __unused NSNotification *notification
)
{
    BMForceOrientationDelayed();
}

static void BMWindowVisible(
    __unused NSNotification *notification
)
{
    BMForceOrientationDelayed();
}

static void BMApplicationActive(
    __unused NSNotification *notification
)
{
    BMForceOrientationDelayed();
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

        BMApplicationActive(notification);
    }];
}

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void)
{
    @autoreleasepool {

        if (!BMIsSpringBoardProcess()) {
            return;
        }

        BMInstallNotifications();

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                BMForceOrientation();
            }
        );
    }
}
