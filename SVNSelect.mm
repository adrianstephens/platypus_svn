#import "SVNSelect.h"
#import "SVNProgress.h"
#import "SVNLog.h"
#import "SVNProperties.h"
#import "SVNBlame.h"
#import "SVNEditor.h"
#import <Cocoa/Cocoa.h>

//------------------------------------------------------------------------------
//	SVNSelect
//------------------------------------------------------------------------------

@implementation SVNSelect
@synthesize data;
@synthesize status;
@synthesize title;

-(id)initWithWindow:(NSWindow*)window {
	if (self = [super initWithWindow:window]) {
		data	= [NSMutableArray new];
		svn		= new SVNcontext;
	}
	return self;
}
-(id)initWithTitle:(NSString*)init_title {
	if (self = [self initWithWindowNibName:@"SVNSelect"]) {
		self.title	= init_title;
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNSelect"];
		[self setLogo];
	}
	return self;
}

-(void)dealloc {
	[data release];
	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

-(void)add:(id)value {
	[self willChangeValueForKey:@"data"];
	[self.data addObject:value];
	[self didChangeValueForKey:@"data"];
}

-(IBAction)cancel_pressed:(id)sender {
	[self close];
}

-(void)getFiles:(NSArray*)paths all:(bool)all {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),	^ {
		for (NSString *path in paths) {
			if (svn_error_t *err = svn->GetStatus(self, path, SVNrevision::head(), svn_depth_infinity, all))
				self.status = svn->GetErrorMessage(err);
		}
	});
}

-(NSArray*)getSelected {
	int				n			= [data count];
	NSMutableArray	*selected	= [NSMutableArray arrayWithCapacity:n];
	for (NSDictionary *info in data) {
		if ([[info valueForKey:@"selected"] boolValue])
			[selected addObject:info];
	}
	return selected;
}

-(NSArray*)getSelectedPaths {
	int				n			= [data count];
	NSMutableArray	*selected	= [NSMutableArray arrayWithCapacity:n];
	for (NSDictionary *info in data) {
		if ([[info valueForKey:@"selected"] boolValue])
			[selected addObject:((SVNClientStatus*)[info valueForKey:@"status"])->path];
	}
	return selected;
}
//------------------------------------------------------------------------------
//	actions on paths
//------------------------------------------------------------------------------

-(SVNClientStatus*)get_selection {
	NSDictionary *entry = [data objectAtIndex:[table clickedRow]];
	return [entry valueForKey:@"status"];
}
-(NSString*)get_selected_path {
	return [self get_selection]->path;
}

- (IBAction)compare:(id)sender {
	NSString *local = [self get_selected_path];
	NSString *repos	= [NSTemporaryDirectory() stringByAppendingPathComponent:[local lastPathComponent]];

	svn_client_info2_t	*info;
	svn_error_t			*err	= svn->GetInfo(local, SVNrevision::head(), &info);
	if (!err) {
		NSString	*url	= [NSString stringWithUTF8String:info->URL];
		if (!(err = svn->GetFile(SVNstreamFILE([repos UTF8String]), url, SVNrevision::head()))) {
		#if 0
			NSString *command = [[NSUserDefaults standardUserDefaults] stringForKey:@"diff_command"];
			[NSTask launchedTaskWithLaunchPath:command arguments:[NSArray arrayWithObjects:local, repos, nil]];
		#else
			[[SVNEditor new] diff:local base:repos];
		#endif
		}
		return;
	}
	svn->LogErrorMessage(err);
}
- (IBAction)revert:(id)sender {
	svn_error_t *err = svn->Revert(self, [NSArray arrayWithObject:[self get_selected_path]]);
	if (!err) {
		[data removeObjectAtIndex:[table clickedRow]];
	}
}
- (IBAction)log:(id)sender {
	[[[SVNLog alloc] init] svn_log:[NSArray arrayWithObject:[self get_selected_path]]];
}
- (IBAction)blame:(id)sender {
	[[[SVNBlame alloc] init] svn_blame:[self get_selected_path] fromRevision:1 toRevision:SVNrevision::head()];
}
- (IBAction)open:(id)sender {
	[[NSWorkspace sharedWorkspace] openFile:[self get_selected_path]];
}
- (IBAction)open_with:(id)sender {
	NSString	*fn = [self get_selected_path];
	if (NSString *app = [sender representedObject]) {
		[[NSWorkspace sharedWorkspace] openFile:fn withApplication:app];
	} else {
		[self chooseApplication:^(NSURL *app) {
			[[NSWorkspace sharedWorkspace] openFile:fn withApplication:[app path]];
		}];
	}
}
- (IBAction)finder:(id)sender {
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:
		[NSArray arrayWithObject: [NSURL fileURLWithPath: [self get_selected_path]]]
	];
}
- (IBAction)show_props:(id)sender {
	NSString *local = [self get_selected_path];
	[[[SVNProperties alloc] init] svn_props:local];
}
- (IBAction)copy_paths:(id)sender {
	NSPasteboard	*pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:[NSArray arrayWithObject:[self get_selected_path]]];
}
- (IBAction)copy_all:(id)sender {
	SVNClientStatus	*stat	= [self get_selection];
	NSPasteboard	*pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:[NSArray arrayWithObjects:
		stat.path,
		stat.lock,
		stat.text_status,
		stat.prop_status,
		nil
	]];
}
- (IBAction)copy_column:(id)sender {
	NSPasteboard	*pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:[NSArray arrayWithObject:[self get_selected_path]]];
}

//------------------------------------------------------------------------------
//	NSMenuDelegate
//------------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu*)menu {
	NSString	*path	= [self get_selected_path];
	[[menu itemWithTitle:@"Open with"] setSubmenu:[self openWithFor:path]];
 }

@end

