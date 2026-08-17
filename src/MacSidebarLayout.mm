//
//  MacSidebarLayout.mm
//  modizer
//

#import "MacSidebarLayout.h"

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
}

@end
