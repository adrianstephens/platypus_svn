#import <Cocoa/Cocoa.h>

@interface SVNAuthorise : NSWindowController {
@public
	NSString	*username;
	NSString	*password;
	NSString	*realm;
	NSConditionLock		*lock;
	bool		ok;
}

-(void)runWithRealm:(NSString*)_realm username:(NSString*)_username;
-(void)waitUntilDone;

@end
