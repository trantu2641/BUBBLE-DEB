#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Safety

static BOOL BMIsValidWindow(UIWindow *window)
{
    if (!window) {
        return NO;
    }

    if (!window.windowScene) {
        return NO;
    }

    CGRect bounds = window.bounds;

    if (bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return NO;
    }

    return YES;
}

static BOOL BMIsLandscape(UIWindow *window)
{
    if (!BMIsValidWindow(window)) {
        return NO;
    }

    CGRect bounds = window.bounds;

    return bounds.size.width > bounds.size.height;
}

#pragma mark - Safe relayout

static void BMRelayoutWindow(UIWindow *window)
{
    if (!BMIsValidWindow(window)) {
        return;
    }

    /*
     * Do NOT modify:
     *
     * - interfaceOrientation
     * - transform
     * - frame
     * - bounds
     *
     * We only request a fresh layout.
     */

    @try {
        [window setNeedsLayout];
        [window layoutIfNeeded];

        UIViewController *root = window.rootViewController;

        if (root) {
            [root.view setNeedsLayout];
            [root.view layoutIfNeeded];
        }
    }
    @catch (__unused NSException *exception) {
        /*
         * Fail safe:
         * never propagate an exception into SpringBoard.
         */
    }
}

#pragma mark - Orientation notification

static void BMOrientationChanged(NSNotification *notification)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {

            UIApplication *application = UIApplication.sharedApplication;

            if (!application) {
                return;
            }

            NSArray<UIWindow *> *windows = application.windows;

            for (UIWindow *window in windows) {

                if (!BMIsValidWindow(window)) {
                    continue;
                }

                /*
                 * Only relayout windows.
                 * We intentionally do not force orientation.
                 */

                BOOL landscape = BMIsLandscape(window);

                (void)landscape;

                BMRelayoutWindow(window);
            }
        }
    });
}

#pragma mark - UIApplication

%hook UIApplication

- (void)sendEvent:(UIEvent *)event
{
    %orig;

    if (!event) {
        return;
    }

    if (event.type != UIEventTypeMotion) {
        return;
    }

    if (event.subtype != UIEventSubtypeMotionShake) {
        return;
    }

    /*
     * No orientation changes are performed here.
     *
     * This hook is intentionally harmless.
     */
}

%end

#pragma mark - UIWindow

%hook UIWindow

- (void)setBounds:(CGRect)bounds
{
    %orig;

    /*
     * Do not modify the bounds.
     * Just allow BubbleMe/window hierarchy to relayout.
     */

    if (!self.windowScene) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        BMRelayoutWindow(self);
    });
}

- (void)setFrame:(CGRect)frame
{
    %orig;

    if (!self.windowScene) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        BMRelayoutWindow(self);
    });
}

%end

#pragma mark - UIScene

%hook UIWindowScene

- (void)setGeometry:(id)geometry
{
    %orig;

    /*
     * iOS updates scene geometry here during rotation.
     * We do NOT replace the geometry or force Portrait.
     */

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in self.windows) {
            BMRelayoutWindow(window);
        }
    });
}

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        /*
         * Only load in SpringBoard.
         *
         * The plist also filters SpringBoard,
         * but this extra guard is intentional.
         */

        NSString *bundleIdentifier =
            NSBundle.mainBundle.bundleIdentifier;

        if (![bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        if (!center) {
            return;
        }

        [center addObserverForName:
                    UIDeviceOrientationDidChangeNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {

            BMOrientationChanged(note);
        }];
    }
}
