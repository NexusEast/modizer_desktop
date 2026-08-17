//
//  MDZLocalFolderStore.mm
//  modizer
//

#import "MDZLocalFolderStore.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const kMDZLocalFoldersDefaultsKey = @"MDZLocalFolders";

@implementation MDZLocalFolder {
    BOOL mdzAccessing;
}

- (BOOL)createBookmarkFromURL:(NSURL *)url {
    if (!url) {
        return NO;
    }
    NSError *error = nil;
    NSURLBookmarkCreationOptions options = 0;
#if TARGET_OS_MACCATALYST || TARGET_OS_OSX
    options |= NSURLBookmarkCreationWithSecurityScope;
#else
    options |= NSURLBookmarkCreationMinimalBookmark;
#endif
    NSData *bookmark = [url bookmarkDataWithOptions:options
                     includingResourceValuesForKeys:nil
                                      relativeToURL:nil
                                              error:&error];
    self.resolvedURL = url;
    self.path = url.path;
    if (self.name.length == 0) {
        self.name = url.lastPathComponent ?: @"Folder";
    }
    if (error || !bookmark) {
        self.accessible = YES;
        return NO;
    }
    self.bookmarkData = bookmark;
    self.accessible = YES;
    return YES;
}

- (BOOL)resolveBookmark {
    if (!self.bookmarkData) {
        self.accessible = (self.resolvedURL != nil || self.path.length > 0);
        return self.accessible;
    }
    NSError *error = nil;
    BOOL stale = NO;
    NSURLBookmarkResolutionOptions options = 0;
#if TARGET_OS_MACCATALYST || TARGET_OS_OSX
    options |= NSURLBookmarkResolutionWithSecurityScope;
#endif
    NSURL *resolved = [NSURL URLByResolvingBookmarkData:self.bookmarkData
                                                options:options
                                          relativeToURL:nil
                                    bookmarkDataIsStale:&stale
                                                  error:&error];
    if (error || !resolved) {
        self.accessible = NO;
        return NO;
    }
    self.resolvedURL = resolved;
    self.path = resolved.path;
    self.accessible = YES;
    if (stale) {
        [self createBookmarkFromURL:resolved];
    }
    return YES;
}

- (BOOL)startAccessing {
    if (![self resolveBookmark]) {
        return NO;
    }
    NSURL *url = self.resolvedURL;
    if (!url) {
        return NO;
    }
    if (!mdzAccessing) {
        mdzAccessing = [url startAccessingSecurityScopedResource];
    }
    return YES;
}

- (void)stopAccessing {
    if (mdzAccessing && self.resolvedURL) {
        [self.resolvedURL stopAccessingSecurityScopedResource];
    }
    mdzAccessing = NO;
}

@end

@interface MDZLocalFolderStore () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSMutableArray<MDZLocalFolder *> *mutableFolders;
@property (nonatomic, copy) void (^pickerCompletion)(NSURL * _Nullable url, NSError * _Nullable error);
@property (nonatomic, strong) UIDocumentPickerViewController *picker;
@end

@implementation MDZLocalFolderStore

+ (instancetype)sharedStore {
    static MDZLocalFolderStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[MDZLocalFolderStore alloc] init];
        [store load];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableFolders = [NSMutableArray array];
    }
    return self;
}

- (NSArray<MDZLocalFolder *> *)folders {
    return [self.mutableFolders copy];
}

- (void)load {
    [self.mutableFolders removeAllObjects];
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kMDZLocalFoldersDefaultsKey];
    for (id item in saved) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = (NSDictionary *)item;
        MDZLocalFolder *folder = [[MDZLocalFolder alloc] init];
        folder.identifier = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
        folder.name = dict[@"name"] ?: @"Folder";
        folder.path = dict[@"path"];
        id bookmark = dict[@"bookmark"];
        if ([bookmark isKindOfClass:[NSData class]]) {
            folder.bookmarkData = bookmark;
        }
        [folder resolveBookmark];
        [self.mutableFolders addObject:folder];
    }
}

- (void)save {
    NSMutableArray *payload = [NSMutableArray array];
    for (MDZLocalFolder *folder in self.mutableFolders) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"id"] = folder.identifier ?: [[NSUUID UUID] UUIDString];
        dict[@"name"] = folder.name ?: @"Folder";
        if (folder.path) {
            dict[@"path"] = folder.path;
        }
        if (folder.bookmarkData) {
            dict[@"bookmark"] = folder.bookmarkData;
        }
        [payload addObject:dict];
    }
    [[NSUserDefaults standardUserDefaults] setObject:payload forKey:kMDZLocalFoldersDefaultsKey];
}

- (BOOL)containsPath:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }
    NSString *std = path.stringByStandardizingPath;
    for (MDZLocalFolder *folder in self.mutableFolders) {
        if ([folder.path.stringByStandardizingPath isEqualToString:std]) {
            return YES;
        }
    }
    return NO;
}

- (MDZLocalFolder *)addFolderWithURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    NSString *path = url.path.stringByStandardizingPath;
    if ([self containsPath:path]) {
        for (MDZLocalFolder *folder in self.mutableFolders) {
            if ([folder.path.stringByStandardizingPath isEqualToString:path]) {
                return folder;
            }
        }
    }
    MDZLocalFolder *folder = [[MDZLocalFolder alloc] init];
    folder.identifier = [[NSUUID UUID] UUIDString];
    folder.name = url.lastPathComponent ?: @"Folder";
    [folder createBookmarkFromURL:url];
    [folder startAccessing];
    [self.mutableFolders addObject:folder];
    [self save];
    return folder;
}

- (void)removeFolder:(MDZLocalFolder *)folder {
    if (!folder) {
        return;
    }
    [folder stopAccessing];
    [self.mutableFolders removeObject:folder];
    [self save];
}

- (void)presentFolderPickerFrom:(UIViewController *)viewController
                     completion:(void (^)(NSURL * _Nullable url, NSError * _Nullable error))completion {
    self.pickerCompletion = completion;
#if TARGET_OS_MACCATALYST
    Class NSOpenPanelClass = NSClassFromString(@"NSOpenPanel");
    if (NSOpenPanelClass) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id openPanel = [NSOpenPanelClass performSelector:@selector(openPanel)];
#pragma clang diagnostic pop
        [openPanel setValue:@NO forKey:@"canChooseFiles"];
        [openPanel setValue:@YES forKey:@"canChooseDirectories"];
        [openPanel setValue:@NO forKey:@"allowsMultipleSelection"];
        [openPanel setValue:@NO forKey:@"canCreateDirectories"];
        [openPanel setValue:NSLocalizedString(@"Select Folder", @"") forKey:@"title"];
        [openPanel setValue:NSLocalizedString(@"Add", @"") forKey:@"prompt"];
        [openPanel setValue:NSLocalizedString(@"Choose a folder to browse in Modizer. Files are not copied.", @"") forKey:@"message"];
        typedef void (^NSOpenPanelCompletionHandler)(NSInteger result);
        NSOpenPanelCompletionHandler handler = ^(NSInteger result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result == 1) {
                    NSArray *urls = [openPanel valueForKey:@"URLs"];
                    NSURL *url = urls.firstObject;
                    if (url) {
                        [url startAccessingSecurityScopedResource];
                        if (self.pickerCompletion) {
                            self.pickerCompletion(url, nil);
                        }
                    } else if (self.pickerCompletion) {
                        self.pickerCompletion(nil, nil);
                    }
                } else if (self.pickerCompletion) {
                    self.pickerCompletion(nil, nil);
                }
                self.pickerCompletion = nil;
            });
        };
        SEL selector = @selector(beginWithCompletionHandler:);
        NSMethodSignature *signature = [openPanel methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:openPanel];
        [invocation setSelector:selector];
        [invocation setArgument:&handler atIndex:2];
        [invocation invoke];
        return;
    }
#endif
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"]
                                                                        inMode:UIDocumentPickerModeOpen];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    self.picker = picker;
    [viewController presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) {
        [url startAccessingSecurityScopedResource];
    }
    if (self.pickerCompletion) {
        self.pickerCompletion(url, nil);
    }
    self.pickerCompletion = nil;
    self.picker = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (self.pickerCompletion) {
        self.pickerCompletion(nil, nil);
    }
    self.pickerCompletion = nil;
    self.picker = nil;
}

@end
