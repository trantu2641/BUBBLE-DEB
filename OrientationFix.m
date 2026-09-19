#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Safety

static BOOL BMIsValidWindow(UIWindow *window)
{
    if (window == nil) {
        return NO;
    }

    UIWindowScene *scene = window.windowScene;

    if (scene == nil) {
        return NO;
    }

    CGRect bounds = window.bounds;

    if (bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return NO;
    }

    return YES;
}

#pragma mark - Safe relayout

static void BMRelayoutWindow(UIWindow *window)
{
    if (!BMIsValidWindow(window)) {
        return;
    }

    @try {

        [window setNeedsLayout];
        [window layoutIfNeeded];

        UIViewController *rootViewController = window.rootViewController;

        if (rootViewController != nil) {

            UIView *rootView = rootViewController.view;

            if (rootView != nil) {
                [rootView setNeedsLayout];
                [rootView layoutIfNeeded];
            }
        }

    }
    @catch (__unused NSException *exception) {
        /*
         * Safety:
         * never allow an exception to escape into SpringBoard.
         */
    }
}

#pragma mark - Relayout all active scenes

static void BMRelayoutAllWindows(void)
{
    UIApplication *application = UIApplication.sharedApplication;

    if (application == nil) {
        return;
    }

    @try {

        /*
         * Do NOT use application.windows.
         *
         * iOS 15+:
         * enumerate connected UIWindowScene objects instead.
         */

        NSSet<UIScene *> *connectedScenes =
            application.connectedScenes;

        for (UIScene *scene in connectedScenes) {

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

                if (!BMIsValidWindow(window)) {
                    continue;
                }

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

#pragma mark - Orientation notification

static void BMOrientationChanged(void)
{
    /*
     * Wait until UIKit has finished updating
     * the scene geometry before relayout.
     */

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {

            BMRelayoutAllWindows();

            /*
             * A second layout pass is useful because
             * BubbleMe may update its own hierarchy
             * one run-loop later.
             */

            dispatch_async(dispatch_get_main_queue(), ^{
                @autoreleasepool {
                    BMRelayoutAllWindows();
                }
            });
        }
    });
}

#pragma mark - UIWindow hook

%hook UIWindow

- (void)setBounds:(CGRect)bounds
{
    %orig;

    if (self.windowScene == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            BMRelayoutWindow(self);
        }
    });
}

- (void)setFrame:(CGRect)frame
{
    %orig;

    if (self.windowScene == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            BMRelayoutWindow(self);
        }
    });
}

%end

#pragma mark - UIWindowScene hook

%hook UIWindowScene

- (void)setGeometry:(id)geometry
{
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {

            UIWindowScene *scene = self;

            if (scene == nil) {
                return;
            }

            NSArray<UIWindow *> *windows =
                scene.windows;

            for (UIWindow *window in windows) {
                BMRelayoutWindow(window);
            }
        }
    });
}

%end

#pragma mark - UIApplicationDelegate style orientation notification

%hook UIDevice

- (void)setOrientation:(UIDeviceOrientation)orientation
{
    %orig;

    /*
     * IMPORTANT:
     *
     * We do NOT change the orientation here.
     * We only observe the change and ask UIKit
     * to perform another layout pass.
     */

    BMOrientationChanged();
}

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        NSString *bundleIdentifier =
            NSBundle.mainBundle.bundleIdentifier;

        /*
         * Safety guard:
         * this dylib should only operate inside SpringBoard.
         */

        if (![bundleIdentifier
              isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        if (center == nil) {
            return;
        }

        /*
         * Device orientation.
         */

        [center addObserverForName:
                    UIDeviceOrientationDidChangeNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {

            BMOrientationChanged();
        }];

        /*
         * Scene activation / geometry changes.
         */

        [center addObserverForName:
                    UISceneDidActivateNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {

            BMOrientationChanged();
        }];

        [center addObserverForName:
                    UIWindowDidBecomeVisibleNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {

            BMOrientationChanged();
        }];
    }
}
