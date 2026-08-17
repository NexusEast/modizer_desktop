//
//  ModizerMacWindowManager.m
//  modizer
//
//  Created by Yohann Magnien David on 29/11/2025.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "../ModizerConstants.h"

static const CGFloat kMDZStatusItemWidth = 228.0;
static const CGFloat kMDZStatusIconSide = 13.0;
static const CGFloat kMDZStatusPad = 6.0;

static NSString *MDZAppLoc(NSString *key) {
    return [[NSBundle mainBundle] localizedStringForKey:key value:key table:nil];
}

static NSString *MDZFormatClock(int milliseconds) {
    if (milliseconds < 0) milliseconds = 0;
    int seconds = milliseconds / 1000;
    return [NSString stringWithFormat:@"%02d:%02d", seconds / 60, seconds % 60];
}

static BOOL MDZIsAppWindow(NSWindow *window) {
    if (!window) {
        return NO;
    }
    if ((window.styleMask & NSWindowStyleMaskTitled) == 0) {
        return NO;
    }
    return window.frame.size.height >= 80.0;
}

@interface MDZMacNowPlayingView : NSView
@property (nonatomic, copy) NSString *trackTitle;
@property (nonatomic, copy) NSString *timeText;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) CGFloat marqueeOffset;
@property (nonatomic, assign) NSTimeInterval marqueeHoldUntil;
@property (nonatomic, assign) BOOL marqueeReturning;
@end

@implementation MDZMacNowPlayingView

- (BOOL)allowsVibrancy {
    return YES;
}

- (BOOL)isFlipped {
    return NO;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (NSFont *)titleFont {
    return [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
}

- (NSFont *)timeFont {
    if (@available(macOS 10.15, *)) {
        return [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    }
    return [NSFont systemFontOfSize:11.0];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    NSColor *color = [NSColor labelColor];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:nil];
    icon.template = YES;
    CGFloat iconY = floor((NSHeight(bounds) - kMDZStatusIconSide) * 0.5);
    NSRect iconRect = NSMakeRect(kMDZStatusPad, iconY, kMDZStatusIconSide, kMDZStatusIconSide);
    [icon drawInRect:iconRect
            fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver
            fraction:1.0
      respectFlipped:YES
               hints:nil];

    NSDictionary *timeAttrs = @{
        NSFontAttributeName: [self timeFont],
        NSForegroundColorAttributeName: color,
    };
    NSSize timeSize = [self.timeText sizeWithAttributes:timeAttrs];
    CGFloat timeX = NSMaxX(bounds) - kMDZStatusPad - ceil(timeSize.width);
    NSPoint timeOrigin = NSMakePoint(timeX, floor((NSHeight(bounds) - timeSize.height) * 0.5));
    [self.timeText drawAtPoint:timeOrigin withAttributes:timeAttrs];

    NSString *title = self.trackTitle.length ? self.trackTitle : MDZAppLoc(@"Now playing");
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [self titleFont],
        NSForegroundColorAttributeName: color,
    };
    NSSize titleSize = [title sizeWithAttributes:titleAttrs];
    CGFloat titleX = NSMaxX(iconRect) + 5.0;
    CGFloat titleMaxX = timeX - 8.0;
    CGFloat titleWidth = titleMaxX - titleX;
    if (titleWidth <= 8.0) {
        return;
    }

    NSRect clip = NSMakeRect(titleX, 0, titleWidth, NSHeight(bounds));
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:clip];
    [path addClip];

    CGFloat drawX = titleX;
    if (titleSize.width > titleWidth) {
        drawX -= self.marqueeOffset;
    }
    NSPoint titleOrigin = NSMakePoint(drawX, floor((NSHeight(bounds) - titleSize.height) * 0.5));
    [title drawAtPoint:titleOrigin withAttributes:titleAttrs];
    [ctx restoreGraphicsState];
}

- (void)advanceMarquee:(NSTimeInterval)now {
    NSString *title = self.trackTitle.length ? self.trackTitle : @"";
    if (title.length == 0) {
        self.marqueeOffset = 0;
        return;
    }
    NSSize titleSize = [title sizeWithAttributes:@{NSFontAttributeName: [self titleFont]}];
    NSSize timeSize = [self.timeText sizeWithAttributes:@{NSFontAttributeName: [self timeFont]}];
    CGFloat titleWidth = NSWidth(self.bounds) - kMDZStatusPad * 2.0 - kMDZStatusIconSide - 5.0 - 8.0 - ceil(timeSize.width);
    CGFloat overflow = titleSize.width - titleWidth;
    if (overflow <= 4.0) {
        self.marqueeOffset = 0;
        self.marqueeReturning = NO;
        self.marqueeHoldUntil = now + 1.2;
        return;
    }
    if (now < self.marqueeHoldUntil) {
        return;
    }
    self.marqueeOffset += 18.0 * (1.0 / 30.0);
    if (self.marqueeOffset > overflow + 12.0) {
        self.marqueeOffset = 0;
        self.marqueeHoldUntil = now + 1.4;
    }
}

@end

@interface ModizerMacWindowManager : NSObject <NSMenuDelegate>
+ (void)setAlwaysOnTop:(BOOL)enabled;
+ (void)enableAlwaysOnTop;
+ (void)disableAlwaysOnTop;
+ (void)applyDesktopWindowGeometry;
+ (void)installNowPlayingStatusItem;
+ (void)updateNowPlaying:(NSDictionary *)info;
@end

@implementation ModizerMacWindowManager

static NSStatusItem *sStatusItem;
static MDZMacNowPlayingView *sNowPlayingView;
static NSTimer *sTickTimer;
static NSString *sTitle = @"";
static int sElapsedMS = 0;
static int sDurationMS = 0;
static BOOL sPlaying = NO;
static BOOL sPaused = NO;
static NSTimeInterval sLastSync = 0;
static ModizerMacWindowManager *sAgent;

+ (void)setAlwaysOnTop:(BOOL)enabled {
#ifdef MDZ_MACOS_WINDOW_AOT
    NSArray *windows = [NSApp windows];
    
    for (NSWindow *window in windows) {
        if (!MDZIsAppWindow(window)) {
            continue;
        }
        if (enabled) {
            // NSFloatingWindowLevel = 3 (au-dessus des fenêtres normales)
            // NSStatusWindowLevel = 25 (encore plus haut, comme les menubar items)
            [window setLevel:NSFloatingWindowLevel];
            
            // Optionnel: rendre visible sur tous les espaces
            [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                          NSWindowCollectionBehaviorFullScreenAuxiliary];
        } else {
            [window setLevel:NSNormalWindowLevel];
            [window setCollectionBehavior:NSWindowCollectionBehaviorDefault];
        }
    }
#endif
}

+ (void)enableAlwaysOnTop {
    [self setAlwaysOnTop:YES];
}

+ (void)disableAlwaysOnTop {
    [self setAlwaysOnTop:NO];
}

+ (void)applyDesktopWindowGeometry {
    NSSize content = NSMakeSize(MODIZER_MAC_WIDTH_DEFAULT, MODIZER_MAC_HEIGHT_DEFAULT);
    NSSize minSize = NSMakeSize(MODIZER_MACM1_WIDTH_MIN, MODIZER_MACM1_HEIGHT_MIN);
    for (NSWindow *window in [NSApp windows]) {
        if (!MDZIsAppWindow(window)) {
            continue;
        }
        [window setContentMinSize:minSize];
        [window setContentSize:content];
    }
}

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installNowPlayingStatusItem];
    });
}

+ (ModizerMacWindowManager *)agent {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sAgent = [[ModizerMacWindowManager alloc] init];
    });
    return sAgent;
}

+ (void)installNowPlayingStatusItem {
    if (sStatusItem) {
        return;
    }
    sStatusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    sStatusItem.autosaveName = @"modizer.nowPlaying";
    sStatusItem.button.image = [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:@"Modizer"];
    sStatusItem.button.image.template = YES;
    sStatusItem.button.toolTip = @"Modizer";
    sStatusItem.button.imagePosition = NSImageOnly;

    sNowPlayingView = [[MDZMacNowPlayingView alloc] initWithFrame:NSMakeRect(0, 0, kMDZStatusItemWidth, 22)];
    sNowPlayingView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    sNowPlayingView.hidden = YES;
    [sStatusItem.button addSubview:sNowPlayingView];

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Modizer"];
    menu.delegate = [self agent];
    sStatusItem.menu = menu;

    sTickTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                         target:self
                                       selector:@selector(tickNowPlaying)
                                       userInfo:nil
                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:sTickTimer forMode:NSRunLoopCommonModes];
}

+ (int)displayedElapsedMS {
    int elapsed = sElapsedMS;
    if (sPlaying && !sPaused && sLastSync > 0) {
        elapsed += (int)((CFAbsoluteTimeGetCurrent() - sLastSync) * 1000.0);
        if (sDurationMS > 0 && elapsed > sDurationMS) {
            elapsed = sDurationMS;
        }
    }
    return elapsed;
}

+ (NSString *)displayedTimeText {
    int elapsed = [self displayedElapsedMS];
    if (sDurationMS > 0) {
        return [NSString stringWithFormat:@"%@ / %@", MDZFormatClock(elapsed), MDZFormatClock(sDurationMS)];
    }
    if (sTitle.length == 0) {
        return @"";
    }
    return MDZFormatClock(elapsed);
}

+ (void)tickNowPlaying {
    if (!sNowPlayingView || sNowPlayingView.hidden) {
        return;
    }
    sNowPlayingView.timeText = [self displayedTimeText];
    [sNowPlayingView advanceMarquee:CFAbsoluteTimeGetCurrent()];
    [sNowPlayingView setNeedsDisplay:YES];
}

+ (void)updateNowPlaying:(NSDictionary *)info {
    if (!sStatusItem) {
        [self installNowPlayingStatusItem];
    }
    NSString *title = info[@"title"];
    if (![title isKindOfClass:[NSString class]]) {
        title = @"";
    }
    BOOL titleChanged = ![title isEqualToString:sTitle];
    sTitle = [title copy];
    sElapsedMS = [info[@"elapsedMS"] intValue];
    sDurationMS = [info[@"durationMS"] intValue];
    sPlaying = [info[@"playing"] boolValue];
    sPaused = [info[@"paused"] boolValue];
    sLastSync = CFAbsoluteTimeGetCurrent();

    BOOL hasTrack = sTitle.length > 0;
    if (hasTrack) {
        sStatusItem.length = kMDZStatusItemWidth;
        sStatusItem.button.image = nil;
        sStatusItem.button.imagePosition = NSNoImage;
        sNowPlayingView.hidden = NO;
        sNowPlayingView.frame = sStatusItem.button.bounds;
        sNowPlayingView.trackTitle = sTitle;
        sNowPlayingView.playing = sPlaying && !sPaused;
        sNowPlayingView.timeText = [self displayedTimeText];
        if (titleChanged) {
            sNowPlayingView.marqueeOffset = 0;
            sNowPlayingView.marqueeHoldUntil = CFAbsoluteTimeGetCurrent() + 1.2;
        }
        sStatusItem.button.toolTip = [NSString stringWithFormat:@"%@\n%@", sTitle, sNowPlayingView.timeText];
        [sNowPlayingView setNeedsDisplay:YES];
    } else {
        sStatusItem.length = NSSquareStatusItemLength;
        sStatusItem.button.image = [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:@"Modizer"];
        sStatusItem.button.image.template = YES;
        sStatusItem.button.imagePosition = NSImageOnly;
        sNowPlayingView.hidden = YES;
        sStatusItem.button.toolTip = @"Modizer";
    }
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [ModizerMacWindowManager rebuildMenu:menu];
}

+ (void)rebuildMenu:(NSMenu *)menu {
    [menu removeAllItems];
    if (sTitle.length) {
        NSMenuItem *now = [[NSMenuItem alloc] initWithTitle:sTitle action:nil keyEquivalent:@""];
        now.enabled = NO;
        [menu addItem:now];
        NSMenuItem *time = [[NSMenuItem alloc] initWithTitle:[self displayedTimeText] action:nil keyEquivalent:@""];
        time.enabled = NO;
        [menu addItem:time];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    NSString *playTitle = (sPlaying && !sPaused) ? MDZAppLoc(@"Pause") : MDZAppLoc(@"Play");
    [menu addItemWithTitle:playTitle action:@selector(statusPlayPause:) keyEquivalent:@""];
    [menu addItemWithTitle:MDZAppLoc(@"Previous") action:@selector(statusPrev:) keyEquivalent:@""];
    [menu addItemWithTitle:MDZAppLoc(@"Next") action:@selector(statusNext:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:MDZAppLoc(@"Show Modizer") action:@selector(statusShowWindow:) keyEquivalent:@""];
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action) {
            item.target = [self agent];
        }
    }
}

+ (void)postCommand:(NSString *)command {
    [[NSNotificationCenter defaultCenter] postNotificationName:MDZMacStatusItemCommandNotification
                                                        object:nil
                                                      userInfo:@{MDZMacStatusItemCommandKey: command}];
}

- (void)statusPlayPause:(id)sender {
    [ModizerMacWindowManager postCommand:MDZMacStatusItemCommandPlayPause];
}

- (void)statusPrev:(id)sender {
    [ModizerMacWindowManager postCommand:MDZMacStatusItemCommandPrev];
}

- (void)statusNext:(id)sender {
    [ModizerMacWindowManager postCommand:MDZMacStatusItemCommandNext];
}

- (void)statusShowWindow:(id)sender {
    [ModizerMacWindowManager showAppWindow];
}

+ (void)showAppWindow {
    [NSApp activateIgnoringOtherApps:YES];
    for (NSWindow *window in [NSApp windows]) {
        if (!MDZIsAppWindow(window)) {
            continue;
        }
        if (window.miniaturized) {
            [window deminiaturize:nil];
        }
        [window makeKeyAndOrderFront:nil];
    }
}

@end
