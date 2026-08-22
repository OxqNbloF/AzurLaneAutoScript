#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <signal.h>
#import <unistd.h>

@interface AlasAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSTask *backendProcess;
@property(nonatomic, strong) NSTask *caffeinateProcess;
@property(nonatomic, strong) NSPipe *stderrPipe;
@property(nonatomic, strong) NSMutableString *stderrText;
@property(nonatomic, strong) NSURL *serverURL;
@property(nonatomic) BOOL serverLoaded;
@property(nonatomic) BOOL terminating;
@end

@implementation AlasAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.stderrText = [NSMutableString string];
    if ([self activateExistingInstance]) {
        [NSApp terminate:nil];
        return;
    }

    [self configureMenus];
    [self configureWindow];

    NSError *error = nil;
    NSURL *alasRoot = [self resolveAlasRoot:&error];
    if (!alasRoot) {
        [self showFatalError:error.localizedDescription];
        return;
    }

    NSString *pythonPath = nil;
    NSInteger port = 0;
    if (![self readSettingsAtRoot:alasRoot pythonPath:&pythonPath port:&port error:&error]) {
        [self showFatalError:error.localizedDescription];
        return;
    }
    if (![self startBackendAtRoot:alasRoot pythonPath:pythonPath port:port error:&error]) {
        [self showFatalError:error.localizedDescription];
        return;
    }

    [self waitForServerOnPort:port attemptsRemaining:120];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    self.terminating = YES;
    [self stopBackend];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showWindow:nil];
    return YES;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [sender orderOut:nil];
    return NO;
}

- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    return nil;
}

- (BOOL)activateExistingInstance {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (bundleIdentifier.length == 0) return NO;

    pid_t currentPID = NSProcessInfo.processInfo.processIdentifier;
    for (NSRunningApplication *application in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier]) {
        if (application.processIdentifier != currentPID) {
            [application activateWithOptions:NSApplicationActivateAllWindows];
            return YES;
        }
    }
    return NO;
}

- (void)configureWindow {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    if (@available(macOS 13.3, *)) {
        self.webView.inspectable = YES;
    }

    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1280, 880)
                  styleMask:style
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"Alas";
    self.window.delegate = self;
    self.window.contentView = self.webView;
    [self.window center];
    [self.window setFrameAutosaveName:@"AlasMainWindow"];
    [self.window makeKeyAndOrderFront:nil];
    [self showLoadingPage:@"Starting Alas…"];
}

- (void)configureMenus {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Alas" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Show Alas" action:@selector(showWindow:) keyEquivalent:@""];
    [appMenu addItemWithTitle:@"Hide Alas" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Quit Alas" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:NSMenuItem.separatorItem];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Reload" action:@selector(reloadPage:) keyEquivalent:@"r"];
    [viewMenu addItem:NSMenuItem.separatorItem];
    [viewMenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];

    NSApp.mainMenu = mainMenu;
}

- (void)showWindow:(id)sender {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)reloadPage:(id)sender {
    if (self.serverURL) {
        [self.webView loadRequest:[NSURLRequest requestWithURL:self.serverURL]];
    } else {
        [self.webView reload];
    }
}

- (NSURL *)resolveAlasRoot:(NSError **)error {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *override = NSProcessInfo.processInfo.environment[@"ALAS_PATH"];
    if (override.length > 0) {
        [roots addObject:override.stringByExpandingTildeInPath];
    }
    [roots addObject:NSFileManager.defaultManager.currentDirectoryPath];

    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    if (bundlePath.length > 0) {
        // A local build lives at <alas>/webapp/dist/Alas.app. This direct
        // candidate avoids walking at all in the common case.
        [roots addObject:[bundlePath stringByAppendingPathComponent:@"../../.."]];
        [roots addObject:bundlePath.stringByDeletingLastPathComponent];
    }

    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    for (NSString *root in roots) {
        NSString *candidate = root.stringByStandardizingPath;
        // Never let malformed or future Foundation path behavior turn startup
        // discovery into an unbounded loop on the main thread.
        for (NSInteger depth = 0; depth < 24 && candidate.length > 0; depth++) {
            if ([visited containsObject:candidate]) break;
            [visited addObject:candidate];

            NSString *gui = [candidate stringByAppendingPathComponent:@"gui.py"];
            NSString *deploy = [candidate stringByAppendingPathComponent:@"config/deploy.yaml"];
            if ([NSFileManager.defaultManager fileExistsAtPath:gui] &&
                [NSFileManager.defaultManager fileExistsAtPath:deploy]) {
                return [NSURL fileURLWithPath:candidate isDirectory:YES];
            }

            NSString *parent = candidate.stringByDeletingLastPathComponent;
            if (parent.length == 0 || [parent isEqualToString:candidate]) break;
            candidate = parent;
        }
    }

    if (error) {
        *error = [NSError errorWithDomain:@"AlasNative" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"Unable to find AzurLaneAutoScript. Set ALAS_PATH to the directory containing gui.py and config/deploy.yaml."
        }];
    }
    return nil;
}

- (BOOL)readSettingsAtRoot:(NSURL *)root
                pythonPath:(NSString **)pythonPath
                      port:(NSInteger *)port
                     error:(NSError **)error {
    NSURL *deployURL = [root URLByAppendingPathComponent:@"config/deploy.yaml"];
    NSString *text = [NSString stringWithContentsOfURL:deployURL encoding:NSUTF8StringEncoding error:error];
    if (!text) return NO;

    NSString *configuredPython = [self yamlScalar:@"PythonExecutable" inText:text];
    NSString *configuredPort = [self yamlScalar:@"WebuiPort" inText:text];
    if (configuredPython.length == 0 || configuredPort.integerValue <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"AlasNative" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"PythonExecutable or WebuiPort is missing from config/deploy.yaml."
            }];
        }
        return NO;
    }

    NSString *expanded = configuredPython.stringByExpandingTildeInPath;
    NSString *resolved = expanded.isAbsolutePath
        ? expanded
        : [root URLByAppendingPathComponent:expanded].URLByStandardizingPath.path;
    if (![NSFileManager.defaultManager isExecutableFileAtPath:resolved]) {
        if (error) {
            *error = [NSError errorWithDomain:@"AlasNative" code:3 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The configured Python executable does not exist: %@", resolved]
            }];
        }
        return NO;
    }

    *pythonPath = resolved;
    *port = configuredPort.integerValue;
    return YES;
}

- (NSString *)yamlScalar:(NSString *)key inText:(NSString *)text {
    NSString *prefix = [key stringByAppendingString:@":"];
    for (NSString *original in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [[original componentsSeparatedByString:@"#"].firstObject
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![line hasPrefix:prefix]) continue;
        NSString *value = [[line substringFromIndex:prefix.length]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        return [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
    }
    return nil;
}

- (BOOL)startBackendAtRoot:(NSURL *)root
                pythonPath:(NSString *)pythonPath
                      port:(NSInteger)port
                     error:(NSError **)error {
    NSTask *process = [[NSTask alloc] init];
    process.executableURL = [NSURL fileURLWithPath:pythonPath];
    process.currentDirectoryURL = root;
    process.arguments = @[
        @"gui.py",
        @"--host", @"127.0.0.1",
        @"--port", @(port).stringValue,
        @"--app",
    ];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PYTHONUNBUFFERED"] = @"1";
    process.environment = environment;
    process.standardOutput = NSFileHandle.fileHandleWithNullDevice;

    NSPipe *pipe = [NSPipe pipe];
    self.stderrPipe = pipe;
    process.standardError = pipe;
    __weak typeof(self) weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) {
            handle.readabilityHandler = nil;
            return;
        }
        [NSFileHandle.fileHandleWithStandardError writeData:data];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.stderrText appendString:text];
            if (weakSelf.stderrText.length > 16000) {
                [weakSelf.stderrText deleteCharactersInRange:NSMakeRange(0, weakSelf.stderrText.length - 16000)];
            }
        });
    };

    process.terminationHandler = ^(NSTask *task) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.terminating || weakSelf.serverLoaded) return;
            NSString *details = [weakSelf.stderrText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            [weakSelf showFatalError:details.length > 0 ? details : @"The Alas Python service stopped before it became ready."];
        });
    };

    if (![process launchAndReturnError:error]) return NO;
    self.backendProcess = process;
    setpgid(process.processIdentifier, process.processIdentifier);
    [self startCaffeinateWatching:process.processIdentifier];
    return YES;
}

- (void)startCaffeinateWatching:(pid_t)processID {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/caffeinate"];
    task.arguments = @[@"-s", @"-w", @(processID).stringValue];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        self.caffeinateProcess = task;
    } else {
        NSLog(@"Unable to start caffeinate: %@", error.localizedDescription);
    }
}

- (void)waitForServerOnPort:(NSInteger)port attemptsRemaining:(NSInteger)attempts {
    if (attempts <= 0) {
        [self showFatalError:[NSString stringWithFormat:@"Timed out waiting for Alas on port %ld.\n\n%@", (long)port, self.stderrText]];
        return;
    }

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/", (long)port]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 1;
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.terminating) return;
            if (response) {
                weakSelf.serverLoaded = YES;
                weakSelf.serverURL = url;
                [weakSelf.webView loadRequest:[NSURLRequest requestWithURL:url]];
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf waitForServerOnPort:port attemptsRemaining:attempts - 1];
            });
        });
    }] resume];
}

- (void)stopBackend {
    self.stderrPipe.fileHandleForReading.readabilityHandler = nil;
    if (self.caffeinateProcess.running) [self.caffeinateProcess terminate];
    self.caffeinateProcess = nil;

    if (self.backendProcess.running) {
        if (kill(-self.backendProcess.processIdentifier, SIGTERM) != 0) {
            [self.backendProcess terminate];
        }
    }
    self.backendProcess = nil;
}

- (void)showLoadingPage:(NSString *)message {
    NSString *html = [NSString stringWithFormat:
        @"<!doctype html><meta charset='utf-8'><style>body{margin:0;display:grid;place-items:center;height:100vh;background:#f5f7fa;color:#445;font:16px -apple-system,sans-serif}</style><div>%@</div>",
        message];
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)showFatalError:(NSString *)message {
    [self showLoadingPage:@"Alas could not start"];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = @"Alas could not start";
    alert.informativeText = message ?: @"Unknown error";
    [alert addButtonWithTitle:@"Quit"];
    [alert runModal];
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        AlasAppDelegate *delegate = [[AlasAppDelegate alloc] init];
        if (argc == 2 && strcmp(argv[1], "--resolve-root") == 0) {
            NSError *error = nil;
            NSURL *root = [delegate resolveAlasRoot:&error];
            if (!root) {
                fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
                return 1;
            }
            printf("%s\n", root.path.UTF8String);
            return 0;
        }

        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
