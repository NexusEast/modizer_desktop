//
//  MacSidebarLayout.mm
//  modizer
//

#import "MacSidebarLayout.h"
#import "ModizerConstants.h"

@implementation MacSidebarLayout

+ (instancetype)loadFromNib {
    NSArray *objects = [[NSBundle mainBundle] loadNibNamed:@"MacSidebarLayout" owner:nil options:nil];
    for (id object in objects) {
        if ([object isKindOfClass:[MacSidebarLayout class]]) {
            return object;
        }
    }
    return nil;
}

- (void)awakeFromNib {
    [super awakeFromNib];
}

- (void)prepareForRuntime {
    self.ibGuideLabel.hidden = YES;
    [self styleTabSegment];
}

- (void)styleTabSegment {
    UIView *host = self.tabHost;
    UISegmentedControl *segment = self.tabSegment;
    UIColor *track = [UIColor colorWithWhite:1.0 alpha:0.10];
    UIColor *selected = [UIColor colorWithWhite:1.0 alpha:0.22];
    CGFloat radius = 11.0;
    if (host) {
        host.backgroundColor = track;
        host.clipsToBounds = YES;
        host.layer.cornerRadius = radius;
        host.layer.borderWidth = 0;
        if (@available(iOS 13.0, *)) {
            host.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
    if (!segment) {
        return;
    }
    segment.backgroundColor = [UIColor clearColor];
    segment.selectedSegmentTintColor = selected;
    segment.layer.cornerRadius = 0;
    segment.clipsToBounds = NO;
    UIImage *blank = [[UIImage alloc] init];
    [segment setDividerImage:blank forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    UIImage * (^fill)(UIColor *) = ^UIImage *(UIColor *color) {
        CGSize size = CGSizeMake(16.0, 16.0);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        [color setFill];
        UIRectFill(CGRectMake(0, 0, size.width, size.height));
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return [img resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    };
    [segment setBackgroundImage:fill([UIColor clearColor]) forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [segment setBackgroundImage:fill(selected) forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
    [segment setBackgroundImage:fill(selected) forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    UIFont *normalFont = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    UIFont *selectedFont = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    [segment setTitleTextAttributes:@{
        NSFontAttributeName: normalFont,
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.58]
    } forState:UIControlStateNormal];
    [segment setTitleTextAttributes:@{
        NSFontAttributeName: selectedFont,
        NSForegroundColorAttributeName: [UIColor whiteColor]
    } forState:UIControlStateSelected];
    [segment setTitleTextAttributes:@{
        NSFontAttributeName: selectedFont,
        NSForegroundColorAttributeName: [UIColor whiteColor]
    } forState:UIControlStateHighlighted];
}

@end
