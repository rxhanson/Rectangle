#import <AppKit/AppKit.h>

/// A private live backdrop, or nil when the current OS cannot provide it.
/// Call only in the disposable renderer process, on its main thread.
NSVisualEffectView * _Nullable RectangleCreateFrostBackdrop(NSRect frame, CGFloat radius);

/// Layer-hosted variant for compositor-owned geometry animations.
CALayer * _Nullable RectangleCreateFrostBackdropLayer(NSRect frame, CGFloat radius);
