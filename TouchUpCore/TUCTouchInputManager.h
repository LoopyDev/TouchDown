//
//  TUCTouchInputManager.h
//  Touch Up Core
//
//  Created by Sebastian Hueber on 03.02.23.
//

#import <AppKit/AppKit.h>
#import <TouchUpCore/TUCTouchInputManager-C.h>
#import <TouchUpCore/TUCTouchDelegate.h>
#import <TouchUpCore/TUCTouch.h>

NS_ASSUME_NONNULL_BEGIN



@interface TUCTouchInputManager : NSObject

@property (weak, nonatomic) id<TUCTouchDelegate> delegate;

@property (strong, atomic) NSMutableSet<TUCTouch *> *touchSet;

/**
 Allows to deactiate that the framework processes touches to post them as mouse events.
 The default value is YES.
 */
@property BOOL postMouseEvents;


/**
 The maximal distance in mm that two taps may be apart from each other to count as double click
 */
@property CGFloat doubleClickTolerance;

/**
 How long the finger has to rest inside `touchSlop` before moving for the movement to be a
 holdAndDrag instead of a drag. Moving off sooner is a drag (by default a scroll). At 0, every
 movement is a holdAndDrag. The default value is 0.08 s.
 */
@property NSTimeInterval holdDuration;

/**
 Radius in mm around the point where a finger landed within which it doesn't count as moving.
 Leaving it cancels a tap and starts a drag or holdAndDrag; wobble inside it is ignored.
 The default value is 1.5 mm.
 */
@property CGFloat touchSlop;

/**
 The maximum distance in mm a touch may travel between two reports while still counting as
 stationary, which sets each touch's `phase`. Once a finger has left `touchSlop`, it also
 decides when a drag pauses.
 */
@property CGFloat stationaryThreshold;

/**
 Width in points of a border along each screen edge in which the cursor is never posted.
 Touches inside this border are pushed inwards to its inner edge. The default value is 0 (off).
 */
@property CGFloat edgeDeadZone;

/**
 If a touch is no longer reported by the screen, wait for this number of incoming reports bevore deleting it from the touch set.
 */
@property NSInteger errorResistance;


/**
 If a touchscreen sometimes sends invalid touch data at location (0,0), activate this option to ignore them
 */
@property BOOL ignoreOriginTouches;

/**
 When YES, the pointer goes back to where it was before the touch once the touch is over.
 Consecutive touches return to where the pointer was before the first one. If the mouse is moved
 meanwhile, it is left alone. The default value is NO.
 */
@property BOOL returnsPointerAfterTouch;

/**
 What `returnsPointerAfterTouch` does after a swipe that is still coasting. NO returns right
 away and stops the coasting; YES lets the scroll finish first, since coasting scrolls whatever
 is under the pointer. The default value is NO.
 */
@property BOOL pointerReturnWaitsForScroll;


- (void)start;

- (void)stop;


/**
 Opt-in exclusive access. When YES, connected touchscreens are seized so macOS and other
 apps no longer receive their events — Touch Up becomes the sole handler. Default is NO.
 Applies immediately to currently-connected devices and  future connections.
 */
- (void)setTouchscreensSeized:(BOOL)seized;



- (CGPoint)convertScreenPointRelativeToAbsolute:(CGPoint)relativePoint locationID:(uint32_t)locationID;

/**
 Maps a raw, normalised digitizer point to a relative screen point, applying the given
 calibration instead of the delegate's. Lets a calibration UI preview a candidate transform.
 */
- (CGPoint)convertDigitizerPoint:(CGPoint)digitizerPoint toRelativeScreenPointWithCalibration:(CGAffineTransform)calibration locationID:(uint32_t)locationID NS_SWIFT_NAME(relativeScreenPoint(forDigitizerPoint:calibration:locationID:));

/**
 The inverse of the (uncalibrated) mapping: which raw digitizer point a perfectly
 calibrated digitizer would report for a given relative screen point.
 */
- (CGPoint)convertRelativeScreenPointToUncalibratedDigitizerPoint:(CGPoint)screenPoint locationID:(uint32_t)locationID NS_SWIFT_NAME(digitizerPoint(forRelativeScreenPoint:locationID:));


- (void)triggerSystemAccessibilityAccessAlert;

@end

NS_ASSUME_NONNULL_END
