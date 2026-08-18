//
//  RootViewControllerLocalFolders.h
//  modizer
//
//  Local tab: a list of user-picked folders. Adding indexes a directory
//  for browsing; removing drops it from the list without deleting files.
//

#import <UIKit/UIKit.h>

@class DetailViewControllerIphone;
@class RootViewControllerLocalBrowser;

@interface RootViewControllerLocalFolders : UIViewController <UITableViewDelegate, UITableViewDataSource, UINavigationControllerDelegate>

@property (nonatomic, strong) DetailViewControllerIphone *detailViewController;
@property (nonatomic, strong) UITableView *tableView;

+ (RootViewControllerLocalBrowser *)mdzMakeBrowserAtPath:(NSString *)path
                                                   title:(NSString *)title
                                                   depth:(int)depth
                                                  detail:(DetailViewControllerIphone *)detail;

@end
