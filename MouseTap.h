// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import <Foundation/Foundation.h>

typedef enum {
    ScrollEventSourceMouse=0,
    ScrollEventSourceTrackpad,
    ScrollEventSourceMax
} ScrollEventSource;

typedef enum {
    ScrollPhaseStart=0,
    ScrollPhaseNormal,
    ScrollPhaseMomentum,
    ScrollPhaseEnd,
    ScrollPhaseMax
} ScrollPhase;

@interface MouseTap : NSObject {
@public
    NSUInteger touching;
    uint64_t lastTouchTime;
    ScrollEventSource lastSource;
}

@property (getter=isActive) BOOL active;
- (void)enableTap;

@end
