//
//  AfloatHub.m
//  AfloatAgent

/*

Copyright © 2006, Emanuele Vulcano.

This file is part of Afloat.

    Afloat is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation; either version 2.1 of the License, or (at your option) any later version.

    Afloat is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License along with Afloat; if not, write to the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301  USA

*/

#import "../AfloatAgentCommunication.h"
#import "AfloatHub.h"
#import "AfloatLogging.h"

#import "AfloatAnimator.h"
#import "AfloatWindowAlphaAnimation.h"
#import "AfloatWindowFader.h"

@implementation AfloatHub

+ (id) sharedHub {
	static id me = nil;
	if (!me) me = [self new];
	
	return me;
}

- (id) init {
	if (self = [super init]) {
		windowData = [NSMutableDictionary new];
		[NSBundle loadNibNamed:@"Hub" owner:self];
		animating = NO;
		
		[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(respondToRollCall:) name:kAfloatRollCallNotification object:kAfloatDistributedObjectIdentifier];
	}
	
	return self;
}

- (void) respondToRollCall:(NSNotification*) notif {
	NSDictionary* info = [NSDictionary dictionaryWithObject:[[NSBundle mainBundle] bundleIdentifier] forKey:kAfloatApplicationBundleID];
	
	[[NSDistributedNotificationCenter defaultCenter] 
		postNotificationName:kAfloatAlreadyLoadedNotification object:kAfloatDistributedObjectIdentifier userInfo:info deliverImmediately:YES];
}

- (void) dealloc {
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	
	[windowData release];
	[super dealloc];
}

- (void) changedUserAlpha:(float) ua forWindow:(NSWindow*) wnd {
    AfloatLog(@"changedUserAlpha:%f forWindow:%@", ua, wnd);
    
    NSMutableDictionary* info = [self infoForWindow:wnd];
    
    if (ua >= 0.95)
        [info removeObjectForKey:kAfloatWindowFaderKey];
    else
        [info setObject:[[[AfloatWindowFader alloc] initForWindow:wnd] autorelease] forKey:kAfloatWindowFaderKey];
}

- (NSMutableDictionary*) infoForWindow:(id /* AfloatWindow */) wnd {
	if (wnd == windowBeingCleared)
		return temporaryCopyOfInfoOfWindowBeingCleared;
	
	id data = [windowData objectForKey:[NSValue valueWithNonretainedObject:wnd]];
	
	if (!data) {
		data = [NSMutableDictionary dictionary];
		[windowData setObject:data forKey:[NSValue valueWithNonretainedObject:wnd]];
	}
	
	return data;
}

- (void) clearInfoForWindow:(id) wnd {
	// The following ballet is done to create a deterministic order
	// in which we clear the info for a window.
	// All NSValue objects are removed LAST.
	// This allows objects that are dealloc'ing to access infoForWindow:
	// with meaningful content.
	// This mess is required to allow AfloatWindowFader to dealloc correctly.
	
	id oldWBC = windowBeingCleared;
	NSMutableDictionary* oldTCetcetc = temporaryCopyOfInfoOfWindowBeingCleared;
	
	// We make a temporary copy that retains all NSValue objects.
	// -infoForWindow: will return the copy while we clear, and nil after we return.
	windowBeingCleared = wnd;
	temporaryCopyOfInfoOfWindowBeingCleared = [NSMutableDictionary dictionaryWithDictionary:[windowData objectForKey:[NSValue valueWithNonretainedObject:wnd]]];
	NSEnumerator* enu = [[temporaryCopyOfInfoOfWindowBeingCleared allKeys] objectEnumerator];
	id key;
	
	while (key = [enu nextObject]) {
		if (![key isKindOfClass:[NSValue class]])
			[temporaryCopyOfInfoOfWindowBeingCleared removeObjectForKey:key];
	}
	
	// Clear the original data. This deallocs all non-NSValue objects.
	[windowData removeObjectForKey:[NSValue valueWithNonretainedObject:wnd]];
	
	// When the copy will be released by the autorel pool,
	// NSValue objects will be dealloc'd.
	
	windowBeingCleared = oldWBC;
	temporaryCopyOfInfoOfWindowBeingCleared = oldTCetcetc;
}

- (void) willRemoveWindow:(id) wnd {
	[self clearInfoForWindow:wnd];
}

- (id) focusedWindow {
	return focusedWindow;
}

- (void) setFocusedWindow:(id) wnd {
	if (wnd != focusedWindow) {
		[focusedWindow release];
		focusedWindow = [wnd retain];
	}
}

- (NSMenu*) afloatMenu {
	return menuWithModelItems;
}

- (IBAction) showAdjustEffectsPanel:(id) sender {
	// I could have connected it in IB;
	// but does Carbon support connections
	// as Cocoa does?
	// This way, a menu with action == showAdjustEffectsPanel:
	// can be intercepted and redirected to an appropriate
	// function/method/whatever by the impl.
	
	[adjustEffectsPanel makeKeyAndOrderFront:self];
}

#pragma mark ** Features **

- (IBAction) toggleKeepAfloat:(id) sender {
	id win = [self focusedWindow];
	if (!win) { NSBeep(); return; }
	
	if ([win alwaysOnTop]) {
		[win setAlwaysOnTop:NO];
		[win setAlphaValue:1.0];
	} else {
		[win setAlwaysOnTop:YES];
		[win setAlphaValue:[self mediumAlphaValue]];
	}
}

- (float) mediumAlphaValue {
	return 0.8;
}

- (float) adequateOverlayAlphaValue {
	return 0.4;
}

- (float) normalizedAlphaValueForValue:(float) val {
    if (val > 1.0) return 1.0;
    if (val < 0.1) return 0.1;
    
    return val;
}

- (IBAction) makeOpaque:(id) sender {
    [[self focusedWindow] setUserAlphaValue:1.0];
}

- (IBAction) makeMediumTransparency:(id) sender {
    [[self focusedWindow] setUserAlphaValue:[self mediumAlphaValue]];
}

- (IBAction) lessTransparent:(id) sender {
    float newVal = [[self focusedWindow] userAlphaValue] - 0.15;
    [[self focusedWindow] setUserAlphaValue:[self normalizedAlphaValueForValue:newVal]];
}

- (IBAction) moreTransparent:(id) sender {
    float newVal = [[self focusedWindow] userAlphaValue] + 0.15;
    [[self focusedWindow] setUserAlphaValue:[self normalizedAlphaValueForValue:newVal]];
}

- (void) fadeWindow:(id) window toAlpha:(float) alpha duration:(NSTimeInterval) duration {
	animating = YES;
	
    AfloatAnimator* ani = [[AfloatAnimator alloc] initWithApproximateDuration:duration];
	[ani addAnimation:[AfloatWindowAlphaAnimation animationForWindow:window fromAlpha:[window alphaValue] toAlpha:alpha]];
	[ani run];
	[ani release];

	animating = NO;
}

- (void) fadeWindow:(id) window toAlpha:(float) alpha {
	[self fadeWindow:window toAlpha:alpha duration:0.35];
}

- (void) fadeInWindow:(id) window {
	if ([window overlayWindow] && !temporarilyTrackingOverlays) return;
	if ([[[self infoForWindow:window] objectForKey:@"AfloatWindowIsFadedIn"] boolValue])
		return;	
	
	[[self infoForWindow:window] setObject:[NSNumber numberWithBool:YES] forKey:@"AfloatWindowIsFadedIn"];

	
	// AfloatLog(@"entered: %f", [[theEvent window] alphaValue]);
	
	[self fadeWindow:window toAlpha:1.0];
}

- (void) fadeOutWindow:(id) window {
	if (![[[self infoForWindow:window] objectForKey:@"AfloatWindowIsFadedIn"] boolValue])
		return;
	
	//AfloatLog(@"exited: %@", num);
	
	[self fadeWindow:window toAlpha:[window userAlphaValue]];
	[[self infoForWindow:window] removeObjectForKey:@"AfloatWindowIsFadedIn"];
}

- (IBAction) resetAllOverlays:(id) sender {
	NSEnumerator* enu = [[[AfloatImplementation sharedInstance] windows] objectEnumerator];
	id window;
	
	while (window = [enu nextObject]) {
		if (![window overlayWindow]) continue;
		
		[window setOverlayWindow:NO];
		[window setAlwaysOnTop:NO];
		[window setAlphaValue:1.0];
	}
}

- (void) beginTemporaryTrackingOfOverlays {
	temporarilyTrackingOverlays = YES;
	
	NSEnumerator* enu = [[[AfloatImplementation sharedInstance] windows] objectEnumerator];
	id wnd;
	
	while (wnd = [enu nextObject]) {
		if (![wnd overlayWindow])
			continue;
		
		[[self infoForWindow:wnd] setObject:[NSNumber numberWithBool:YES] forKey:@"AfloatIsTemporarilyTracked"];
		[wnd setOverlayWindow:NO];
	}
}

- (void) endTemporaryTrackingOfOverlays {
	if (!temporarilyTrackingOverlays) return;
	temporarilyTrackingOverlays = NO;
	
	NSEnumerator* enu = [[[AfloatImplementation sharedInstance] windows] objectEnumerator];
	id wnd;
	
	while (wnd = [enu nextObject]) {
		NSMutableDictionary* d = [self infoForWindow:wnd];
		if (![d objectForKey:@"AfloatIsTemporarilyTracked"])
			continue;
		
		[d removeObjectForKey:@"AfloatIsTemporarilyTracked"];
		[wnd setOverlayWindow:YES];
	}
}

- (BOOL) isTemporarilyTrackingOverlays {
	return temporarilyTrackingOverlays;
}

- (IBAction) toggleAlwaysOnTop:(id) sender {
	id w = [self focusedWindow];
	[w setAlwaysOnTop:![w alwaysOnTop]];
}

@end
