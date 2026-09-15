#import "WindowFrostBackdrop.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

@interface RectangleFrostBackdropView : NSVisualEffectView
@property(nonatomic, strong) CALayer *backdrop;
@end

@implementation RectangleFrostBackdropView
- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.backdrop.frame = self.bounds;
    [CATransaction commit];
}
@end

CALayer *RectangleCreateFrostBackdropLayer(NSRect frame, CGFloat radius) {
    // Swift cannot catch an Objective-C KVC exception. Keep all private setup
    // inside this boundary so a changed OS implementation falls back to AppKit.
    @try {
        Class backdropClass = NSClassFromString(@"CABackdropLayer");
        Class filterClass = NSClassFromString(@"CAFilter");
        SEL factory = NSSelectorFromString(@"filterWithType:");
        if (!backdropClass || ![filterClass respondsToSelector:factory]) return nil;
        CALayer *backdrop = [backdropClass layer];
        id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, factory, @"gaussianBlur");
        if (!backdrop || !filter) return nil;
        [filter setValue:@YES forKey:@"inputNormalizeEdges"];
        [filter setValue:@(radius) forKey:@"inputRadius"];
        if (fabs([[filter valueForKey:@"inputRadius"] doubleValue] - radius) > .01) return nil;
        [backdrop setValue:@YES forKey:@"windowServerAware"];
        [backdrop setValue:@YES forKey:@"enabled"];
        [backdrop setValue:@1.0 forKey:@"scale"];
        [backdrop setValue:@0.1 forKey:@"bleedAmount"];
        [backdrop setValue:@YES forKey:@"disablesOccludedBackdropBlurs"];
        [backdrop setValue:@NO forKey:@"ignoresOffscreenGroups"];
        [backdrop setValue:@NO forKey:@"allowsInPlaceFiltering"];
        backdrop.filters = @[filter];
        backdrop.masksToBounds = YES;
        backdrop.frame = (NSRect){NSZeroPoint, frame.size};
        backdrop.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;

        return backdrop;
    } @catch (NSException *exception) {
        return nil;
    }
}

NSVisualEffectView *RectangleCreateFrostBackdrop(NSRect frame, CGFloat radius) {
    @try {
        CALayer *backdrop = RectangleCreateFrostBackdropLayer(frame, radius);
        if (!backdrop) return nil;
        RectangleFrostBackdropView *view = [[RectangleFrostBackdropView alloc] initWithFrame:frame];
        view.material = NSVisualEffectMaterialFullScreenUI;
        view.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        view.state = NSVisualEffectStateActive;
        view.wantsLayer = YES;
        [view setValue:@YES forKey:@"clear"];
        view.layer.masksToBounds = YES;
        view.backdrop = backdrop;
        [view.layer insertSublayer:backdrop atIndex:0];
        return view;
    } @catch (NSException *exception) {
        return nil;
    }
}
