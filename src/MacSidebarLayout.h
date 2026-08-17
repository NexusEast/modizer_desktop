//
//  MacSidebarLayout.h
//  modizer
//
//  Left-column chrome. Open XIB/MacSidebarLayout.xib in Interface Builder
//  (Freeform 420x48). The UISegmentedControl in Tab Segment Host is the
//  real tab bar used at runtime. Drag that host to center the tabs.
//

#import <UIKit/UIKit.h>

@interface MacSidebarLayout : UIView

@property (nonatomic, weak) IBOutlet UIView *tabHost;
@property (nonatomic, weak) IBOutlet UISegmentedControl *tabSegment;
@property (nonatomic, weak) IBOutlet UILabel *ibGuideLabel;

+ (instancetype)loadFromNib;

- (void)prepareForRuntime;

@end
