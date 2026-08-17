//
//  myTabBarController.mm
//  modizer
//
//  Created by Yohann Magnien on 14/06/10.
//  Copyright 2010 __YoyoFR / Yohann Magnien__. All rights reserved.
//

#define DEBUG_SHOW_WELCOME 0

#import "myTabBarController.h"
#import "TTFadeAnimator.h"
#import "MDZFontAwesome.h"

#import "ModizerConstants.h"
#import "ModizerTypes.h"

#import "CarPlayAndRemoteManagement.h"
#import "WelcomeVC.h"
#import "SceneDelegate.h"
#import "StoreManager.h"
#import "ModizerPlaylistBridge.h"
#import "ModizFileHelper.h"
#import "CloudStorageManager.h"
#import "AppDelegate_Phone.h"
#import "MacSidebarLayout.h"
#import "RootViewControllerLocalFolders.h"
#import <objc/runtime.h>

#if TARGET_OS_MACCATALYST
@interface myTabBarController (MDZMacLayout)
- (void)mdzInstallPersistentLibrarySplitIfNeeded;
- (void)mdzHideSidebarNowPlayingButtons;
- (UINavigationController *)mdzStandalonePlayerNavigationController;
- (void)mdzInstallMacSidebarSegmentIfNeeded;
- (void)mdzLayoutMacSidebarSegment;
- (void)mdzApplyMacTabBarHidden;
- (void)mdzApplyMacSidebarNavChrome;
- (void)mdzPinMacSidebarSearchBars;
- (void)mdzEnsureMacSidebarBackButton;
- (void)mdzMacSidebarBackTapped;
- (void)mdzObserveSelectedNavIfNeeded;
- (void)mdzHideSystemTabOverlays;
- (void)mdzHideSystemTabOverlaysInView:(UIView *)view depth:(int)depth;
- (void)mdzDumpTabLikeViews:(UIView *)view depth:(int)depth file:(FILE *)fp;
@end

@interface UINavigationController (MDZMacPlayer)
- (void)mdz_pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
@end
#endif

extern NSMutableArray *mac_key_pressed,*mac_key_released;


@implementation myTabBarController

@synthesize welcomePages;
@synthesize detailViewControllerIphone;
@synthesize playlistVC;
@synthesize rootViewControllerIphone;
@synthesize onlineVC;
@synthesize searchVC;
@synthesize moreVC;
@synthesize webBrowser;
@synthesize downloadVC;
@synthesize aboutVC;

@synthesize animatedLaunchVC;
@synthesize cpMngt;


- (UIViewController *)visibleViewController:(UIViewController *)rootViewController
{
    if ([rootViewController isKindOfClass:[UITabBarController class]])
    {
        UIViewController *selectedViewController = ((UITabBarController *)rootViewController).selectedViewController;

        return [self visibleViewController:selectedViewController];
    }
    if ([rootViewController isKindOfClass:[UINavigationController class]])
    {
        UIViewController *lastViewController = [[((UINavigationController *)rootViewController) viewControllers] lastObject];

        return [self visibleViewController:lastViewController];
    }
    
    if (rootViewController.presentedViewController == nil)
    {
        return rootViewController;
    }
    if ([rootViewController.presentedViewController isKindOfClass:[UINavigationController class]])
    {
        UINavigationController *navigationController = (UINavigationController *)rootViewController.presentedViewController;
        UIViewController *lastViewController = [[navigationController viewControllers] lastObject];

        return [self visibleViewController:lastViewController];
    }
    if ([rootViewController.presentedViewController isKindOfClass:[UITabBarController class]])
    {
        UITabBarController *tabBarController = (UITabBarController *)rootViewController.presentedViewController;
        UIViewController *selectedViewController = tabBarController.selectedViewController;

        return [self visibleViewController:selectedViewController];
    }

    UIViewController *presentedViewController = (UIViewController *)rootViewController.presentedViewController;

    return [self visibleViewController:presentedViewController];
}


- (UIStatusBarStyle)preferredStatusBarStyle {    
    return UIStatusBarStyleDefault;
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    UIViewController *vc=[self visibleViewController:self];
    return vc;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
    //    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.delegate = self;
    
    [self setNeedsStatusBarAppearanceUpdate];
    
    [self.detailViewControllerIphone.view layoutSubviews];
    
    [self showAnimatedLaunchOverlay];
}

- (id)findChildOfClass:(Class)cls {
    for (UIViewController *vc in self.viewControllers) {
        // If embedded in a nav controller, check its root
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *root = ((UINavigationController *)vc).viewControllers.firstObject;
            if ([root isKindOfClass:cls]) {
                return root;
            }
        } else if ([vc isKindOfClass:cls]) {
            return vc;
        }
    }
    return nil;
}

- (SceneDelegate *)currentSceneDelegate {
    UIWindowScene *windowScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
                windowScene = ws;
                break;
        }
    }
    return (SceneDelegate *)windowScene.delegate;
}

- (void)registerVCinAppDelegate {
    AppDelegate_Phone *appDelegate = (AppDelegate_Phone *)[[UIApplication sharedApplication] delegate];
    appDelegate.detailViewControlleriPhone = detailViewControllerIphone;
    appDelegate.rootViewControlleriPhone = rootViewControllerIphone;
    appDelegate.tabBarC = self;
    appDelegate.playlistVC = playlistVC;
    appDelegate.downloadVC = downloadVC;
        
    SceneDelegate *sceneDelegate = [self currentSceneDelegate];
    sceneDelegate.detailViewControlleriPhone = detailViewControllerIphone;
    sceneDelegate.rootViewControlleriPhone = rootViewControllerIphone;
    sceneDelegate.tabBarController = self;
    sceneDelegate.playlistVC = playlistVC;
    sceneDelegate.downloadVC =downloadVC;
}

- (void)goToNextWelcomePage {
    if (welcomePageIndex >= [self.welcomePages count] - 1) {
        // Already on last page
        return;
    }
    welcomePageIndex++;
    [myPVC setViewControllers:@[self.welcomePages[welcomePageIndex]]
                    direction:UIPageViewControllerNavigationDirectionForward
                     animated:YES
                   completion:nil];
}

- (void)goToPreviousWelcomePage {
    if (welcomePageIndex <= 0) {
        // Already on first page
        return;
    }
    welcomePageIndex--;
    [myPVC setViewControllers:@[self.welcomePages[welcomePageIndex]]
                    direction:UIPageViewControllerNavigationDirectionReverse
                     animated:YES
                   completion:nil];
}

- (void)goToWelcomePageAtIndex:(NSInteger)index {
    if (index < 0 || index >= [self.welcomePages count]) {
        return;
    }
    UIPageViewControllerNavigationDirection direction =
        (index > welcomePageIndex) ? UIPageViewControllerNavigationDirectionForward
                                   : UIPageViewControllerNavigationDirectionReverse;
    welcomePageIndex = index;
    [myPVC setViewControllers:@[self.welcomePages[index]]
                    direction:direction
                     animated:YES
                   completion:nil];
}

- (UIImage *)createScanlinePattern:(CGSize)size {
    // Create scanline pattern
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Draw scanlines
    CGFloat scanlineHeight = 1.0; // Height of each scanline
    CGFloat scanlineSpacing = 2.0; // Distance between scanlines
    
    for (CGFloat y = 0; y < size.height; y += scanlineSpacing) {
        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.0 alpha:0.45].CGColor);
        CGContextFillRect(context, CGRectMake(0, y, size.width, scanlineHeight));
    }
    
    UIImage *scanlineImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return scanlineImage;
}

- (void)applyGradientToLabel:(UILabel *)label {
    // Remove any existing gradient layers
    for (CALayer *layer in label.layer.sublayers.copy) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }
    
    // Create gradient layer
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = label.bounds;

#define COL1 0xFF4FB3
#define COL2 0xC44CFF
#define COL3 0x4AA8FF
    
#define RED(x) (((x>>16)&0xFF)/255.0)
#define GREEN(x) (((x>>8)&0xFF)/255.0)
#define BLUE(x) (((x>>0)&0xFF)/255.0)
    // Define gradient colors (adjust these to your preference)
    gradientLayer.colors = @[
        (id)[UIColor colorWithRed:RED(COL1) green:GREEN(COL1) blue:BLUE(COL1) alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:RED(COL2) green:GREEN(COL2) blue:BLUE(COL2) alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:RED(COL3) green:GREEN(COL3) blue:BLUE(COL3) alpha:1.0].CGColor,
    ];

    
    // Set gradient direction (0,0 to 1,0 = left to right, 0,0 to 0,1 = top to bottom)
    gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    
    // Render the gradient into an image
    UIGraphicsBeginImageContextWithOptions(label.bounds.size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Draw gradient
    [gradientLayer renderInContext:context];
    
    // Overlay scanlines
    UIImage *scanlineImage = [self createScanlinePattern:label.bounds.size];
    [scanlineImage drawInRect:CGRectMake(0, 0, label.bounds.size.width, label.bounds.size.height) blendMode:kCGBlendModeMultiply alpha:1.0];
    
    UIImage *finalImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // Apply gradient + scanlines as text color
    label.textColor = [UIColor colorWithPatternImage:finalImage];
}

- (void) setupWelcomePages {
    welcomePage1=[[WelcomeVC alloc] initWithNibName:@"WelcomeView_1Image" bundle:[NSBundle mainBundle]];
    welcomePage2=[[WelcomeVC alloc] initWithNibName:@"WelcomeView_2Images" bundle:[NSBundle mainBundle]];
    welcomePage3=[[WelcomeVC alloc] initWithNibName:@"WelcomeView_4Images" bundle:[NSBundle mainBundle]];
    welcomePage4=[[WelcomeVC alloc] initWithNibName:@"WelcomeView_1Image" bundle:[NSBundle mainBundle]];
    
    [welcomePage1 loadViewIfNeeded];
    [welcomePage2 loadViewIfNeeded];
    [welcomePage3 loadViewIfNeeded];
    [welcomePage4 loadViewIfNeeded];
    
    float HEADER_FONT_SIZE=20;
    //Page 1
    welcomePage1.topLabel.text=NSLocalizedString(
@"Welcome to Modizer!\n",@"");
    welcomePage1.topLabel.font = [UIFont fontWithName:@"Orbitron-Regular" size:HEADER_FONT_SIZE];
    welcomePage1.imageView1.image = [UIImage imageNamed:@"welcome_localBrowser.png"];
    welcomePage1.leftBtn.hidden=true;
    welcomePage1.rightBtn.hidden=false;
    [welcomePage1.rightBtn addTarget:self action:@selector(goToNextWelcomePage) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage1.exitBtn setTitle:NSLocalizedString(@"Skip",@"") forState:UIControlStateNormal];
    welcomePage1.messageLabel.text=NSLocalizedString(@""
"Your gateway to retro and tracker music.\n"
"Power up your device with legendary game tunes, iconic tracker modules, and timeless chiptune classics.",@"");
    welcomePage1.messageLabel.font = [UIFont fontWithName:@"Montserrat-Regular" size:15];
    
    //Page 2
    welcomePage2.topLabel.text=NSLocalizedString(@"Level up your library.",@"");
    welcomePage2.topLabel.font = [UIFont fontWithName:@"Orbitron-Regular" size:HEADER_FONT_SIZE];
    welcomePage2.imageView1.image = [UIImage imageNamed:@"welcome_online.png"];
    welcomePage2.imageView2.image = [UIImage imageNamed:@"welcome_playlist.png"];
    welcomePage2.leftBtn.hidden=false;
    welcomePage2.rightBtn.hidden=false;
    [welcomePage2.leftBtn addTarget:self action:@selector(goToPreviousWelcomePage) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage2.rightBtn addTarget:self action:@selector(goToNextWelcomePage) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage2.exitBtn setTitle:NSLocalizedString(@"Skip",@"") forState:UIControlStateNormal];
    welcomePage2.messageLabel.text=NSLocalizedString(@""
"Browse and stream from online catalogs, to complete your own collections.\nBuild, edit, and listen to playlists effortlessly.",@"");
    welcomePage2.messageLabel.font = [UIFont fontWithName:@"Montserrat-Regular" size:15];
    
    //Page 3
    welcomePage3.topLabel.text=NSLocalizedString(@"Sound meets visuals.",@"");
    welcomePage3.topLabel.font = [UIFont fontWithName:@"Orbitron-Regular" size:HEADER_FONT_SIZE];
    welcomePage3.imageView1.image = [UIImage imageNamed:@"welcome_playerView1.png"];
    welcomePage3.imageView2.image = [UIImage imageNamed:@"welcome_playerView2.png"];
    welcomePage3.imageView3.image = [UIImage imageNamed:@"welcome_playerView3.png"];
    welcomePage3.imageView4.image = [UIImage imageNamed:@"welcome_playerView4.png"];
    welcomePage3.leftBtn.hidden=false;
    welcomePage3.rightBtn.hidden=false;
    [welcomePage3.leftBtn addTarget:self action:@selector(goToPreviousWelcomePage) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage3.rightBtn addTarget:self action:@selector(goToNextWelcomePage) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage3.exitBtn setTitle:NSLocalizedString(@"Skip",@"") forState:UIControlStateNormal];
    welcomePage3.messageLabel.text=NSLocalizedString(@""
"Unlock classic oscilloscope looks, spectrum bars, piano rolls, trackers view and ProjectM/Milkdrop FX. Let Modizer paint each track with motion and color.",@"");
    welcomePage3.messageLabel.font = [UIFont fontWithName:@"Montserrat-Regular" size:15];
    
    //Page 4
    welcomePage4.topLabel.text=NSLocalizedString(@"Made with passion,\noffered for free.",@"");
    welcomePage4.topLabel.font = [UIFont fontWithName:@"Orbitron-Regular" size:HEADER_FONT_SIZE];
    welcomePage4.imageView1.image = [UIImage imageNamed:@"welcome_more.png"];
    welcomePage4.leftBtn.hidden=false;
    welcomePage4.rightBtn.hidden=true;
    [welcomePage4.leftBtn addTarget:self action:@selector(goToPreviousWelcomePage) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage4.exitBtn setTitle:NSLocalizedString(@"Close",@"") forState:UIControlStateNormal];
    welcomePage4.messageLabel.text=NSLocalizedString(@""
"If you enjoy the app, tips are a great way to support its ongoing development.\nThank you for helping keep Modizer alive and evolving.",@"");
    welcomePage4.messageLabel.font = [UIFont fontWithName:@"Montserrat-Regular" size:15];
    
    [welcomePage1.exitBtn addTarget:self action:@selector(exitWelcomePages) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage2.exitBtn addTarget:self action:@selector(exitWelcomePages) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage3.exitBtn addTarget:self action:@selector(exitWelcomePages) forControlEvents:UIControlEventTouchUpInside];
    [welcomePage4.exitBtn addTarget:self action:@selector(exitWelcomePages) forControlEvents:UIControlEventTouchUpInside];
    
    self.welcomePages= @[welcomePage1,welcomePage2,welcomePage3,welcomePage4];
    
    myPVC=[[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:NULL];
    welcomePageIndex=0;
    [myPVC setViewControllers:@[welcomePages[welcomePageIndex]] direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
    
    myPVC.dataSource=self;
    myPVC.delegate=self;
    
    // Apply gradients after layout
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyGradientToLabel:self->welcomePage1.topLabel];
        [self applyGradientToLabel:self->welcomePage2.topLabel];
        [self applyGradientToLabel:self->welcomePage3.topLabel];
        [self applyGradientToLabel:self->welcomePage4.topLabel];
    });
}

- (void)enablePageControlTaps {
    for (UIView *view in myPVC.view.subviews) {
        if ([view isKindOfClass:[UIPageControl class]]) {
            UIPageControl *pageControl = (UIPageControl *)view;
            pageControl.userInteractionEnabled = YES;
            [pageControl addTarget:self action:@selector(pageControlTapped:) forControlEvents:UIControlEventValueChanged];
            break;
        }
    }
}

- (void)pageControlTapped:(UIPageControl *)pageControl {
    NSInteger targetPage = pageControl.currentPage;
    [self goToWelcomePageAtIndex:targetPage];
}


#pragma mark - UIDropInteractionDelegate

- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {
    // Vérifier que la session contient des fichiers audio/musique
    return [session hasItemsConformingToTypeIdentifiers:@[@"public.audio", @"public.data"]];
}

- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction
                   sessionDidUpdate:(id<UIDropSession>)session {
    // Proposer une copie des fichiers
    return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationCopy];
}

- (void)dropInteraction:(UIDropInteraction *)interaction
            performDrop:(id<UIDropSession>)session {
    __block bool first=true;
    for (UIDragItem *item in session.items) {
        // Utiliser loadInPlaceFileRepresentation au lieu de loadFileRepresentationForTypeIdentifier
        [item.itemProvider loadInPlaceFileRepresentationForTypeIdentifier:@"public.data"
                                                        completionHandler:^(NSURL *url, BOOL isInPlace, NSError *error) {
            if (url && !error) {
//                NSLog(@"Fichier à l'emplacement d'origine: %@", url.path);
//                NSLog(@"Est-ce in-place? %@", isInPlace ? @"OUI" : @"NON");
                
                // Démarrer l'accès sécurisé
                BOOL accessGranted = [url startAccessingSecurityScopedResource];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Maintenant url pointe vers ~/Downloads/spc/eotb.rsn
                    [self loadAndPlayFileAtURL:url add_to_playlist:!first];
                    if (first) first=false;
                    
                    // Libérer l'accès
                    if (accessGranted) {
                        [url stopAccessingSecurityScopedResource];
                    }
                });
            } else {
                MDZELog("Erreur: %@", error);
            }
        }];
    }
}

- (void)loadAndPlayFileAtURL:(NSURL *)fileURL add_to_playlist:(bool)add_to_playlist {
    // Ton code de lecture existant, mais avec une NSURL au lieu d'un NSString
    // Par exemple, passer l'URL à tes librairies audio
    //NSLog(@"Lecture du fichier depuis: %@", fileURL.path);
    
    // Adapter ton code de lecture pour utiliser l'URL
    //[self openURL:fileURL];
    
        NSString *shortfilepath=fileURL.path;
    if (!add_to_playlist) {
        t_playlist *pl;
        pl=(t_playlist*)calloc(1,sizeof(t_playlist));
        
        pl->nb_entries=1;
        pl->entries[0].label=[shortfilepath lastPathComponent];
        pl->entries[0].fullpath=shortfilepath;
        pl->entries[0].ratings=-1;
        pl->entries[0].playcounts=0;
        [detailViewControllerIphone play_listmodules:pl start_index:0];
        free(pl);
    } else {
        [detailViewControllerIphone add_to_playlist:shortfilepath fileName:[shortfilepath lastPathComponent] forcenoplay:0];
    }

}

- (void)viewDidLoad {
    START_PROFILE
	[super viewDidLoad];
    self.navigationController.delegate = self;
    
    UIDropInteraction *dropInteraction = [[UIDropInteraction alloc] initWithDelegate:self];
        [self.view addInteraction:dropInteraction];
    
    //self.view.backgroundColor = [UIColor clearColor];
    
    // iOS 15+ Fix: Configure appearance for tab bar and navigation bar
    if (@available(iOS 15.0, *)) {
        // Configure Tab Bar Appearance
        UITabBarAppearance *tabBarAppearance = [[UITabBarAppearance alloc] init];
        [tabBarAppearance configureWithDefaultBackground];
        
        // You can customize colors here if needed:
        // tabBarAppearance.backgroundColor = [UIColor systemBackgroundColor];
        
        self.tabBar.standardAppearance = tabBarAppearance;
        self.tabBar.scrollEdgeAppearance = tabBarAppearance;
        
        // Configure Navigation Bar Appearance for all child navigation controllers
        UINavigationBarAppearance *navBarAppearance = [[UINavigationBarAppearance alloc] init];
        [navBarAppearance configureWithDefaultBackground];
        
        // You can customize colors here if needed:
        // navBarAppearance.backgroundColor = [UIColor systemBackgroundColor];
        
        // Apply to all navigation controllers in tabs
        for (UIViewController *vc in self.viewControllers) {
            if ([vc isKindOfClass:[UINavigationController class]]) {
                UINavigationController *nav = (UINavigationController *)vc;
                nav.navigationBar.standardAppearance = navBarAppearance;
                nav.navigationBar.scrollEdgeAppearance = navBarAppearance;
                nav.navigationBar.compactAppearance = navBarAppearance;
            }
        }
    }
    
    if (@available(iOS 18.0, *)) {
#if TARGET_OS_MACCATALYST
        self.mode = UITabBarControllerModeTabBar;
        [self setTabBarHidden:YES animated:NO];
        self.sidebar.hidden = YES;
#else
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            self.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
        }
        self.mode = UITabBarControllerModeTabSidebar;
#endif
    }
    
    
    // Resolve detailViewControllerIphone
    self.rootViewControllerIphone = [self findChildOfClass:[RootViewControllerLocalBrowser class]];
    self.playlistVC = [self findChildOfClass:[RootViewControllerPlaylist class]];
    self.onlineVC = [self findChildOfClass:[OnlineViewController class]];
    self.searchVC = [self findChildOfClass:[SearchViewController class]];
    self.moreVC = [self findChildOfClass:[MoreViewController class]];
    
    self.detailViewControllerIphone = [self findChildOfClass:[DetailViewControllerIphone class]];
    self.webBrowser = [self findChildOfClass:[WebBrowser class]];
    self.downloadVC = [self findChildOfClass:[DownloadViewController class]];
    self.aboutVC = [self findChildOfClass:[AboutViewController class]];
    
    
    [self.rootViewControllerIphone loadViewIfNeeded];
    [self.playlistVC loadViewIfNeeded];
    [self.onlineVC loadViewIfNeeded];
    [self.searchVC loadViewIfNeeded];
    [self.moreVC loadViewIfNeeded];
    
    [self.detailViewControllerIphone loadViewIfNeeded];
    [self.webBrowser loadViewIfNeeded];
    [self.downloadVC loadViewIfNeeded];
    [self.aboutVC loadViewIfNeeded];
    

    
    // Build a filtered list of tab view controllers by class
    NSArray<Class> *excludedClasses = @[
        // List classes to exclude here, e.g.:
        [DetailViewControllerIphone class],
        [AboutViewController class],
        [DownloadViewController class],
        [WebBrowser class],
        // [MoreViewController class]
    ];
    
    //Initiate storeManager
    [StoreManager sharedManager];
    
    //check if new version
    if (detailViewControllerIphone.not_expected_version) {
        //show Welcome Screen
        settings[GLOB_ShowWelcome].detail.mdz_boolswitch.switch_value=1;
    }
    
    self.downloadVC.barItem=moreVC.navigationController.tabBarItem;
    [self.downloadVC refreshDownloadCountBadge];
    
    NSMutableArray<UIViewController *> *filteredTabs = [NSMutableArray array];
    for (UIViewController *vc in self.viewControllers) {
        BOOL shouldExclude = NO;
        Class candidateClass = [vc class];
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)vc;
            UIViewController *root = nav.viewControllers.firstObject;
            if (root != nil) {
                candidateClass = [root class];
            }
        }
        for (Class cls in excludedClasses) {
            if ([candidateClass isSubclassOfClass:cls]) {
                shouldExclude = YES;
                break;
            }
        }
        if (!shouldExclude) {
            [filteredTabs addObject:vc];
        }
    }
    
    [self setViewControllers:filteredTabs animated:NO];
    [self mdzInstallLocalFoldersTabIfNeeded];
    
    // iOS 15+ Fix: Reapply navigation bar appearance after setting view controllers
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *navBarAppearance = [[UINavigationBarAppearance alloc] init];
        [navBarAppearance configureWithDefaultBackground];
        
        for (UIViewController *vc in filteredTabs) {
            if ([vc isKindOfClass:[UINavigationController class]]) {
                UINavigationController *nav = (UINavigationController *)vc;
                nav.navigationBar.standardAppearance = navBarAppearance;
                nav.navigationBar.scrollEdgeAppearance = navBarAppearance;
                nav.navigationBar.compactAppearance = navBarAppearance;
            }
        }
    }
    
    // Initialize CarPlay management
    self.cpMngt = [[CarPlayAndRemoteManagement alloc] init];
    self.cpMngt.detailViewController = detailViewControllerIphone;
    self.cpMngt.rootVCLocalB = rootViewControllerIphone;
    [self.cpMngt initCarPlayAndRemote];
    
    
    //Register various key VC in App Delegate
    [self registerVCinAppDelegate];

    
    // Configure notifications delegate to detail controller
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = detailViewControllerIphone;
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (!granted) mdzNotificationAllowed=false;
        else mdzNotificationAllowed=true;
    }];
    
    
    UIWindowScene *windowScene;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            windowScene = (UIWindowScene*) scene;
            break;
        }
    }
    
    [self setupWelcomePages];
    
#if TARGET_OS_MACCATALYST

    // Set navigation controller delegates to handle pushed view controllers
    for (UIViewController *vc in self.viewControllers) {
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)vc;
            nav.delegate = self;
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self mdzInstallPersistentLibrarySplitIfNeeded];
    });
#endif

//    if (@available(iOS 15.0, *)) {
//        UITabBarAppearance *appearance = [UITabBarAppearance new];
//        [appearance configureWithDefaultBackground];
//        self.tabBar.standardAppearance = appearance;
//        self.tabBar.scrollEdgeAppearance = appearance;
//    }
    END_PROFILE
}

- (void)mdzInstallLocalFoldersTabIfNeeded {
    for (UIViewController *vc in self.viewControllers) {
        UIViewController *root = vc;
        if ([vc isKindOfClass:[UINavigationController class]]) {
            root = ((UINavigationController *)vc).viewControllers.firstObject;
        }
        if ([root isKindOfClass:[RootViewControllerLocalFolders class]]) {
            RootViewControllerLocalFolders *folders = (RootViewControllerLocalFolders *)root;
            if (!folders.detailViewController) {
                folders.detailViewController = self.detailViewControllerIphone;
            }
            return;
        }
    }
    RootViewControllerLocalFolders *foldersVC = [[RootViewControllerLocalFolders alloc] init];
    foldersVC.detailViewController = self.detailViewControllerIphone;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:foldersVC];
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Local", @"")
                                                   image:[UIImage systemImageNamed:@"folder.badge.plus"]
                                                     tag:0];
    NSMutableArray *tabs = [self.viewControllers mutableCopy] ?: [NSMutableArray array];
    NSUInteger insertAt = tabs.count > 0 ? 1 : 0;
    if (insertAt > tabs.count) {
        insertAt = tabs.count;
    }
    [tabs insertObject:nav atIndex:insertAt];
    [self setViewControllers:tabs animated:NO];
}


- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    bool is_macOS=false;
    if ([NSProcessInfo processInfo].isiOSAppOnMac) {
        is_macOS=true;
    }
#if TARGET_OS_MACCATALYST
    is_macOS=true;
#endif
    if (is_macOS) {
#if TARGET_OS_MACCATALYST
        if (self.catalystSplitViewController) {
            [self mdzApplyMacTabBarHidden];
            [self mdzLayoutMacSidebarSegment];
            return;
        }
#endif
        // Continuously enforce tab bar at zero frame during all layout passes
        self.tabBar.hidden = YES;
        self.tabBar.frame = CGRectZero;
    }
}


#if TARGET_OS_MACCATALYST
- (UINavigationController *)mdzDetailNavigationController {
    UIViewController *selected = self.selectedViewController;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        return (UINavigationController *)selected;
    }
    if (self.viewControllers.count > 0 && [self.viewControllers.firstObject isKindOfClass:[UINavigationController class]]) {
        self.selectedIndex = 0;
        return (UINavigationController *)self.viewControllers.firstObject;
    }
    return nil;
}

- (BOOL)mdzShowPlayerOnDetailSide {
    // Player lives in the split secondary column; never push it onto the sidebar.
    return (self.catalystSplitViewController != nil);
}

- (UINavigationController *)mdzStandalonePlayerNavigationController {
    if (!detailViewControllerIphone) {
        return nil;
    }
    UINavigationController *nav = detailViewControllerIphone.navigationController;
    if (nav && ![self.viewControllers containsObject:nav] && nav.viewControllers.firstObject == detailViewControllerIphone) {
        nav.navigationBarHidden = YES;
        return nav;
    }
    if (detailViewControllerIphone.parentViewController) {
        UINavigationController *oldNav = detailViewControllerIphone.navigationController;
        if (oldNav) {
            NSMutableArray *stack = [oldNav.viewControllers mutableCopy];
            [stack removeObject:detailViewControllerIphone];
            oldNav.viewControllers = stack ?: @[];
        } else {
            [detailViewControllerIphone willMoveToParentViewController:nil];
            [detailViewControllerIphone.view removeFromSuperview];
            [detailViewControllerIphone removeFromParentViewController];
        }
    }
    nav = [[UINavigationController alloc] initWithRootViewController:detailViewControllerIphone];
    nav.navigationBar.prefersLargeTitles = NO;
    nav.navigationBarHidden = YES;
    return nav;
}

- (void)mdzApplyMacTabBarHidden {
    if (@available(iOS 18.0, *)) {
        if (!self.tabBarHidden) {
            [self setTabBarHidden:YES animated:NO];
        }
        self.sidebar.hidden = YES;
    }
    self.tabBar.hidden = YES;
    self.tabBar.alpha = 0;
    self.tabBar.userInteractionEnabled = NO;
}

- (void)mdzDumpTabLikeViews:(UIView *)view depth:(int)depth file:(FILE *)fp {
    if (!view || depth > 24 || !fp) {
        return;
    }
    NSString *cls = NSStringFromClass(view.class);
    if ([cls.lowercaseString containsString:@"tab"] || [cls containsString:@"Platter"] || [cls containsString:@"Segment"] || [cls containsString:@"Floating"]) {
        fprintf(fp, "%*s%s frame=%.0f,%.0f %.0fx%.0f hidden=%d\n", depth * 2, "", cls.UTF8String,
                view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height, view.hidden);
    }
    for (UIView *sub in view.subviews) {
        [self mdzDumpTabLikeViews:sub depth:depth + 1 file:fp];
    }
}

- (void)mdzHideSystemTabOverlays {
    [self mdzApplyMacTabBarHidden];
    FILE *fp = fopen("/tmp/mdz_tab_views.txt", "w");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        fprintf(fp ?: stdout, "windows=%lu\n", (unsigned long)windowScene.windows.count);
        for (UIWindow *window in windowScene.windows) {
            if (fp) {
                fprintf(fp, "WINDOW %s frame=%.0f,%.0f %.0fx%.0f hidden=%d\n",
                        NSStringFromClass(window.class).UTF8String,
                        window.frame.origin.x, window.frame.origin.y, window.frame.size.width, window.frame.size.height, window.hidden);
                [self mdzDumpTabLikeViews:window depth:1 file:fp];
            }
            [self mdzHideSystemTabOverlaysInView:window];
        }
    }
    if (fp) {
        fclose(fp);
    }
}

- (void)mdzHideSystemTabOverlaysInView:(UIView *)view {
    [self mdzHideSystemTabOverlaysInView:view depth:0];
}

- (void)mdzHideSystemTabOverlaysInView:(UIView *)view depth:(int)depth {
    if (!view || depth > 24) {
        return;
    }
    NSString *cls = NSStringFromClass(view.class);
    BOOL hide = NO;
    if ([view isKindOfClass:[UITabBar class]]) {
        hide = YES;
    } else if ([cls containsString:@"BottomTabBarGroup"] ||
               [cls containsString:@"TabBarPlatter"] ||
               [cls containsString:@"_UITabBarAuxiliary"] ||
               [cls containsString:@"VisualProvider_Floating"] ||
               [cls containsString:@"_UITabBarVisualProvider"]) {
        hide = YES;
    }
    if (hide) {
        view.hidden = YES;
        view.alpha = 0;
    }
    for (UIView *sub in [view.subviews copy]) {
        [self mdzHideSystemTabOverlaysInView:sub depth:depth + 1];
    }
}

- (void)mdzInstallMacSidebarSegmentIfNeeded {
    if (self.macSidebarLayout && self.macSidebarSegment) {
        [self mdzLayoutMacSidebarSegment];
        return;
    }
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (UIViewController *vc in self.viewControllers) {
        NSString *title = vc.tabBarItem.title;
        if (title.length == 0) {
            title = vc.title ?: @"•";
        }
        [titles addObject:title];
    }
    if (titles.count == 0) {
        return;
    }
    MacSidebarLayout *layout = [MacSidebarLayout loadFromNib];
    if (!layout) {
        return;
    }
    self.macSidebarLayout = layout;
    UISegmentedControl *segment = layout.tabSegment;
    if (!segment) {
        segment = [[UISegmentedControl alloc] initWithItems:titles];
        UIView *host = layout.tabHost ?: layout;
        segment.frame = host.bounds;
        segment.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:segment];
    } else {
        [segment removeAllSegments];
        for (NSUInteger i = 0; i < titles.count; i++) {
            [segment insertSegmentWithTitle:titles[i] atIndex:i animated:NO];
        }
    }
    segment.selectedSegmentIndex = (NSInteger)self.selectedIndex;
    segment.apportionsSegmentWidthsByContent = NO;
    [segment addTarget:self action:@selector(mdzSidebarSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.macSidebarSegment = segment;
    [layout styleTabSegment];
    [self.view addSubview:layout];
    [layout prepareForRuntime];
    [self mdzLayoutMacSidebarSegment];
}

- (void)mdzApplyMacSidebarNavChrome {
    for (UIViewController *vc in self.viewControllers) {
        if (![vc isKindOfClass:[UINavigationController class]]) {
            continue;
        }
        UINavigationController *nav = (UINavigationController *)vc;
        nav.navigationBar.prefersLargeTitles = NO;
        nav.interactivePopGestureRecognizer.enabled = YES;
        for (UIViewController *child in nav.viewControllers) {
            child.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
            child.navigationItem.hidesBackButton = YES;
            child.navigationItem.leftBarButtonItem = nil;
        }
        if (!nav.navigationBarHidden) {
            [nav setNavigationBarHidden:YES animated:NO];
        }
    }
}

- (void)mdzMacSidebarBackTapped {
    UIViewController *selected = self.selectedViewController;
    if (![selected isKindOfClass:[UINavigationController class]]) {
        return;
    }
    UINavigationController *nav = (UINavigationController *)selected;
    if (nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
    }
}

- (void)mdzObserveSelectedNavIfNeeded {
    UIViewController *selected = self.selectedViewController;
    UINavigationController *nav = nil;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        nav = (UINavigationController *)selected;
    }
    if (self.macObservedNav == nav) {
        return;
    }
    if (self.macObservedNav) {
        @try {
            [self.macObservedNav removeObserver:self forKeyPath:@"viewControllers"];
        } @catch (__unused NSException *ex) {
        }
        self.macObservedNav = nil;
    }
    if (!nav) {
        return;
    }
    self.macObservedNav = nav;
    [nav addObserver:self forKeyPath:@"viewControllers" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"viewControllers"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self mdzPinMacSidebarSearchBars];
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)mdzEnsureMacSidebarBackButton {
    if (self.macSidebarBackButton) {
        return;
    }
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    if (@available(iOS 15.0, *)) {
        btn.configuration = nil;
    }
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                      weight:UIImageSymbolWeightSemibold
                                                                                       scale:UIImageSymbolScaleMedium];
    UIImage *img = [UIImage systemImageNamed:@"chevron.backward" withConfiguration:cfg];
    [btn setImage:img forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    btn.layer.cornerRadius = 10.0;
    btn.clipsToBounds = YES;
    btn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    btn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    btn.contentEdgeInsets = UIEdgeInsetsZero;
    btn.imageEdgeInsets = UIEdgeInsetsMake(1.0, -1.0, -1.0, 1.0);
    btn.adjustsImageWhenHighlighted = NO;
    btn.accessibilityLabel = NSLocalizedString(@"Back", @"");
    [btn addTarget:self action:@selector(mdzMacSidebarBackTapped) forControlEvents:UIControlEventTouchUpInside];
    self.macSidebarBackButton = btn;
}

- (void)mdzPinMacSidebarSearchBars {
    [self mdzObserveSelectedNavIfNeeded];
    UIViewController *selected = self.selectedViewController;
    UINavigationController *nav = nil;
    if ([selected isKindOfClass:[UINavigationController class]]) {
        nav = (UINavigationController *)selected;
        selected = nav.topViewController;
    }
    BOOL canPop = (nav && nav.viewControllers.count > 1);
    [self mdzEnsureMacSidebarBackButton];
    UIButton *back = self.macSidebarBackButton;
    UIView *host = selected.view;
    if (!host) {
        back.hidden = YES;
        return;
    }
    if (back.superview != host) {
        [host addSubview:back];
    }
    back.hidden = !canPop;
    CGFloat top = host.safeAreaInsets.top;
    CGFloat width = CGRectGetWidth(host.bounds);
    CGFloat searchH = 44.0;
    CGFloat leading = canPop ? 52.0 : 0.0;
    UISearchBar *barToAlign = nil;
    for (UIView *sub in host.subviews) {
        if (![sub isKindOfClass:[UISearchBar class]]) {
            continue;
        }
        UISearchBar *bar = (UISearchBar *)sub;
        if (bar.superview != host) {
            continue;
        }
        if (bar.hidden || CGRectGetHeight(bar.frame) < 1.0) {
            continue;
        }
        bar.frame = CGRectMake(leading, top, MAX(44.0, width - leading), searchH);
        if (!barToAlign) {
            barToAlign = bar;
        }
    }
    if (canPop && barToAlign) {
        [barToAlign layoutIfNeeded];
        UIView *field = barToAlign.searchTextField;
        CGRect fieldR = [field convertRect:field.bounds toView:host];
        CGFloat side = CGRectGetHeight(fieldR);
        CGFloat by = fieldR.origin.y;
        if (side < 28.0 || CGRectIsEmpty(fieldR) || !field) {
            side = 36.0;
            by = top + (searchH - side) / 2.0;
        } else if (side > 40.0) {
            by += (side - 36.0) / 2.0;
            side = 36.0;
        }
        back.frame = CGRectMake(8.0, by, side, side);
        back.layer.cornerRadius = MIN(10.0, side / 2.0);
        [host bringSubviewToFront:back];
    }
}

- (void)mdzLayoutMacSidebarSegment {
    if (!self.macSidebarLayout) {
        [self mdzInstallMacSidebarSegmentIfNeeded];
        if (!self.macSidebarLayout) {
            return;
        }
    }
    [self mdzApplyMacTabBarHidden];
    [self mdzApplyMacSidebarNavChrome];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (width < 8.0) {
        return;
    }
    MacSidebarLayout *layout = self.macSidebarLayout;
    CGFloat barH = MDZ_MAC_SIDEBAR_BAR_HEIGHT;
    CGFloat sysTop = self.view.safeAreaInsets.top - self.additionalSafeAreaInsets.top;
    if (sysTop < 0.0) {
        sysTop = 0.0;
    }
    CGFloat titleTop = MAX(sysTop, MDZ_MAC_TITLEBAR_HEIGHT);
    layout.frame = CGRectMake(0, titleTop, width, barH);
    layout.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
    layout.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    CGFloat padX = 16.0;
    CGFloat padY = (barH - MDZ_MAC_SIDEBAR_SEGMENT_HEIGHT) / 2.0;
    if (layout.tabHost) {
        layout.tabHost.frame = CGRectMake(padX, padY, MAX(8.0, width - padX * 2.0), MDZ_MAC_SIDEBAR_SEGMENT_HEIGHT);
    }
    if (self.macSidebarSegment && layout.tabHost) {
        self.macSidebarSegment.frame = layout.tabHost.bounds;
    }
    [layout styleTabSegment];
    CGFloat neededTop = (titleTop - sysTop) + barH;
    if (fabs(self.additionalSafeAreaInsets.top - neededTop) > 0.5) {
        self.additionalSafeAreaInsets = UIEdgeInsetsMake(neededTop, 0, 0, 0);
    }
    [self mdzPinMacSidebarSearchBars];
    [self.view bringSubviewToFront:layout];
}

- (void)mdzSidebarSegmentChanged:(UISegmentedControl *)sender {
    NSInteger idx = sender.selectedSegmentIndex;
    if (idx >= 0 && idx < (NSInteger)self.viewControllers.count) {
        self.selectedIndex = (NSUInteger)idx;
        [self mdzPinMacSidebarSearchBars];
    }
}

- (void)mdzHideSidebarNowPlayingButtons {
    for (UIViewController *vc in self.viewControllers) {
        if (![vc isKindOfClass:[UINavigationController class]]) {
            continue;
        }
        UINavigationController *nav = (UINavigationController *)vc;
        for (UIViewController *child in nav.viewControllers) {
            child.navigationItem.rightBarButtonItem = nil;
        }
    }
}

- (void)mdzInstallPersistentLibrarySplitIfNeeded {
    if (self.catalystSplitViewController) {
        return;
    }
    UIWindow *window = self.view.window;
    if (!window) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.windows.firstObject) {
                window = windowScene.windows.firstObject;
                break;
            }
        }
    }
    if (!window || !rootViewControllerIphone) {
        return;
    }

    UISplitViewController *split = nil;
    if (@available(iOS 14.0, *)) {
        split = [[UISplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
        split.preferredSplitBehavior = UISplitViewControllerSplitBehaviorTile;
        split.displayModeButtonVisibility = UISplitViewControllerDisplayModeButtonVisibilityNever;
        split.primaryBackgroundStyle = UISplitViewControllerBackgroundStyleNone;
    } else {
        split = [[UISplitViewController alloc] init];
    }
    self.catalystSplitViewController = split;
    split.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    split.presentsWithGesture = NO;
    split.preferredPrimaryColumnWidth = MDZ_MAC_LIBRARY_COLUMN_WIDTH;
    split.minimumPrimaryColumnWidth = MDZ_MAC_LIBRARY_COLUMN_MIN;
    split.maximumPrimaryColumnWidth = MDZ_MAC_LIBRARY_COLUMN_MAX;
    split.delegate = self;

    // Keep Library/Playlists/Online/Search/More together in the left column.
    // A custom segmented control sits at the top of that column; hide the
    // system tab bar so iOS 18 does not draw it across the player.
    if (@available(iOS 18.0, *)) {
        self.mode = UITabBarControllerModeTabBar;
        [self setTabBarHidden:YES animated:NO];
        self.sidebar.hidden = YES;
    }
    [self mdzApplyMacTabBarHidden];

    UINavigationController *playerNav = [self mdzStandalonePlayerNavigationController];
    [detailViewControllerIphone loadViewIfNeeded];
    [self mdzHideSidebarNowPlayingButtons];

    if (@available(iOS 14.0, *)) {
        [split setViewController:self forColumn:UISplitViewControllerColumnPrimary];
        if (playerNav) {
            [split setViewController:playerNav forColumn:UISplitViewControllerColumnSecondary];
        }
    } else {
        split.viewControllers = playerNav ? @[self, playerNav] : @[self];
    }
    window.rootViewController = split;
    [self mdzInstallMacSidebarSegmentIfNeeded];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self mdzHideSystemTabOverlays];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self mdzHideSystemTabOverlays];
    });
    [detailViewControllerIphone.view setNeedsLayout];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [UINavigationController class];
        Method original = class_getInstanceMethod(cls, @selector(pushViewController:animated:));
        Method swizzled = class_getInstanceMethod(cls, @selector(mdz_pushViewController:animated:));
        if (original && swizzled) {
            method_exchangeImplementations(original, swizzled);
        }
    });
}

- (UISplitViewControllerDisplayMode)targetDisplayModeForActionInSplitViewController:(UISplitViewController *)svc {
    return UISplitViewControllerDisplayModeOneBesideSecondary;
}

- (BOOL)splitViewController:(UISplitViewController *)splitViewController
collapseSecondaryViewController:(UIViewController *)secondaryViewController
ontoPrimaryViewController:(UIViewController *)primaryViewController {
    return NO;
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    [super setSelectedViewController:selectedViewController];

    if (self.catalystSplitViewController) {
        [self mdzApplyMacTabBarHidden];
        if (self.macSidebarSegment) {
            NSInteger idx = [self.viewControllers indexOfObject:selectedViewController];
            if (idx != NSNotFound && self.macSidebarSegment.selectedSegmentIndex != idx) {
                self.macSidebarSegment.selectedSegmentIndex = idx;
            }
        }
        return;
    }
    self.tabBar.hidden = YES;
    self.tabBar.frame = CGRectZero;
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];

    if (self.catalystSplitViewController) {
        [self mdzApplyMacTabBarHidden];
        if (self.macSidebarSegment &&
            selectedIndex < (NSUInteger)self.macSidebarSegment.numberOfSegments &&
            self.macSidebarSegment.selectedSegmentIndex != (NSInteger)selectedIndex) {
            self.macSidebarSegment.selectedSegmentIndex = (NSInteger)selectedIndex;
        }
        return;
    }
    self.tabBar.hidden = YES;
    self.tabBar.frame = CGRectZero;
}
#endif

- (void)presentWelcomePages {
    if (!DEBUG_SHOW_WELCOME && (settings[GLOB_ShowWelcome].detail.mdz_boolswitch.switch_value==0)) {
        if (settings[GLOB_ShowWelcome].detail.mdz_boolswitch.switch_value==0) {
            [self.rootViewControllerIphone createEditableCopyOfDatabaseIfNeeded:FALSE quiet:0];
        }
        return;
    }
    
    // Don't present if already presenting or presented
    if (myPVC.presentingViewController != nil || myPVC.isBeingPresented) {
        return;
    }
    
    if (myPVC) {
        [self presentViewController:myPVC animated:NO completion:^{
            // Enable page control taps after presentation
            [self enablePageControlTaps];
        }];
        //only show it once
        settings[GLOB_ShowWelcome].detail.mdz_boolswitch.switch_value=0;
    }
}

- (void)exitWelcomePages {
    [myPVC dismissViewControllerAnimated:true completion:^{
        [self.rootViewControllerIphone createEditableCopyOfDatabaseIfNeeded:FALSE quiet:0];
    }];
}

- (nullable UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController {
    WelcomeVC *last_item=NULL;
    for (WelcomeVC *item in self.welcomePages) {
        if (item==viewController) {
            break;
        }
        last_item=item;
    }
    return last_item;
}
- (nullable UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController {
    WelcomeVC *last_item=NULL;
    WelcomeVC *next_item=NULL;
    for (WelcomeVC *item in self.welcomePages) {
        if (last_item==viewController) {
            next_item=item;
            break;
        }
        last_item=item;
    }
    return next_item;
}

- (NSInteger)presentationCountForPageViewController:(UIPageViewController *)pageViewController {
    // The number of items reflected in the page indicator.
    return 4;
}

- (NSInteger)presentationIndexForPageViewController:(UIPageViewController *)pageViewController {
    // The selected item reflected in the page indicator.
    return welcomePageIndex;
}

- (void)pageViewController:(UIPageViewController *)pageViewController 
        didFinishAnimating:(BOOL)finished 
   previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers 
       transitionCompleted:(BOOL)completed {
    
    if (completed) {
        UIViewController *currentVC = pageViewController.viewControllers.firstObject;
        welcomePageIndex = [self.welcomePages indexOfObject:currentVC];
    }
}

- (void)showAnimatedLaunchOverlay {
    if (self.animatedLaunchVC != nil) { return; }

    AnimatedLaunchVC *vc = [[AnimatedLaunchVC alloc] initWithNibName:@"AnimatedLaunch" bundle:[NSBundle mainBundle]];
    vc.localBrowserVC = self.rootViewControllerIphone;
    vc.tabVC = self;
    
    // Load the view first
    [vc loadViewIfNeeded];
    
    // Forward appearance to child
    [vc beginAppearanceTransition:YES animated:NO];

    // Try adding to window for guaranteed top-level display
    UIWindow *window = self.view.window;
    if (window) {
        vc.view.frame = window.bounds;
        vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vc.view.alpha = 1.0;
        
        [window addSubview:vc.view];
    } else {
        // Fallback to self.view if window not available yet
        vc.view.frame = self.view.bounds;
        vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vc.view.alpha = 1.0;
        [self.view addSubview:vc.view];
        [self.view bringSubviewToFront:vc.view];
    }

    // Finish forwarding
    [vc endAppearanceTransition];

    [vc didMoveToParentViewController:self];

    self.animatedLaunchVC = vc;
}
//- (void)hideAnimatedLaunchOverlay {
//    if (!self.animatedLaunchVC) { return; }
//
//    [self.animatedLaunchVC willMoveToParentViewController:nil];
//
//    // Forward disappearance to child
//    [self.animatedLaunchVC beginAppearanceTransition:NO animated:YES];
//
//    [UIView animateWithDuration:0.3 animations:^{
//        self.animatedLaunchVC.view.alpha = 0.0;
//    } completion:^(BOOL finished) {
//        [self.animatedLaunchVC.view removeFromSuperview];
//        
//        // Finish forwarding
//        [self.animatedLaunchVC endAppearanceTransition];
//        
//        [self.animatedLaunchVC removeFromParentViewController];
//        self.animatedLaunchVC = nil;
//    }];
//}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
#if TARGET_OS_MACCATALYST
    [self mdzInstallPersistentLibrarySplitIfNeeded];
#endif
    
    static bool firstcall=true;
    
    if (firstcall) {
        firstcall=false;
        
        // Force layout of all visible views first
        [self.view layoutIfNeeded];
        
        // Let the table views fully load their data
        if ([self.selectedViewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)self.selectedViewController;
            [nav.topViewController.view layoutIfNeeded];
        } else {
            [self.selectedViewController.view layoutIfNeeded];
        }
        
        //[self showAnimatedLaunchOverlay];
    }
}

-(void) openURL:(NSURL *)url {
    // Handle custom modizer:// scheme for Shortcuts
    if ([[url scheme] isEqualToString:@"modizer"]) {
        NSString *host = [url host];
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSMutableDictionary *params = [NSMutableDictionary dictionary];

        for (NSURLQueryItem *item in components.queryItems) {
            params[item.name] = item.value;
        }

        // Check for fromShortcut flag and set it IMMEDIATELY
        if ([params[@"fromShortcut"] isEqualToString:@"true"]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"LaunchedFromShortcut"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            MDZILog("URL launched from Shortcut - flag set");
        }

        // Handle different URL commands using ModizerPlaylistBridge
        if ([host isEqualToString:@"playPlaylist"]) {
            NSString *playlistId = params[@"id"];
            int startIndex = [params[@"index"] intValue];

            if (playlistId) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[ModizerPlaylistBridge sharedInstance] playPlaylistWithId:[playlistId intValue] startIndex:startIndex];
                });
            }
            return;
        }
        else if ([host isEqualToString:@"playPlaylistByName"]) {
            NSString *name = params[@"name"];
            int startIndex = [params[@"index"] intValue];

            if (name) {
                // Decode URL-encoded name
                NSString *decodedName = [name stringByRemovingPercentEncoding];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[ModizerPlaylistBridge sharedInstance] playPlaylistWithName:decodedName startIndex:startIndex];
                });
            }
            return;
        }
        else if ([host isEqualToString:@"playBuiltin"]) {
            int playlistId = [params[@"id"] intValue];

            dispatch_async(dispatch_get_main_queue(), ^{
                [[ModizerPlaylistBridge sharedInstance] playBuiltinPlaylistWithId:playlistId startIndex:0];
            });
            return;
        }
    }

    if ([url isFileURL]) {
        NSString *filepath;
        filepath=[url path];
        
        NSString *imported_filepath;
        NSError *err;
        NSFileManager *mFileMngr=[[NSFileManager alloc] init];

        [mFileMngr createDirectoryAtPath:[[ModizFileHelper getAppHomeDirectory] stringByAppendingPathComponent:@"Documents/Downloads"] withIntermediateDirectories:true attributes:NULL error:NULL];

        imported_filepath=[NSString stringWithFormat:@"%@/%@",[[ModizFileHelper getAppHomeDirectory] stringByAppendingPathComponent:@"Documents/Downloads"],[filepath lastPathComponent]];
        //////////////////
        ///Get access
        // Check if this is a cloud source path
        CloudStorageSource *cloudSource = [[CloudStorageManager sharedManager] sourceForPath:filepath];
        BOOL accessGranted = NO;

        if (cloudSource) {
            // Use CloudStorageManager for cloud sources
            accessGranted = [[CloudStorageManager sharedManager] startAccessingSource:cloudSource];
        } else {
            // Legacy security-scoped access
            accessGranted = [url startAccessingSecurityScopedResource];
        }

        if (accessGranted) {
            ////////////////////
            //Download from cloud if required (iCloud, Google Drive, Dropbox, etc.)

            // Check if file needs to be downloaded using CloudStorageManager
            if (![[CloudStorageManager sharedManager] isFileDownloaded:url]) {
                // File is not downloaded locally - trigger download
                NSError *downloadError = nil;
                BOOL downloadStarted = [[CloudStorageManager sharedManager] startDownloadingFile:url error:&downloadError];

                NSString *message;
                if (downloadStarted) {
                    message = NSLocalizedString(@"File is not available locally.\nDownload has been triggered, please check in 'Files' application.",@"");
                } else {
                    message = NSLocalizedString(@"File is not available locally and cannot be downloaded.\nPlease check your internet connection and try again.",@"");
                }

                UIAlertController *alertDownloading = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Warning",@"")
                                                                                          message:message
                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleCancel
                                                                    handler:^(UIAlertAction * action) {
                }];
                [alertDownloading addAction:closeAction];
                [self presentViewController:alertDownloading animated:YES completion:nil];

                // Stop accessing and return - don't try to play a file that isn't downloaded
                if (cloudSource) {
                    [[CloudStorageManager sharedManager] stopAccessingSource:cloudSource];
                } else {
                    [url stopAccessingSecurityScopedResource];
                }
                return;
            }

#if TARGET_OS_MACCATALYST
#else
            if ([mFileMngr copyItemAtPath:filepath toPath:imported_filepath error:&err]) {
                [rootViewControllerIphone refreshViewAfterDownload];
            } else {
            }
#endif
            // Stop accessing
            if (cloudSource) {
                [[CloudStorageManager sharedManager] stopAccessingSource:cloudSource];
            } else {
                [url stopAccessingSecurityScopedResource];
            }
        } else  {
        }
#if TARGET_OS_MACCATALYST
        NSString *shortfilepath=filepath;
#else
        NSString *shortfilepath=imported_filepath=[NSString stringWithFormat:@"Documents/Downloads/%@",[filepath lastPathComponent]];
#endif
        t_playlist *pl;
        pl=(t_playlist*)calloc(1,sizeof(t_playlist));
        
        pl->nb_entries=1;
        pl->entries[0].label=[shortfilepath lastPathComponent];
        pl->entries[0].fullpath=shortfilepath;
        pl->entries[0].ratings=-1;
        pl->entries[0].playcounts=0;
        [detailViewControllerIphone play_listmodules:pl start_index:0];
        free(pl);
    }
}

#pragma mark - Key Commands

- (NSArray *)keyCommands
{
    UIKeyCommand *tabCommand = [UIKeyCommand keyCommandWithInput:@"\t"  modifierFlags:0 action:@selector(keyTabPressed)];
    if (@available(iOS 15.0, *)) {
        tabCommand.wantsPriorityOverSystemBehavior = YES;
    }
    
    UIKeyCommand *leftCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow modifierFlags:0 action:@selector(leftPressed)];
    if (@available(iOS 15.0, *)) {
        leftCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *rightCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow modifierFlags:0 action:@selector(rightPressed)];
    if (@available(iOS 15.0, *)) {
        rightCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *leftShiftCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow modifierFlags:UIKeyModifierShift action:@selector(leftShiftPressed)];
    if (@available(iOS 15.0, *)) {
        leftCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *rightShiftCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow modifierFlags:UIKeyModifierShift action:@selector(rightShiftPressed)];
    if (@available(iOS 15.0, *)) {
        rightCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *leftAltCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow modifierFlags:UIKeyModifierAlternate action:@selector(leftAltPressed)];
    if (@available(iOS 15.0, *)) {
        leftAltCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *rightAltCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow modifierFlags:UIKeyModifierAlternate action:@selector(rightAltPressed)];
    if (@available(iOS 15.0, *)) {
        rightAltCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *leftCmdCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow modifierFlags:UIKeyModifierCommand action:@selector(leftCmdPressed)];
    if (@available(iOS 15.0, *)) {
        leftCmdCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *rightCmdCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow modifierFlags:UIKeyModifierCommand action:@selector(rightCmdPressed)];
    if (@available(iOS 15.0, *)) {
        rightCmdCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *upCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow modifierFlags:0 action:@selector(upPressed)];
    if (@available(iOS 15.0, *)) {
        upCommand.wantsPriorityOverSystemBehavior = YES;
    }
    UIKeyCommand *downCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow modifierFlags:0 action:@selector(downPressed)];
    if (@available(iOS 15.0, *)) {
        downCommand.wantsPriorityOverSystemBehavior = YES;
    }

    return @[leftCommand,rightCommand,leftShiftCommand,rightShiftCommand,leftAltCommand,rightAltCommand,leftCmdCommand,rightCmdCommand,upCommand,downCommand,
//                [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow  modifierFlags:0 action:@selector(leftPressed)],
//              [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow   modifierFlags:0 action:@selector(rightPressed)],
//              [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow   modifierFlags:UIKeyModifierAlternate action:@selector(leftAltPressed)],
//              [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow   modifierFlags:UIKeyModifierAlternate action:@selector(rightAltPressed)],
//              [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow   modifierFlags:UIKeyModifierCommand action:@selector(leftCmdPressed)],
//              [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow   modifierFlags:UIKeyModifierCommand action:@selector(rightCmdPressed)],
//              [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow   modifierFlags:0 action:@selector(upPressed)],
//              [UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow   modifierFlags:0 action:@selector(downPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"1"   modifierFlags:0 action:@selector(key1Pressed)],
              [UIKeyCommand keyCommandWithInput:@"&"   modifierFlags:0 action:@selector(key1Pressed)],
              [UIKeyCommand keyCommandWithInput:@"1"   modifierFlags:UIKeyModifierAlternate action:@selector(key1AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"&"   modifierFlags:UIKeyModifierAlternate action:@selector(key1AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"2"   modifierFlags:0 action:@selector(key2Pressed)],
              [UIKeyCommand keyCommandWithInput:@"é"   modifierFlags:0 action:@selector(key2Pressed)],
              [UIKeyCommand keyCommandWithInput:@"2"   modifierFlags:UIKeyModifierAlternate action:@selector(key2AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"é"   modifierFlags:UIKeyModifierAlternate action:@selector(key2AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"3"   modifierFlags:0 action:@selector(key3Pressed)],
              [UIKeyCommand keyCommandWithInput:@"\""   modifierFlags:0 action:@selector(key3Pressed)],
              [UIKeyCommand keyCommandWithInput:@"3"   modifierFlags:UIKeyModifierAlternate action:@selector(key3AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"\""   modifierFlags:UIKeyModifierAlternate action:@selector(key3AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"4"   modifierFlags:0 action:@selector(key4Pressed)],
              [UIKeyCommand keyCommandWithInput:@"'"   modifierFlags:0 action:@selector(key4Pressed)],
              [UIKeyCommand keyCommandWithInput:@"4"   modifierFlags:UIKeyModifierAlternate action:@selector(key4AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"'"   modifierFlags:UIKeyModifierAlternate action:@selector(key4AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"5"   modifierFlags:0 action:@selector(key5Pressed)],
              [UIKeyCommand keyCommandWithInput:@"("   modifierFlags:0 action:@selector(key5Pressed)],
              [UIKeyCommand keyCommandWithInput:@"5"   modifierFlags:UIKeyModifierAlternate action:@selector(key5AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"("   modifierFlags:UIKeyModifierAlternate action:@selector(key5AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"6"   modifierFlags:0 action:@selector(key6Pressed)],
              [UIKeyCommand keyCommandWithInput:@"§"   modifierFlags:0 action:@selector(key6Pressed)],
              [UIKeyCommand keyCommandWithInput:@"6"   modifierFlags:UIKeyModifierAlternate action:@selector(key6AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"§"   modifierFlags:UIKeyModifierAlternate action:@selector(key6AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"7"   modifierFlags:0 action:@selector(key7Pressed)],
              [UIKeyCommand keyCommandWithInput:@"è"   modifierFlags:0 action:@selector(key7Pressed)],
              [UIKeyCommand keyCommandWithInput:@"7"   modifierFlags:UIKeyModifierAlternate action:@selector(key7AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"è"   modifierFlags:UIKeyModifierAlternate action:@selector(key7AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"8"   modifierFlags:0 action:@selector(key8Pressed)],
              [UIKeyCommand keyCommandWithInput:@"!"   modifierFlags:0 action:@selector(key8Pressed)],
              [UIKeyCommand keyCommandWithInput:@"8"   modifierFlags:UIKeyModifierAlternate action:@selector(key8AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"!"   modifierFlags:UIKeyModifierAlternate action:@selector(key8AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"9"   modifierFlags:0 action:@selector(key9Pressed)],
              [UIKeyCommand keyCommandWithInput:@"ç"   modifierFlags:0 action:@selector(key9Pressed)],
              [UIKeyCommand keyCommandWithInput:@"9"   modifierFlags:UIKeyModifierAlternate action:@selector(key9AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"ç"   modifierFlags:UIKeyModifierAlternate action:@selector(key9AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"0"   modifierFlags:0 action:@selector(key0Pressed)],
              [UIKeyCommand keyCommandWithInput:@"à"   modifierFlags:0 action:@selector(key0Pressed)],
              [UIKeyCommand keyCommandWithInput:@"0"   modifierFlags:UIKeyModifierAlternate action:@selector(key0AltPressed)],
              [UIKeyCommand keyCommandWithInput:@"à"   modifierFlags:UIKeyModifierAlternate action:@selector(key0AltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"i"   modifierFlags:0 action:@selector(keyIPressed)],
              [UIKeyCommand keyCommandWithInput:@"i"   modifierFlags:UIKeyModifierAlternate action:@selector(keyIAltPressed)],
              [UIKeyCommand keyCommandWithInput:@"e"   modifierFlags:0 action:@selector(keyEPressed)],
              [UIKeyCommand keyCommandWithInput:@"f"   modifierFlags:0 action:@selector(keyFPressed)],
              [UIKeyCommand keyCommandWithInput:@"f"   modifierFlags:UIKeyModifierAlternate action:@selector(keyFAltPressed)],
              [UIKeyCommand keyCommandWithInput:@"s"   modifierFlags:0 action:@selector(keySPressed)],
              [UIKeyCommand keyCommandWithInput:@"s"   modifierFlags:UIKeyModifierAlternate action:@selector(keySAltPressed)],
              [UIKeyCommand keyCommandWithInput:@"h"   modifierFlags:0 action:@selector(keyHPressed)],
              [UIKeyCommand keyCommandWithInput:@"\r"   modifierFlags:0 action:@selector(enterPressed)],
              [UIKeyCommand keyCommandWithInput:@" "   modifierFlags:0 action:@selector(spacePressed)],
              
              [UIKeyCommand keyCommandWithInput:@"b"   modifierFlags:0 action:@selector(keyBPressed)],
              [UIKeyCommand keyCommandWithInput:@"m"   modifierFlags:0 action:@selector(keyMPressed)],
              [UIKeyCommand keyCommandWithInput:@"m"   modifierFlags:UIKeyModifierAlternate action:@selector(keyMAltPressed)],
              [UIKeyCommand keyCommandWithInput:@"o"   modifierFlags:0 action:@selector(keyOPressed)],
              [UIKeyCommand keyCommandWithInput:@"o"   modifierFlags:UIKeyModifierAlternate action:@selector(keyOAltPressed)],
              [UIKeyCommand keyCommandWithInput:@"v"   modifierFlags:0 action:@selector(keyVPressed)],
              [UIKeyCommand keyCommandWithInput:@"t"   modifierFlags:0 action:@selector(keyTPressed)],
              [UIKeyCommand keyCommandWithInput:@"t"   modifierFlags:UIKeyModifierAlternate action:@selector(keyTAltPressed)],
              
              [UIKeyCommand keyCommandWithInput:@"p"   modifierFlags:0 action:@selector(keyPPressed)],
              [UIKeyCommand keyCommandWithInput:@"n"   modifierFlags:0 action:@selector(keyNPressed)],
              [UIKeyCommand keyCommandWithInput:@"l"   modifierFlags:0 action:@selector(keyLPressed)],
              [UIKeyCommand keyCommandWithInput:@"a"   modifierFlags:0 action:@selector(keyAPressed)],
              [UIKeyCommand keyCommandWithInput:@"q"   modifierFlags:0 action:@selector(keyQPressed)],
              
              [UIKeyCommand keyCommandWithInput:UIKeyInputEscape   modifierFlags:0 action:@selector(keyESCPressed)],
              [UIKeyCommand keyCommandWithInput:UIKeyInputDelete   modifierFlags:0 action:@selector(keyDeletePressed)],
              tabCommand,];
    
}

#pragma mark - Key Action Methods

-(void)key1Pressed {
    [detailViewControllerIphone switchFX:1 change:1];
}
-(void)key1AltPressed {
    [detailViewControllerIphone switchFX:1 change:-1];
}
-(void)key2Pressed {
    [detailViewControllerIphone switchFX:2 change:1];
}
-(void)key2AltPressed {
    [detailViewControllerIphone switchFX:2 change:-1];
}
-(void)key3Pressed {
    [detailViewControllerIphone switchFX:3 change:1];
}
-(void)key3AltPressed {
    [detailViewControllerIphone switchFX:3 change:-1];
}
-(void)key4Pressed {
    [detailViewControllerIphone switchFX:4 change:1];
}
-(void)key4AltPressed {
    [detailViewControllerIphone switchFX:4 change:-1];
}
-(void)key5Pressed {
    [detailViewControllerIphone switchFX:5 change:1];
}
-(void)key5AltPressed {
    [detailViewControllerIphone switchFX:5 change:-1];
}
-(void)key6Pressed {
    [detailViewControllerIphone switchFX:6 change:1];
}
-(void)key6AltPressed {
    [detailViewControllerIphone switchFX:6 change:-1];
}
-(void)key7Pressed {
    [detailViewControllerIphone switchFX:7 change:1];
}
-(void)key7AltPressed {
    [detailViewControllerIphone switchFX:7 change:-1];
}
-(void)key8Pressed {
    [detailViewControllerIphone switchFX:8 change:1];
}
-(void)key8AltPressed {
    [detailViewControllerIphone switchFX:8 change:-1];
}
-(void)key9Pressed {
    [detailViewControllerIphone switchFX:9 change:1];
}
-(void)key9AltPressed {
    [detailViewControllerIphone switchFX:9 change:-1];
}
-(void)key0Pressed {
    [detailViewControllerIphone switchFX:0 change:1];
}
-(void)key0AltPressed {
    [detailViewControllerIphone switchFX:0 change:-1];
}
- (void)enterPressed{
    [detailViewControllerIphone oglViewSwitchFS];
}
- (void)keyVPressed{
    [detailViewControllerIphone mdSwitchVolBars];
}
- (void)keyBPressed{
    [detailViewControllerIphone mdSwitchFixedBar];
}
- (void)keyIPressed{
    [detailViewControllerIphone mdShowMusicInfo];
    [detailViewControllerIphone mdInfoFX];
}
- (void)keyIAltPressed{
    
}
- (void)keyMPressed{
    [detailViewControllerIphone mdSwitchSpectrumBloom:1];
}
- (void)keyMAltPressed{
    [detailViewControllerIphone mdSwitchSpectrumBloom:-1];
}
- (void)keyOPressed{
    [detailViewControllerIphone mdSwitchLandscapeBloom:1];
}
- (void)keyOAltPressed{
    [detailViewControllerIphone mdSwitchLandscapeBloom:-1];
}
- (void)keyFPressed{
    [detailViewControllerIphone mdSwitchModPatternFont:1];
}
- (void)keyFAltPressed{
    [detailViewControllerIphone mdSwitchModPatternFont:-1];
}
- (void)keySPressed{
    [detailViewControllerIphone mdSwitchModPatternFontSize:1];
}
- (void)keySAltPressed{
    [detailViewControllerIphone mdSwitchModPatternFontSize:-1];
}
- (void)keyTPressed{
    [detailViewControllerIphone mdSwitchModPatternTheme:1];
}
- (void)keyTAltPressed{
    [detailViewControllerIphone mdSwitchModPatternTheme:-1];
}
- (void)keyEPressed{
    [detailViewControllerIphone oglButtonPushed];
}
- (void)keyNPressed{
    [detailViewControllerIphone mdNextPreset];
}
- (void)keyPPressed{
    [detailViewControllerIphone mdPrevPreset];
}
- (void)keyHPressed{
    [detailViewControllerIphone mdSwitchFPSHud];
}
- (void)keyLPressed{
    [detailViewControllerIphone mdSwitchLockStatusPreset];
}
- (void)keyAPressed{
    [detailViewControllerIphone mdChangeFavoriteStatusPreset:0];
}
- (void)keyESCPressed{
    [detailViewControllerIphone mdOpenCloseMenu];
}
//- (void)keyDeletePressed{
//    [detailViewControllerIphone mdBackAction];
//}
- (void)keyDeletePressed {
      if (detailViewControllerIphone.isViewLoaded && detailViewControllerIphone.view.window) {
          [detailViewControllerIphone mdBackAction];
      } else {
          UINavigationController *navController = (UINavigationController *)self.selectedViewController;
          [navController popViewControllerAnimated:YES];
      }
  }
- (void)keyQPressed {
    [detailViewControllerIphone mdTestAsyncLoad];
}
/*
- (UIViewController *) getVisibleViewControllerFrom:(UIViewController *) vc {
    if ([vc isKindOfClass:[UINavigationController class]]) {
        return [self getVisibleViewControllerFrom:[((UINavigationController *) vc) visibleViewController]];
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        return [self getVisibleViewControllerFrom:[((UITabBarController *) vc) selectedViewController]];
    } else {
        if (vc.presentedViewController) {
            return [self getVisibleViewControllerFrom:vc.presentedViewController];
        } else {
            return vc;
        }
    }
}

- (UIViewController *)visibleViewController {
    UIViewController *rootViewController = self;//.rootViewController;
    return [self getVisibleViewControllerFrom:rootViewController];
}*/

-(void) goToPlayerView {
#if TARGET_OS_MACCATALYST
    if ([self mdzShowPlayerOnDetailSide]) {
        return;
    }
#endif
    UIViewController *currentVC=[self visibleViewController:self];
    if (currentVC) {
        if ([currentVC respondsToSelector:@selector(goPlayer)]) [currentVC performSelector:@selector(goPlayer)];
    }
}


- (void)keyTabPressed{
    [self goToPlayerView];
}

-(void)leftPressed {
    [detailViewControllerIphone jumpSeekBwd:30];
}
-(void)rightPressed {
    [detailViewControllerIphone jumpSeekFwd:30];
}
-(void)leftShiftPressed {
    [detailViewControllerIphone jumpSeekBwd:60];
}
-(void)rightShiftPressed {
    [detailViewControllerIphone jumpSeekFwd:60];
}
-(void)leftCmdPressed {
    [detailViewControllerIphone playPrev];
}
-(void)rightCmdPressed {
    [detailViewControllerIphone playNext];
}
-(void)leftAltPressed {
    if ((detailViewControllerIphone.mplayer.mod_subsongs>1)&&
        (detailViewControllerIphone.mplayer.mod_currentsub>detailViewControllerIphone.mplayer.mod_minsub)&&(detailViewControllerIphone.mOnlyCurrentSubEntry==0))
        [detailViewControllerIphone playPrevSub]; //should handle sub ?
    else {//no more subsongs, check if within an archive to play prev entry
        if ([detailViewControllerIphone.mplayer isArchive]&&([detailViewControllerIphone.mplayer getArcEntriesCnt]>1)&&([detailViewControllerIphone.mplayer getArcIndex]>0)&&(detailViewControllerIphone.mOnlyCurrentEntry==0)) {
            [detailViewControllerIphone.mplayer selectPrevArcEntry];
            [detailViewControllerIphone play_loadArchiveModule];
        } else [detailViewControllerIphone play_prevEntry];
    }
}
-(void)rightAltPressed {
    //1st check if there are more subsongs
    if ((detailViewControllerIphone.mplayer.mod_subsongs>1)&&
        (detailViewControllerIphone.mplayer.mod_currentsub<detailViewControllerIphone.mplayer.mod_maxsub)&&(detailViewControllerIphone.mOnlyCurrentSubEntry==0))
        [detailViewControllerIphone playNextSub];
    else {
        //no more subsongs, check if within an archive to play next entry
        
        if ([detailViewControllerIphone.mplayer isArchive]&&([detailViewControllerIphone.mplayer getArcEntriesCnt]>1)&&(detailViewControllerIphone.mOnlyCurrentEntry==0)) {
            if ([detailViewControllerIphone.mplayer selectNextArcEntry]<0) [detailViewControllerIphone play_nextEntry];
            else [detailViewControllerIphone play_loadArchiveModule];
        } else [detailViewControllerIphone play_nextEntry];
    }
}

-(void)upPressed {
    [detailViewControllerIphone restartCurrent];
}
-(void)downPressed {
    [self rightAltPressed];
}
-(void)spacePressed {
    if (detailViewControllerIphone.mPaused) [detailViewControllerIphone playPushed];
    else [detailViewControllerIphone pausePushed];
}

#pragma mark - Press Events

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    bool _dontForwardEvent=false;
    for (UIPress *press in presses) {
        UIKey *key=press.key;
        if (key.keyCode==UIKeyboardHIDUsageKeyboardRightShift) {
            [detailViewControllerIphone mdShiftMode:0];
        }
        //MDZILog("adding release of %d",(int)key.keyCode);
        [mac_key_released addObject:[NSNumber numberWithInt:(int)key.keyCode]];
    }
    if (!_dontForwardEvent) [super pressesEnded:presses withEvent:event];
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses
           withEvent:(UIPressesEvent *)event {
    bool _dontForwardEvent=false;
    for (UIPress *press in presses) {
        UIKey *key=press.key;
        if (key.keyCode==UIKeyboardHIDUsageKeyboardRightShift) {
            [detailViewControllerIphone mdShiftMode:1];
        }
        //MDZILog("adding press of %d",(int)key.keyCode);
        [mac_key_pressed addObject:[NSNumber numberWithInt:(int)key.keyCode]];
    }
    if (!_dontForwardEvent) [super pressesBegan:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    // Traiter comme un release
    bool _dontForwardEvent=false;
    for (UIPress *press in presses) {
        UIKey *key=press.key;
        if (key.keyCode==UIKeyboardHIDUsageKeyboardRightShift) {
            [detailViewControllerIphone mdShiftMode:0];
        }
        //MDZILog("adding cancel of %d",(int)key.keyCode);
        [mac_key_released addObject:[NSNumber numberWithInt:(int)key.keyCode]];
    }
    if (!_dontForwardEvent) [super pressesCancelled:presses withEvent:event];
}

#pragma mark - Remote Control

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.subtype == UIEventSubtypeRemoteControlTogglePlayPause) {
        if (detailViewControllerIphone.mPaused) {
            detailViewControllerIphone.mPaused=0;
            [detailViewControllerIphone.mplayer Pause:NO];
        } else {
            detailViewControllerIphone.mPaused=1;
            [detailViewControllerIphone.mplayer Pause:YES];
        }
    }
    if (event.subtype == UIEventSubtypeRemoteControlPlay) {
        if (detailViewControllerIphone.mPaused) {
            detailViewControllerIphone.mPaused=0;
            [detailViewControllerIphone.mplayer Pause:NO];
        }
    }
    if (event.subtype == UIEventSubtypeRemoteControlPause) {
        if (detailViewControllerIphone.mPaused==0) {
            detailViewControllerIphone.mPaused=1;
            [detailViewControllerIphone.mplayer Pause:YES];
        }
    }
    if (event.subtype == UIEventSubtypeRemoteControlStop) {
        if (detailViewControllerIphone.mPaused==0) {
            detailViewControllerIphone.mPaused=1;
            [detailViewControllerIphone.mplayer Pause:YES];
        }
    }
    if (event.subtype == UIEventSubtypeRemoteControlNextTrack) {
        //1st check if there are more subsongs
        if ((detailViewControllerIphone.mplayer.mod_subsongs>1)&&
            (detailViewControllerIphone.mplayer.mod_currentsub<detailViewControllerIphone.mplayer.mod_maxsub)&&(detailViewControllerIphone.mOnlyCurrentSubEntry==0))
            [detailViewControllerIphone playNextSub];
        else {
            //no more subsongs, check if within an archive to play next entry
            
            if ([detailViewControllerIphone.mplayer isArchive]&&([detailViewControllerIphone.mplayer getArcEntriesCnt]>1)&&(detailViewControllerIphone.mOnlyCurrentEntry==0)) {
                if ([detailViewControllerIphone.mplayer selectNextArcEntry]<0) [detailViewControllerIphone play_nextEntry];
                else [detailViewControllerIphone play_loadArchiveModule];
            } else [detailViewControllerIphone play_nextEntry];
        }
    }
    if (event.subtype == UIEventSubtypeRemoteControlPreviousTrack) {
        //1st check if there are more subsongs
        if ((detailViewControllerIphone.mplayer.mod_subsongs>1)&&
            (detailViewControllerIphone.mplayer.mod_currentsub>detailViewControllerIphone.mplayer.mod_minsub)&&(detailViewControllerIphone.mOnlyCurrentSubEntry==0))
            [detailViewControllerIphone playPrevSub]; //should handle sub ?
        else {//no more subsongs, check if within an archive to play prev entry
            if ([detailViewControllerIphone.mplayer isArchive]&&([detailViewControllerIphone.mplayer getArcEntriesCnt]>1)&&([detailViewControllerIphone.mplayer getArcIndex]>0)&&(detailViewControllerIphone.mOnlyCurrentEntry==0)) {
                [detailViewControllerIphone.mplayer selectPrevArcEntry];
                [detailViewControllerIphone play_loadArchiveModule];
            } else [detailViewControllerIphone play_prevEntry];
        }
    }
    
    /*UIEventSubtypeRemoteControlBeginSeekingBackward = 106,
    UIEventSubtypeRemoteControlEndSeekingBackward   = 107,
    UIEventSubtypeRemoteControlBeginSeekingForward  = 108,
    UIEventSubtypeRemoteControlEndSeekingForward    = 109,*/
}


#pragma mark - UINavigationControllerDelegate

#if TARGET_OS_MACCATALYST
- (void)navigationController:(UINavigationController *)navigationController
       willShowViewController:(UIViewController *)viewController
                     animated:(BOOL)animated {
    if (self.catalystSplitViewController) {
        [self mdzApplyMacTabBarHidden];
        [self mdzApplyMacSidebarNavChrome];
        if (navigationController == self.rootViewControllerIphone.navigationController &&
            [viewController isKindOfClass:[DetailViewControllerIphone class]]) {
            NSMutableArray *stack = [navigationController.viewControllers mutableCopy];
            [stack removeObject:viewController];
            navigationController.viewControllers = stack;
            [self mdzShowPlayerOnDetailSide];
        } else if ([self.viewControllers containsObject:navigationController]) {
            [navigationController setNavigationBarHidden:YES animated:NO];
            viewController.navigationItem.hidesBackButton = YES;
            viewController.navigationItem.leftBarButtonItem = nil;
            [self mdzPinMacSidebarSearchBars];
        }
        return;
    }
    self.tabBar.hidden = YES;
    self.tabBar.frame = CGRectZero;
}
#endif

- (BOOL)canBecomeFirstResponder {
    return YES;
}

@end

#if TARGET_OS_MACCATALYST
@implementation UINavigationController (MDZMacPlayer)
- (void)mdz_pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if ([viewController isKindOfClass:[DetailViewControllerIphone class]]) {
        AppDelegate_Phone *appDelegate = (AppDelegate_Phone *)[[UIApplication sharedApplication] delegate];
        if (appDelegate.tabBarC.catalystSplitViewController && [appDelegate.tabBarC mdzShowPlayerOnDetailSide]) {
            return;
        }
    }
    [self mdz_pushViewController:viewController animated:animated];
}
@end
#endif

