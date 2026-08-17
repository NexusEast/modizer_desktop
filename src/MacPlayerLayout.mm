//
//  MacPlayerLayout.mm
//  modizer
//

#import "MacPlayerLayout.h"
#import "ModizerConstants.h"
#import "EQViewController.h"
#import "NVPeakingEQFilter.h"

extern NVPeakingEQFilter *nvdsp_PEQ[EQUALIZER_NB_BANDS];
extern BOOL nvdsp_EQ;

@implementation MacPlayerLayout {
    BOOL mdzEqWired;
}

+ (instancetype)loadFromNib {
    NSArray *objects = [[NSBundle mainBundle] loadNibNamed:@"MacPlayerLayout" owner:nil options:nil];
    for (id object in objects) {
        if ([object isKindOfClass:[MacPlayerLayout class]]) {
            return object;
        }
    }
    return nil;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self mdzRoundPanel:self.subsongPanel];
    [self mdzRoundPanel:self.voicesPanel];
    [self mdzRoundPanel:self.eqPanel];
    [self styleTransportButtonsPlaying:YES];
    [self mdzWireEqualizerIfNeeded];
}

- (void)prepareForRuntime {
    self.ibGuideLabel.hidden = YES;
    self.visualizerPlaceholder.hidden = YES;
    self.eqApplySwitch.hidden = YES;
    self.eqApplyLabel.hidden = YES;
    NSArray *hosts = @[
        self.commandLeftHost ?: [NSNull null],
        self.commandTitleHost ?: [NSNull null],
        self.commandRightHost ?: [NSNull null],
        self.progressBar ?: [NSNull null]
    ];
    for (id hostObj in hosts) {
        if (hostObj == [NSNull null]) {
            continue;
        }
        UIView *host = hostObj;
        for (UIView *sub in host.subviews) {
            if ([sub isKindOfClass:[UILabel class]]) {
                sub.hidden = YES;
            } else if (host == self.progressBar && ![sub isKindOfClass:[UIControl class]]) {
                sub.hidden = YES;
            } else if (host == self.progressBar && [sub isKindOfClass:[UISlider class]]) {
                sub.hidden = YES;
            }
        }
    }
    [self syncEqualizerFromEngine];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self mdzLayoutChromeStack];
    [self mdzLayoutTransportButtons];
    CGFloat gap = 8.0;
    CGFloat rowW = CGRectGetWidth(self.bottomRow.bounds);
    CGFloat rowH = CGRectGetHeight(self.bottomRow.bounds);
    if (rowW > 24.0 && rowH > 8.0) {
        CGFloat cellW = (rowW - gap * 2.0) / 3.0;
        self.subsongPanel.frame = CGRectMake(0, 0, cellW, rowH);
        self.voicesPanel.frame = CGRectMake(cellW + gap, 0, cellW, rowH);
        self.eqPanel.frame = CGRectMake((cellW + gap) * 2.0, 0, cellW, rowH);
    }
    [self mdzLayoutPanel:self.subsongPanel title:self.subsongTitle body:self.subsongBody];
    [self mdzLayoutPanel:self.voicesPanel title:self.voicesTitle body:self.voicesBody];
    [self mdzLayoutPanel:self.eqPanel title:self.eqTitle body:self.eqBody];
    if (self.voicesEmptyLabel) {
        CGRect b = self.voicesBody.bounds;
        self.voicesEmptyLabel.frame = CGRectMake(4.0, MAX(0.0, (CGRectGetHeight(b) - 20.0) / 2.0), MAX(8.0, CGRectGetWidth(b) - 8.0), 20.0);
        self.voicesEmptyLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
        self.voicesEmptyLabel.adjustsFontSizeToFitWidth = YES;
        self.voicesEmptyLabel.minimumScaleFactor = 0.7;
    }
    [self mdzLayoutEqualizer];
}

- (void)mdzLayoutChromeStack {
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w < 8.0 || h < 8.0) {
        return;
    }
    CGFloat cmdH = MDZ_MAC_COMMAND_HEIGHT;
    CGFloat botH = CGRectGetHeight(self.bottomRow.bounds);
    if (botH < 80.0) {
        botH = 200.0;
    }
    CGFloat trH = CGRectGetHeight(self.transportBar.bounds);
    if (trH < 48.0) {
        trH = 80.0;
    }
    CGFloat progH = CGRectGetHeight(self.progressBar.bounds);
    if (progH < 24.0) {
        progH = 40.0;
    }
    CGFloat bottomPad = 12.0;
    CGFloat botY = MAX(cmdH + 80.0, h - botH - bottomPad);
    self.commandBar.frame = CGRectMake(0, 0, w, cmdH);
    if (self.commandTitleHost) {
        self.commandTitleHost.frame = CGRectMake(16.0, 0, MAX(8.0, w - 32.0), cmdH);
        self.commandTitleHost.backgroundColor = [UIColor clearColor];
    }
    self.bottomRow.frame = CGRectMake(12.0, botY, MAX(8.0, w - 24.0), botH);
    CGFloat trY = botY - trH;
    self.transportBar.frame = CGRectMake(0, trY, w, trH);
    self.transportBar.backgroundColor = [UIColor clearColor];
    CGFloat progY = trY - progH;
    self.progressBar.frame = CGRectMake(24.0, progY, MAX(8.0, w - 48.0), progH);
    self.progressBar.backgroundColor = [UIColor clearColor];
    CGFloat vizY = cmdH;
    self.visualizerContainer.frame = CGRectMake(0, vizY, w, MAX(80.0, progY - vizY));
}

- (void)mdzLayoutTransportButtons {
    CGFloat barW = CGRectGetWidth(self.transportBar.bounds);
    CGFloat barH = CGRectGetHeight(self.transportBar.bounds);
    if (barW < 80.0 || barH < 8.0) {
        return;
    }
    CGFloat playSide = 52.0;
    CGFloat skipSide = 44.0;
    CGFloat gap = 12.0;
    CGFloat accSide = MIN(36.0, MAX(28.0, barH - 16.0));
    CGFloat accGap = 8.0;
    CGFloat pad = 20.0;
    NSInteger leftCount = 4;
    NSInteger rightCount = 3;
    CGFloat leftW = accSide * leftCount + accGap * (leftCount - 1);
    CGFloat rightW = accSide * rightCount + accGap * (rightCount - 1);
    if (self.commandLeftHost) {
        self.commandLeftHost.backgroundColor = [UIColor clearColor];
        self.commandLeftHost.frame = CGRectMake(pad, MAX(0.0, (barH - accSide) / 2.0), leftW, accSide);
    }
    if (self.commandRightHost) {
        self.commandRightHost.backgroundColor = [UIColor clearColor];
        self.commandRightHost.frame = CGRectMake(barW - pad - rightW, MAX(0.0, (barH - accSide) / 2.0), rightW, accSide);
    }
    NSArray *buttons = @[
        self.prevButton, self.rewindButton, self.playButton,
        self.forwardButton, self.nextButton
    ];
    CGFloat total = skipSide * 4.0 + playSide + gap * 4.0;
    CGFloat x = (barW - total) / 2.0;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIButton *button = buttons[i];
        if (!button) {
            continue;
        }
        CGFloat side = (button == self.playButton) ? playSide : skipSide;
        CGFloat y = MAX(0.0, (barH - side) / 2.0);
        button.frame = CGRectMake(x, y, side, side);
        button.layer.cornerRadius = side / 2.0;
        button.clipsToBounds = YES;
        x += side + gap;
    }
}

- (void)mdzLayoutPanel:(UIView *)panel title:(UILabel *)title body:(UIView *)body {
    if (!panel) {
        return;
    }
    CGFloat w = CGRectGetWidth(panel.bounds);
    CGFloat h = CGRectGetHeight(panel.bounds);
    CGFloat titleH = 30.0;
    CGFloat inset = 12.0;
    if (title) {
        title.frame = CGRectMake(inset, 8.0, MAX(0.0, w - inset * 2.0), 20.0);
        title.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        title.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
    }
    if (body) {
        body.frame = CGRectMake(inset, titleH, MAX(0.0, w - inset * 2.0), MAX(0.0, h - titleH - inset));
        body.backgroundColor = [UIColor clearColor];
        body.clipsToBounds = YES;
    }
}

- (void)mdzRoundPanel:(UIView *)panel {
    panel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
    panel.layer.cornerRadius = 14.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    panel.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        panel.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (UISlider *)mdzEqSliderAt:(NSInteger)index {
    return (UISlider *)[self.eqBody viewWithTag:index + 1];
}

- (UILabel *)mdzEqFreqLabelAt:(NSInteger)index {
    return (UILabel *)[self.eqBody viewWithTag:201 + index];
}

- (UILabel *)mdzEqValueLabelAt:(NSInteger)index {
    return (UILabel *)[self.eqBody viewWithTag:301 + index];
}

- (void)mdzWireEqualizerIfNeeded {
    if (mdzEqWired) {
        return;
    }
    UISlider *first = [self mdzEqSliderAt:0];
    if (!first) {
        return;
    }
    mdzEqWired = YES;
    CGAffineTransform rotation = CGAffineTransformMakeRotation(-(CGFloat)M_PI / 2.0);
    for (int i = 0; i < EQUALIZER_NB_BANDS; i++) {
        UISlider *slider = [self mdzEqSliderAt:i];
        if (!slider) {
            continue;
        }
        slider.minimumValue = -12;
        slider.maximumValue = 12;
        slider.transform = rotation;
        MDZMacStyleSlider(slider, 3.0, 11.0);
        [slider addTarget:self action:@selector(mdzEqSliderChanged:) forControlEvents:UIControlEventValueChanged];
        UILabel *freq = [self mdzEqFreqLabelAt:i];
        freq.textAlignment = NSTextAlignmentCenter;
        freq.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
        freq.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightMedium];
        freq.adjustsFontSizeToFitWidth = YES;
        freq.minimumScaleFactor = 0.55;
        UILabel *value = [self mdzEqValueLabelAt:i];
        value.textAlignment = NSTextAlignmentCenter;
        value.textColor = [UIColor colorWithWhite:1.0 alpha:0.38];
        value.font = [UIFont monospacedDigitSystemFontOfSize:9.0 weight:UIFontWeightRegular];
        value.adjustsFontSizeToFitWidth = YES;
        value.minimumScaleFactor = 0.55;
    }
    [self.eqApplySwitch addTarget:self action:@selector(mdzEqSwitchChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)mdzLayoutEqualizer {
    UIView *body = self.eqBody;
    if (!body || ![self mdzEqSliderAt:0]) {
        return;
    }
    CGFloat w = CGRectGetWidth(body.bounds);
    CGFloat h = CGRectGetHeight(body.bounds);
    if (w < 40.0 || h < 40.0) {
        return;
    }
    CGFloat inset = 4.0;
    self.eqApplySwitch.hidden = YES;
    self.eqApplyLabel.hidden = YES;
    CGFloat freqH = 14.0;
    CGFloat valueH = 12.0;
    CGFloat sliderH = MAX(36.0, h - freqH - valueH - 4.0);
    CGFloat usable = MAX(10.0, w - inset * 2.0);
    CGFloat slot = usable / (CGFloat)EQUALIZER_NB_BANDS;
    CGFloat sliderW = 20.0;
    for (int i = 0; i < EQUALIZER_NB_BANDS; i++) {
        UISlider *slider = [self mdzEqSliderAt:i];
        UILabel *freq = [self mdzEqFreqLabelAt:i];
        UILabel *value = [self mdzEqValueLabelAt:i];
        CGFloat cx = inset + (i + 0.5) * slot;
        slider.frame = CGRectMake(cx - sliderW / 2.0, freqH, sliderW, sliderH);
        freq.frame = CGRectMake(inset + i * slot, 0, slot, freqH);
        value.frame = CGRectMake(inset + i * slot, freqH + sliderH, slot, valueH);
    }
}

- (void)syncEqualizerFromEngine {
    [self mdzWireEqualizerIfNeeded];
    for (int i = 0; i < EQUALIZER_NB_BANDS; i++) {
        UISlider *slider = [self mdzEqSliderAt:i];
        UILabel *freq = [self mdzEqFreqLabelAt:i];
        UILabel *value = [self mdzEqValueLabelAt:i];
        if (!nvdsp_PEQ[i]) {
            continue;
        }
        slider.value = nvdsp_PEQ[i].G;
        float f = nvdsp_PEQ[i].centerFrequency;
        if (f >= 1000) {
            freq.text = [NSString stringWithFormat:@"%.0fk", f / 1000.0f];
        } else {
            freq.text = [NSString stringWithFormat:@"%.0f", f];
        }
        value.text = [NSString stringWithFormat:@"%.1f", nvdsp_PEQ[i].G];
    }
    self.eqApplySwitch.on = nvdsp_EQ;
}

- (void)mdzEqSliderChanged:(UISlider *)sender {
    NSInteger idx = sender.tag - 1;
    if (idx < 0 || idx >= EQUALIZER_NB_BANDS || !nvdsp_PEQ[idx]) {
        return;
    }
    nvdsp_PEQ[idx].G = sender.value;
    UILabel *value = [self mdzEqValueLabelAt:idx];
    value.text = [NSString stringWithFormat:@"%.1f", sender.value];
    [EQViewController backupEQSettings];
}

- (void)mdzEqSwitchChanged:(UISwitch *)sender {
    nvdsp_EQ = sender.on;
    [EQViewController backupEQSettings];
}

- (void)mdzStyleTransportButton:(UIButton *)button image:(UIImage *)image prominent:(BOOL)prominent {
    if (!button) {
        return;
    }
    UIColor *bg = prominent
        ? [UIColor whiteColor]
        : [UIColor colorWithWhite:1.0 alpha:0.08];
    UIColor *fg = prominent
        ? [UIColor colorWithWhite:0.10 alpha:1.0]
        : [UIColor whiteColor];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
        cfg.baseForegroundColor = fg;
        cfg.baseBackgroundColor = bg;
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        cfg.image = image;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);
        button.configuration = cfg;
    } else {
        button.tintColor = fg;
        button.backgroundColor = bg;
        [button setImage:image forState:UIControlStateNormal];
    }
    CGFloat side = MIN(CGRectGetWidth(button.bounds), CGRectGetHeight(button.bounds));
    button.layer.cornerRadius = (side > 1.0) ? (side / 2.0) : (prominent ? 26.0 : 22.0);
    button.clipsToBounds = YES;
}

- (void)styleTransportButtonsPlaying:(BOOL)playing {
    UIImageSymbolConfiguration *skipCfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                          weight:UIImageSymbolWeightMedium
                                                                                           scale:UIImageSymbolScaleMedium];
    UIImageSymbolConfiguration *playCfg = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                          weight:UIImageSymbolWeightSemibold
                                                                                           scale:UIImageSymbolScaleLarge];
    [self mdzStyleTransportButton:self.prevButton
                            image:[UIImage systemImageNamed:@"backward.end.fill" withConfiguration:skipCfg]
                       prominent:NO];
    [self mdzStyleTransportButton:self.rewindButton
                            image:[UIImage systemImageNamed:@"backward.fill" withConfiguration:skipCfg]
                       prominent:NO];
    [self mdzStyleTransportButton:self.forwardButton
                            image:[UIImage systemImageNamed:@"forward.fill" withConfiguration:skipCfg]
                       prominent:NO];
    [self mdzStyleTransportButton:self.nextButton
                            image:[UIImage systemImageNamed:@"forward.end.fill" withConfiguration:skipCfg]
                       prominent:NO];
    NSString *playName = playing ? @"pause.fill" : @"play.fill";
    [self mdzStyleTransportButton:self.playButton
                            image:[UIImage systemImageNamed:playName withConfiguration:playCfg]
                       prominent:YES];
}

@end
