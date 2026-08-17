//
//  MacPlayerLayout.h
//  modizer
//
//  Mac player chrome. Open XIB/MacPlayerLayout.xib in Interface Builder
//  (not Main.storyboard and not EQViewController.xib). The canvas is a
//  Freeform 1024x720 UIKit view: Command bar, visualizer, progress,
//  transport buttons, and the three bottom panels including the EQ
//  sliders and Apply switch. Those EQ controls are the ones used at
//  runtime on Mac.
//
//  This is a UIKit (Cocoa Touch) XIB because Mac Catalyst is UIKit, not
//  AppKit. Interface Builder has no Mac device for UIKit files. If the
//  canvas looks like an iPhone:
//    1. Select the root view "Mac Player Layout"
//    2. Size inspector -> Simulated Size = Freeform
//    3. Width 1024, Height 720
//    4. Bottom "View as" bar: pick iPad landscape, not iPhone
//
//  Drag these hosts to rearrange the player:
//    commandLeftHost / commandTitleHost / commandRightHost
//    progressBar (time + slider)
//    visualizerContainer, transportBar, bottom panels
//

#import <UIKit/UIKit.h>

@interface MacPlayerLayout : UIView

@property (nonatomic, weak) IBOutlet UIView *commandBar;
@property (nonatomic, weak) IBOutlet UIView *commandLeftHost;
@property (nonatomic, weak) IBOutlet UIView *commandTitleHost;
@property (nonatomic, weak) IBOutlet UIView *commandRightHost;
@property (nonatomic, weak) IBOutlet UIView *visualizerContainer;
@property (nonatomic, weak) IBOutlet UILabel *visualizerPlaceholder;
@property (nonatomic, weak) IBOutlet UIView *progressBar;
@property (nonatomic, weak) IBOutlet UILabel *ibGuideLabel;
@property (nonatomic, weak) IBOutlet UIView *transportBar;
@property (nonatomic, weak) IBOutlet UIButton *prevButton;
@property (nonatomic, weak) IBOutlet UIButton *rewindButton;
@property (nonatomic, weak) IBOutlet UIButton *playButton;
@property (nonatomic, weak) IBOutlet UIButton *forwardButton;
@property (nonatomic, weak) IBOutlet UIButton *nextButton;
@property (nonatomic, weak) IBOutlet UIView *bottomRow;
@property (nonatomic, weak) IBOutlet UIView *subsongPanel;
@property (nonatomic, weak) IBOutlet UILabel *subsongTitle;
@property (nonatomic, weak) IBOutlet UIView *subsongBody;
@property (nonatomic, weak) IBOutlet UITableView *subsongTable;
@property (nonatomic, weak) IBOutlet UIView *voicesPanel;
@property (nonatomic, weak) IBOutlet UILabel *voicesTitle;
@property (nonatomic, weak) IBOutlet UIView *voicesBody;
@property (nonatomic, weak) IBOutlet UILabel *voicesEmptyLabel;
@property (nonatomic, weak) IBOutlet UIView *eqPanel;
@property (nonatomic, weak) IBOutlet UILabel *eqTitle;
@property (nonatomic, weak) IBOutlet UIView *eqBody;
@property (nonatomic, weak) IBOutlet UISwitch *eqApplySwitch;
@property (nonatomic, weak) IBOutlet UILabel *eqApplyLabel;

+ (instancetype)loadFromNib;
- (void)prepareForRuntime;
- (void)styleTransportButtonsPlaying:(BOOL)playing;
- (void)syncEqualizerFromEngine;

@end
