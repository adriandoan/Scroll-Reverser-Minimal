// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import "MouseTap.h"
#import "CoreFoundation/CoreFoundation.h"
#import <AppKit/AppKit.h>
#import <mach/mach_time.h>
#import "IOKitSPI.h"
#import "CoreGraphicsSPI.h"

// Hardcoded behavior: reverse mouse scrolling only (vertical), leave trackpad alone.
static const BOOL kReverseMouse = YES;
static const BOOL kReverseTrackpad = NO;
static const BOOL kReverseVertical = YES;
static const BOOL kReverseHorizontal = NO;

#define MILLISECOND ((uint64_t)1000000)

static ScrollPhase _momentumPhaseForEvent(CGEventRef event)
{
    switch ([[NSEvent eventWithCGEvent:event] momentumPhase]) {
        case NSTouchPhaseBegan:
            return ScrollPhaseStart;
        case NSTouchPhaseStationary:
            return ScrollPhaseMomentum;
        case NSTouchPhaseEnded:
        case NSTouchPhaseCancelled:
            return ScrollPhaseEnd;
        default:
            return ScrollPhaseNormal;
    }
}

static uint64_t _nanoseconds(void)
{
    static mach_timebase_info_data_t info={0};
    if (info.denom==0) {
        mach_timebase_info(&info);
    }
    uint64_t time = mach_absolute_time();
    time *= info.numer;
    time /= info.denom;
    return * (uint64_t *) &time;
}

static CGEventRef _callback(CGEventTapProxy proxy,
                           CGEventType type,
                           CGEventRef eventRef,
                           void *userInfo)
{
    @autoreleasepool
    {
        MouseTap *const tap=(__bridge MouseTap *)userInfo;
        const uint64_t time=_nanoseconds();
        NSEvent *const event=[NSEvent eventWithCGEvent:eventRef];

        if (type==(CGEventType)NSEventTypeGesture)
        {
            const NSUInteger touching=[[event touchesMatchingPhase:NSTouchPhaseTouching inView:nil] count];
            if (touching>=2) {
                tap->lastTouchTime=time;
                tap->touching=MAX(tap->touching, touching);
            }
            else {
                return eventRef;
            }
        }
        else if (type==(CGEventType)NSEventTypeScrollWheel)
        {
            const BOOL continuous=!!CGEventGetIntegerValueField(eventRef, kCGScrollWheelEventIsContinuous);

            const int64_t axis1=CGEventGetIntegerValueField(eventRef, kCGScrollWheelEventDeltaAxis1);
            const int64_t axis2=CGEventGetIntegerValueField(eventRef, kCGScrollWheelEventDeltaAxis2);
            const int64_t point_axis1=CGEventGetIntegerValueField(eventRef, kCGScrollWheelEventPointDeltaAxis1);
            const int64_t point_axis2=CGEventGetIntegerValueField(eventRef, kCGScrollWheelEventPointDeltaAxis2);
            const double fixedpt_axis1=CGEventGetDoubleValueField(eventRef, kCGScrollWheelEventFixedPtDeltaAxis1);
            const double fixedpt_axis2=CGEventGetDoubleValueField(eventRef, kCGScrollWheelEventFixedPtDeltaAxis2);

            IOHIDEventRef const ioHidEventRef=CGEventCopyIOHIDEvent(eventRef);
            IOHIDFloat iohid_axis1=0;
            IOHIDFloat iohid_axis2=0;
            if (ioHidEventRef) {
                iohid_axis1=IOHIDEventGetFloatValue(ioHidEventRef, kIOHIDEventFieldScrollY);
                iohid_axis2=IOHIDEventGetFloatValue(ioHidEventRef, kIOHIDEventFieldScrollX);
            }

            const uint64_t touchElapsed=(time-tap->lastTouchTime);
            const NSUInteger touching=tap->touching;
            tap->touching=0;
            const ScrollPhase phase=_momentumPhaseForEvent(eventRef);

            const ScrollEventSource source=(^{
                if (!continuous) {
                    return ScrollEventSourceMouse;
                }
                if (touching>=2 && touchElapsed<(MILLISECOND*222)) {
                    return ScrollEventSourceTrackpad;
                }
                if (phase==ScrollPhaseNormal && touchElapsed>(MILLISECOND*333)) {
                    return ScrollEventSourceMouse;
                }
                return tap->lastSource;
            })();
            tap->lastSource=source;

            const BOOL invert = (source==ScrollEventSourceTrackpad) ? kReverseTrackpad : kReverseMouse;

            const NSInteger vmul=(invert&&kReverseVertical)?-1:1;
            const NSInteger hmul=(invert&&kReverseHorizontal)?-1:1;

            if (vmul!=1) {
                CGEventSetIntegerValueField(eventRef, kCGScrollWheelEventDeltaAxis1, axis1*vmul);
                CGEventSetDoubleValueField(eventRef, kCGScrollWheelEventFixedPtDeltaAxis1, fixedpt_axis1*vmul);
                CGEventSetIntegerValueField(eventRef, kCGScrollWheelEventPointDeltaAxis1, point_axis1*vmul);
                if (ioHidEventRef) {
                    IOHIDEventSetFloatValue(ioHidEventRef, kIOHIDEventFieldScrollY, iohid_axis1*vmul);
                }
            }
            if (hmul!=1) {
                CGEventSetIntegerValueField(eventRef, kCGScrollWheelEventDeltaAxis2, axis2*hmul);
                CGEventSetDoubleValueField(eventRef, kCGScrollWheelEventFixedPtDeltaAxis2, fixedpt_axis2*hmul);
                CGEventSetIntegerValueField(eventRef, kCGScrollWheelEventPointDeltaAxis2, point_axis2*hmul);
                if (ioHidEventRef) {
                    IOHIDEventSetFloatValue(ioHidEventRef, kIOHIDEventFieldScrollX, iohid_axis2*hmul);
                }
            }

            if (ioHidEventRef) {
                CFRelease(ioHidEventRef);
            }
        }
        else
        {
            [tap enableTap];
        }
    }

    return eventRef;
}

@interface MouseTap ()
@property CFMachPortRef activeTapPort;
@property CFRunLoopSourceRef activeTapSource;
@property CFMachPortRef passiveTapPort;
@property CFRunLoopSourceRef passiveTapSource;
@end

@implementation MouseTap

- (void)setActive:(BOOL)state
{
    if (state) {
        [self start];
    }
    else {
        [self stop];
    }
}

- (BOOL)isActive
{
    return self.activeTapSource&&self.passiveTapSource&&self.activeTapPort&&self.passiveTapPort;
}

- (void)start
{
    if([self isActive])
        return;

    touching=0;
    lastTouchTime=0;
    lastSource=0;

    self.passiveTapPort=(CFMachPortRef)CGEventTapCreate(kCGSessionEventTap,
                                                   kCGTailAppendEventTap,
                                                   kCGEventTapOptionListenOnly,
                                                   NSEventMaskGesture,
                                                   _callback,
                                                   (__bridge void *)(self));

    self.activeTapPort=(CFMachPortRef)CGEventTapCreate(kCGSessionEventTap,
                                           kCGTailAppendEventTap,
                                           kCGEventTapOptionDefault,
                                           NSEventMaskScrollWheel,
                                           _callback,
                                           (__bridge void *)(self));

    if (self.passiveTapPort && self.activeTapPort) {
        self.passiveTapSource = (CFRunLoopSourceRef)CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.passiveTapPort, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), self.passiveTapSource, kCFRunLoopCommonModes);
        self.activeTapSource = (CFRunLoopSourceRef)CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.activeTapPort, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), self.activeTapSource, kCFRunLoopCommonModes);
        NSLog(@"Scroll Reverser tap started");
    }
    else {
        NSLog(@"Scroll Reverser tap failed to start - check Accessibility permissions");
        [self stop];
    }
}

- (void)stop
{
    if (self.activeTapSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), self.activeTapSource, kCFRunLoopCommonModes);
        CFRelease(self.activeTapSource);
        self.activeTapSource=nil;
    }
    if (self.activeTapPort) {
        CFMachPortInvalidate(self.activeTapPort);
        CFRelease(self.activeTapPort);
        self.activeTapPort=nil;
    }
    if (self.passiveTapSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), self.passiveTapSource, kCFRunLoopCommonModes);
        CFRelease(self.passiveTapSource);
        self.passiveTapSource=nil;
    }
    if (self.passiveTapPort) {
        CFMachPortInvalidate(self.passiveTapPort);
        CFRelease(self.passiveTapPort);
        self.passiveTapPort=nil;
    }
}

- (void)enableTap
{
    if (self.activeTapPort&&!CGEventTapIsEnabled(self.activeTapPort)) {
        CGEventTapEnable(self.activeTapPort, YES);
    }
    if (self.passiveTapPort&&!CGEventTapIsEnabled(self.passiveTapPort)) {
        CGEventTapEnable(self.passiveTapPort, YES);
    }
}

@end
