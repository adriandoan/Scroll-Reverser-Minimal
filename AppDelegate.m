// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import "AppDelegate.h"
#import "MouseTap.h"

@interface AppDelegate ()
@property MouseTap *tap;
@property NSTimer *permissionsRetryTimer;
@end

@implementation AppDelegate

+ (void)terminateOthers
{
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if (![app isEqual:[NSRunningApplication currentApplication]]) {
            if ([[app.bundleIdentifier lowercaseString] isEqualToString:[[NSRunningApplication currentApplication].bundleIdentifier lowercaseString]]) {
                [app terminate];
            }
        }
    }
}

- (instancetype)init
{
    self=[super init];
    if (self) {
        [[self class] terminateOthers];
        self.tap=[[MouseTap alloc] init];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self ensurePermissionsAndStart];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(appDidWake:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
}

- (void)ensurePermissionsAndStart
{
    NSDictionary *opts=@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    BOOL trusted=AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

    if (trusted) {
        self.tap.active=YES;
        return;
    }

    NSLog(@"Waiting for Accessibility permission...");
    self.permissionsRetryTimer=[NSTimer scheduledTimerWithTimeInterval:1.0
                                                               repeats:YES
                                                                 block:^(NSTimer *t) {
        if (AXIsProcessTrustedWithOptions(NULL)) {
            [t invalidate];
            self.permissionsRetryTimer=nil;
            self.tap.active=YES;
            NSLog(@"Accessibility granted - tap activated");
        }
    }];
}

/* On wake from sleep, macOS sometimes stops delivering events to our tap. Relaunch. */
- (void)appDidWake:(NSNotification *)note
{
    NSLog(@"OS woke from sleep - relaunching");
    NSWorkspaceOpenConfiguration *config = [[NSWorkspaceOpenConfiguration alloc] init];
    config.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSBundle mainBundle].bundleURL
                                          configuration:config
                                      completionHandler:nil];
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

@end
