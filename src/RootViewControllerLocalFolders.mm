//
//  RootViewControllerLocalFolders.mm
//  modizer
//

#import "RootViewControllerLocalFolders.h"
#import "RootViewControllerLocalBrowser.h"
#import "DetailViewControllerIphone.h"
#import "MDZLocalFolderStore.h"
#import "ModizerConstants.h"
#import "TTFadeAnimator.h"

@interface RootViewControllerLocalFolders ()
@property (nonatomic, strong) UIViewController *childController;
@end

@implementation RootViewControllerLocalFolders

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Local", @"");
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    if (MDZIsMacDesktop()) {
        self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
        self.navigationItem.hidesBackButton = YES;
        self.navigationItem.leftBarButtonItem = nil;
        [self.navigationController setNavigationBarHidden:YES animated:NO];
    }

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = MDZIsMacDesktop() ? MDZ_MAC_TABLE_ROW_HEIGHT : 52.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    if (MDZIsMacDesktop()) {
        self.tableView.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
        self.tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    }
    [self.view addSubview:self.tableView];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.childController = nil;
    self.navigationController.delegate = self;
    if (MDZIsMacDesktop()) {
        [self.navigationController setNavigationBarHidden:YES animated:NO];
    }
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    MDZAdaptVisibleMacTableCells(self.tableView);
}

- (NSInteger)mdzFolderCount {
    return (NSInteger)[MDZLocalFolderStore sharedStore].folders.count;
}

- (BOOL)mdzIsAddRow:(NSIndexPath *)indexPath {
    return indexPath.row >= [self mdzFolderCount];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self mdzFolderCount] + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL addRow = [self mdzIsAddRow:indexPath];
    NSString *ident = addRow ? @"add" : @"folder";
    UITableViewCellStyle style = addRow ? UITableViewCellStyleDefault : UITableViewCellStyleSubtitle;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:ident];
    }
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                      weight:UIImageSymbolWeightMedium];
    if (addRow) {
        cell.textLabel.text = NSLocalizedString(@"Add Folder", @"");
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:cfg];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.textLabel.textColor = [UIColor systemBlueColor];
    } else {
        MDZLocalFolder *folder = [MDZLocalFolderStore sharedStore].folders[indexPath.row];
        cell.textLabel.text = folder.name;
        cell.detailTextLabel.text = folder.path ?: @"";
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill" withConfiguration:cfg];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIColor *fg = folder.accessible ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        if (MDZIsMacDesktop()) {
            fg = folder.accessible ? [UIColor colorWithWhite:1.0 alpha:0.92] : [UIColor colorWithWhite:1.0 alpha:0.42];
        }
        cell.textLabel.textColor = fg;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.tintColor = [UIColor systemBlueColor];
    }
    cell.textLabel.font = [UIFont systemFontOfSize:MDZIsMacDesktop() ? 16.0 : 16.0 weight:UIFontWeightMedium];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    if (MDZIsMacDesktop()) {
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        cell.selectedBackgroundView = sel;
        if (addRow) {
            cell.textLabel.textColor = [UIColor colorWithRed:0.45 green:0.72 blue:1.0 alpha:1.0];
        }
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return ![self mdzIsAddRow:indexPath];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return NSLocalizedString(@"Remove", @"");
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    [self mdzRemoveFolderAtIndex:indexPath.row];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self mdzIsAddRow:indexPath]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                         title:NSLocalizedString(@"Remove", @"")
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self mdzRemoveFolderAtIndex:indexPath.row];
        completionHandler(YES);
    }];
    remove.backgroundColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[remove]];
    cfg.performsFirstActionWithFullSwipe = YES;
    return cfg;
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if ([self mdzIsAddRow:indexPath]) {
        return nil;
    }
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> *suggestedActions) {
        UIAction *remove = [UIAction actionWithTitle:NSLocalizedString(@"Remove", @"")
                                               image:[UIImage systemImageNamed:@"minus.circle"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
            [self mdzRemoveFolderAtIndex:indexPath.row];
        }];
        return [UIMenu menuWithTitle:@"" children:@[remove]];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self mdzIsAddRow:indexPath]) {
        [self mdzAddFolder];
        return;
    }
    MDZLocalFolder *folder = [MDZLocalFolderStore sharedStore].folders[indexPath.row];
    [self mdzOpenFolder:folder];
}

- (void)mdzRemoveFolderAtIndex:(NSInteger)index {
    NSArray<MDZLocalFolder *> *folders = [MDZLocalFolderStore sharedStore].folders;
    if (index < 0 || index >= (NSInteger)folders.count) {
        return;
    }
    [[MDZLocalFolderStore sharedStore] removeFolder:folders[index]];
    [self.tableView reloadData];
}

- (void)mdzAddFolder {
    [[MDZLocalFolderStore sharedStore] presentFolderPickerFrom:self completion:^(NSURL *url, NSError *error) {
        if (!url) {
            return;
        }
        NSString *path = url.path.stringByStandardizingPath;
        BOOL already = [[MDZLocalFolderStore sharedStore] containsPath:path];
        MDZLocalFolder *folder = [[MDZLocalFolderStore sharedStore] addFolderWithURL:url];
        [url stopAccessingSecurityScopedResource];
        [self.tableView reloadData];
        if (already && folder) {
            return;
        }
        (void)error;
    }];
}

- (void)mdzOpenFolder:(MDZLocalFolder *)folder {
    if (![folder startAccessing] || folder.path.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"")
                                                                       message:NSLocalizedString(@"Cannot access this folder. You can remove it from the list.", @"")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    RootViewControllerLocalBrowser *browser = [[RootViewControllerLocalBrowser alloc] initWithNibName:@"PlaylistViewController" bundle:[NSBundle mainBundle]];
    browser.title = folder.name;
    browser.currentPath = folder.path;
    browser->browse_depth = 1;
    browser.detailViewController = self.detailViewController;
    if (MDZIsMacDesktop()) {
        browser.edgesForExtendedLayout = UIRectEdgeAll;
        browser.extendedLayoutIncludesOpaqueBars = YES;
        browser.hidesBottomBarWhenPushed = NO;
    } else {
        browser.edgesForExtendedLayout = UIRectEdgeNone;
        browser.extendedLayoutIncludesOpaqueBars = NO;
    }
    self.childController = browser;
    self.navigationController.delegate = self;
    [self.navigationController pushViewController:browser animated:YES];
}

#pragma mark - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                  animationControllerForOperation:(UINavigationControllerOperation)operation
                                               fromViewController:(UIViewController *)fromVC
                                                 toViewController:(UIViewController *)toVC {
    return [[TTFadeAnimator alloc] init];
}

@end
