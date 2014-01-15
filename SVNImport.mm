#import "SVNImport.h"
#import "SVNProgress.h"
#import "main.h"

//------------------------------------------------------------------------------
//	SVNimport
//------------------------------------------------------------------------------

@implementation SVNImport

-(id)init {
	if (self = [self initWithWindowNibName:@"SVNImport"]) {
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNImport"];
		[self setLogo];
		svn	= new SVNcontext;
	}
	return self;
}

-(void)dealloc {
	[super dealloc];
	[paths release];
}

-(void)windowDidLoad {
    [super windowDidLoad];
	NSArray *array = [SVNService getLRU:@"repository"];
	[repo addItemsWithObjectValues:array];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

- (IBAction)ok_pressed:(id)sender {
	SVNProgress		*prog	= [[SVNProgress alloc] initWithTitle:@"Import"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		NSString	*dest	= [repo stringValue];
		NSString	*log	= [message stringValue];
		svn_error_t	*err	= 0;
		for (NSString *srce in paths) {
			NSString	*dest2 = [NSString stringWithFormat:@"%@/%@", dest, [srce lastPathComponent]];
			if ([srce isDir]) {
				if ((err = svn->MakeDir(prog, dest2, log)))
					break;
				if ((err  = svn->Checkout(prog, dest2, srce)))
					break;
					
				NSError	*error = nil;
				for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:srce error:&error]) {
					if ([file hasPrefix:@"."])
						continue;
					if ((err = svn->Add(prog, [srce stringByAppendingPathComponent:file])))
						break;
				}
			}
//			if ((err = svn->Import(prog, srce, [NSString stringWithFormat:@"%@/%@", dest, [srce lastPathComponent]], log)))
//				break;
		}
		[prog finishedWithError:err];
	});
	[self close];
}

- (IBAction)cancel_pressed:(id)sender {
	[self close];
}

-(void)svn_import:(NSArray*)_paths {
	paths = [_paths retain];
}

@end
