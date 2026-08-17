//
//  MDZLocalFolderStore.h
//  modizer
//
//  User-picked local folders for the Local tab. Entries are bookmarks
//  only: removing a folder drops it from the list and does not delete
//  anything on disk.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MDZLocalFolder : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *path;
@property (nonatomic, strong, nullable) NSData *bookmarkData;
@property (nonatomic, strong, nullable) NSURL *resolvedURL;
@property (nonatomic, assign) BOOL accessible;

- (BOOL)createBookmarkFromURL:(NSURL *)url;
- (BOOL)resolveBookmark;
- (BOOL)startAccessing;
- (void)stopAccessing;

@end

@interface MDZLocalFolderStore : NSObject

@property (nonatomic, strong, readonly) NSArray<MDZLocalFolder *> *folders;

+ (instancetype)sharedStore;

- (void)load;
- (void)save;

- (nullable MDZLocalFolder *)addFolderWithURL:(NSURL *)url;
- (void)removeFolder:(MDZLocalFolder *)folder;
- (BOOL)containsPath:(NSString *)path;

- (void)presentFolderPickerFrom:(UIViewController *)viewController
                     completion:(void (^)(NSURL * _Nullable url, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
