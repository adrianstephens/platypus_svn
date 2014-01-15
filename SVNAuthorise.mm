#import "SVNAuthorise.h"

@implementation SVNAuthorise

-(id)init {
	if (self = [super initWithWindowNibName:@"SVNAuthorise"]) {
		lock	= [[NSConditionLock alloc] initWithCondition:0];
	}
	return self;
}

-(void)runWithRealm:(NSString*)_realm username:(NSString*)_username {
	username	= [_username retain];
	password	= [NSString new];
	realm		= [_realm retain];
	[lock lock];
	[self window];
}

- (void)windowDidLoad {
    [super windowDidLoad];
}

-(void)dealloc {
	[username release];
	[password release];
	[realm release];
	
	[lock unlock];
	[lock release];

	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[lock unlockWithCondition:1];
//	[self release];
}

- (IBAction)cancel:(id)sender {
	[self close];
}

- (IBAction)ok:(id)sender {
	ok = true;
	[self close];
}

-(void)waitUntilDone {
	[lock lockWhenCondition:1];
}

@end
