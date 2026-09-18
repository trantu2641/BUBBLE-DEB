#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL BMOFIsLandscape(void) {
    UIWindow *key = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive && ws.activationState != UISceneActivationStateForegroundInactive) continue;
        for (UIWindow *w in ws.windows) {
            if ([w isKindOfClass:NSClassFromString(@"BMBubbleWindow")]) { key = w; break; }
        }
        if (key) break;
    }
    if (!key) return NO;
    return key.bounds.size.width > key.bounds.size.height;
}

static UIWindow *BMFindBubbleWindow(void) {
    Class cls = NSClassFromString(@"BMBubbleWindow");
    if (!cls) return nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if ([w isKindOfClass:cls]) return w;
        }
    }
    return nil;
}

static void BMRelayoutBubbleWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            UIWindow *w = BMFindBubbleWindow();
            if (!w || !w.windowScene) return;
            // Fail-safe: only ask UIKit to recompute layout. Do not force a
            // controller orientation and do not apply a screen-wide transform.
            if ([w respondsToSelector:@selector(setNeedsLayout)]) [w setNeedsLayout];
            if ([w respondsToSelector:@selector(layoutIfNeeded)]) [w layoutIfNeeded];
        }
    });
}

static void BMOrientationChanged(NSNotification *n) {
    (void)n;
    BMRelayoutBubbleWindow();
}

__attribute__((constructor))
static void BubbleMeOrientationFixInit(void) {
    @autoreleasepool {
        // This fix is intentionally limited to SpringBoard/BubbleMe's own window.
        if (!NSClassFromString(@"BMBubbleWindow")) return;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            BMOrientationChanged(note);
        }];
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    }
}
