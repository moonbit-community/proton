#if defined(__APPLE__)
#include "../../mac_internal.h"
#import <Cocoa/Cocoa.h>
#include <math.h>

@interface NSWindow (ProtonButtonFixture)
- (void)setButtonOwner:(proton_engine_window_t *)owner;
@end

#define CHECK(condition) do { if (!(condition)) { result = __LINE__; goto cleanup; } } while (0)

static NSRect button_cluster(NSWindow *window) {
  const NSWindowButton types[] = {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton};
  NSRect cluster = NSZeroRect;
  for (int i = 0; i < 3; i++) {
    NSButton *button = [window standardWindowButton:types[i]];
    NSRect rect = [window.contentView convertRect:button.bounds fromView:button];
    cluster = i ? NSUnionRect(cluster, rect) : rect;
  }
  return cluster;
}

int32_t proton_test_button_position(int32_t overlay) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    int result = 0;
    proton_engine_window_t owner = {0};
    owner.titlebar_overlay = overlay;
    owner.window_button_visible = 1;
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    if (overlay) style |= NSWindowStyleMaskFullSizeContentView;
    NSWindow *window = [[NSClassFromString(@"ProtonWindow") alloc] initWithContentRect:NSMakeRect(0,0,640,480) styleMask:style backing:NSBackingStoreBuffered defer:NO];
    CHECK(window != nil);
    [window setReleasedWhenClosed:NO];
    if (overlay) { window.titleVisibility = NSWindowTitleHidden; window.titlebarAppearsTransparent = YES; }
    owner.window = window;
    owner.content_view = window.contentView;
    [window setButtonOwner:&owner];
    [window layoutIfNeeded];
    NSRect initial = button_cluster(window);
    CGFloat initial_top = NSMaxY(window.contentView.bounds) - NSMaxY(initial);
    char error[256] = {0};
    int32_t custom = 0, x = 0, y = 0;
    CHECK(proton_engine_window_set_button_position(&owner, 1, 16, 30, error, sizeof(error)) == PROTON_OK);
    CHECK(proton_engine_window_get_button_position(&owner, &custom, &x, &y, error, sizeof(error)) == PROTON_OK);
    CHECK(custom == overlay);
    if (overlay) {
      CHECK(x == 16 && y == 30);
      for (int i = 0; i < 4; i++) {
        if (i == 1) [window setFrame:NSMakeRect(0,0,800,600) display:NO];
        if (i == 2) CHECK(proton_engine_window_set_button_visibility(&owner, 0, error, sizeof(error)) == PROTON_OK);
        if (i == 3) CHECK(proton_engine_window_set_button_visibility(&owner, 1, error, sizeof(error)) == PROTON_OK);
        [window layoutIfNeeded];
        NSRect cluster = button_cluster(window);
        CHECK(fabs(NSMinX(cluster) - 16) < 0.1);
        CHECK(fabs(NSMaxY(window.contentView.bounds) - NSMaxY(cluster) - 30) < 0.1);
        CHECK(fabs(NSWidth(cluster) - NSWidth(initial)) < 0.1);
        NSButton *close = [window standardWindowButton:NSWindowCloseButton];
        CHECK(NSContainsRect(close.superview.bounds, close.frame));
        NSView *frame_view = window.contentView.superview;
        NSPoint center = [close convertPoint:NSMakePoint(NSMidX(close.bounds), NSMidY(close.bounds)) toView:frame_view];
        if (i != 2) CHECK([frame_view hitTest:center] == close);
        int32_t ax, ay, aw, ah, zoom;
        CHECK(proton_engine_window_get_titlebar_area(&owner, &ax, &ay, &aw, &ah, &zoom, error, sizeof(error)) == PROTON_OK);
        CHECK(ah >= 30 + NSHeight(cluster));
        CHECK(i == 2 ? ax == 0 : ax >= NSMaxX(cluster));
      }
      CHECK(proton_engine_window_set_button_position(&owner, 1, 0, 0, error, sizeof(error)) == PROTON_OK);
      CHECK(proton_engine_window_get_button_position(&owner, &custom, &x, &y, error, sizeof(error)) == PROTON_OK);
      CHECK(custom == 1 && x == 0 && y == 0);
    } else { CHECK(NSEqualRects(initial, button_cluster(window))); }
    CHECK(proton_engine_window_set_button_position(&owner, 0, 0, 0, error, sizeof(error)) == PROTON_OK);
    CHECK(proton_engine_window_get_button_position(&owner, &custom, &x, &y, error, sizeof(error)) == PROTON_OK);
    CHECK(custom == 0);
    [window setFrame:NSMakeRect(0,0,640,480) display:NO];
    [window layoutIfNeeded];
    NSRect restored = button_cluster(window);
    CHECK(fabs(NSMinX(restored) - NSMinX(initial)) < 0.1);
    CHECK(fabs(NSMaxY(window.contentView.bounds) - NSMaxY(restored) - initial_top) < 0.1);
    CHECK(fabs(NSWidth(restored) - NSWidth(initial)) < 0.1);
cleanup:
    [window setButtonOwner:NULL];
    [window close];
    [window release];
    return result;
  }
}
#endif
