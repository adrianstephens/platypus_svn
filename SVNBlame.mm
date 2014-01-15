#import "SVNBlame.h"
#import "SVNLog.h"

@implementation SVNBlame
@synthesize data;
@synthesize filename;

-(id)init {
	if (self = [self initWithWindowNibName:@"SVNBlame"]) {
		data = [[NSMutableArray alloc] init];
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNBlame"];
		[self window];
		syntax_colouring = [SyntaxColouring new];
		svn	= new SVNcontext;
	}
	return self;
}

-(void)dealloc {
	[data release];
	[filename release];
	[syntax_colouring release];
	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

-(void)windowDidLoad {
    [super windowDidLoad];
	table.intercellSpacing = NSMakeSize(3, 0);
//	[[table.tableColumns objectAtIndex:3] setWidth:1000];
}

-(void)add:(id)value {
	[self willChangeValueForKey:@"data"];
	[data addObject:value];
	[self didChangeValueForKey:@"data"];
}

NSComparisonResult sorter(id obj1, id obj2, void *p) {
	unsigned long long	n1 = [[(NSDictionary*)obj1 objectForKey:@"revision"] unsignedLongLongValue],
						n2 = [[(NSDictionary*)obj2 objectForKey:@"revision"] unsignedLongLongValue];
	return n1 < n2 ? NSOrderedAscending : n1 > n2 ? NSOrderedDescending : NSOrderedSame;
}

-(void)set_ages:(id)dummy {
	NSMutableArray	*revs	= [NSMutableArray arrayWithCapacity:[data count]];
	for (NSDictionary *i in data)
		[revs addObject:i];
		
#if 0
	[revs sortUsingComparator:(NSComparator)^(id obj1, id obj2) {
		unsigned long long	n1 = [[(NSDictionary*)obj1 objectForKey:@"revision"] unsignedLongLongValue],
							n2 = [[(NSDictionary*)obj2 objectForKey:@"revision"] unsignedLongLongValue];
		return n1 < n2 ? NSOrderedAscending : n1 > n2 ? NSOrderedDescending : NSOrderedSame;
	}];
#else
	[revs sortUsingFunction:sorter context:NULL];
#endif
	unsigned long long	prev	= 0;
	int					unique	= -1;
	for (NSDictionary *i in revs) {
		unsigned long long	rev = [[i objectForKey:@"revision"] unsignedLongLongValue];
		if (rev != prev) {
			prev = rev;
			unique++;
		}
	}

	float	scale	= 1.f / unique;
	prev			= 0;
	unique			= -1;
	[self willChangeValueForKey:@"data"];
	for (NSDictionary *i in revs) {
		unsigned long long	rev = [[i objectForKey:@"revision"] unsignedLongLongValue];
		if (rev != prev) {
			prev = rev;
			unique++;
		}
		int	index = [[i objectForKey:@"lineno"] intValue];
		NSMutableDictionary	*info = [NSMutableDictionary dictionaryWithDictionary:[data objectAtIndex:index]];
		[info setObject:[NSNumber numberWithFloat:unique * scale] forKey:@"age"];
		[data setObject:info atIndexedSubscript:index];
	}
	[self didChangeValueForKey:@"data"];
}

-(void)svn_blame:(NSString*)path fromRevision:(SVNrevision)rev_start toRevision:(SVNrevision)rev_end {
	[[self window] setRepresentedFilename:path];
	self.filename	= path;
	dispatch_async(
		dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),	^ {
			if (svn_error_t *err = svn->Blame(self, path, rev_start, rev_end))
				svn->LogErrorMessage(err);
			[self performSelectorOnMainThread:@selector(set_ages:) withObject:nil waitUntilDone:YES];
		}
	);
}

//------------------------------------------------------------------------------
//	context menu actions
//------------------------------------------------------------------------------

- (IBAction)copylog:(id)sender {
	NSDictionary *entry = [data objectAtIndex:[table clickedRow]];
	NSPasteboard *pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:[NSArray arrayWithObject:[entry valueForKey:@"log"]]];
}
- (IBAction)blame_previous:(id)sender {
	NSDictionary *entry = [data objectAtIndex:[table clickedRow]];
	[[SVNBlame new] svn_blame:filename fromRevision:1 toRevision:--SVNrevision([entry valueForKey:@"revision"])];
}
- (IBAction)show_changes:(id)sender {
	NSDictionary	*entry		= [data objectAtIndex:[table clickedRow]];
	svn_revnum_t	revision2	= [[entry valueForKey:@"revision"] unsignedLongLongValue];
	svn_revnum_t	revision1	= revision2 - 1;

	NSString *fn	= [NSTemporaryDirectory() stringByAppendingPathComponent:[filename lastPathComponent]];

#if 0
	NSString *fn1	= [NSString stringWithFormat:@"%@-rev%@", fn, [NSNumber numberWithLongLong:revision1]];
	NSString *fn2	= [NSString stringWithFormat:@"%@-rev%@", fn, [NSNumber numberWithLongLong:revision2]];

	svn->GetFile(SVNstreamFILE([fn1 UTF8String]), filename, revision1);
	svn->GetFile(SVNstreamFILE([fn2 UTF8String]), filename, revision2);

	NSString *command = [[NSUserDefaults standardUserDefaults] stringForKey:@"diff_command"];
	[NSTask launchedTaskWithLaunchPath:command arguments:[NSArray arrayWithObjects:fn1, fn2, nil]];
#else
	svn->GetDiffs(fn, filename, revision1, filename, revision2);
#endif

}
- (IBAction)show_log:(id)sender {
	NSDictionary *entry = [data objectAtIndex:[table clickedRow]];
	[[[SVNLog alloc] init] svn_log:[NSArray arrayWithObject:filename] fromRevision:[entry valueForKey:@"revision"]];
}

-(void)tableView:(NSTableView*)tv willDisplayCell:(NSTextFieldCell*)cell forTableColumn:(NSTableColumn*)col row:(NSInteger)row {
	if ([[col identifier] isEqualToString:@"revision"]) {
		float	x = [[[data objectAtIndex:row] objectForKey:@"age"] floatValue];
		x = 1 - x / 2;
		[cell setBackgroundColor:[NSColor colorWithDeviceRed:x green:x blue:x alpha:1]];
	}
}
//------------------------------------------------------------------------------
//	SVN delegate
//------------------------------------------------------------------------------

-(svn_error_t*)SVNblame:(const SVN_blame_info&)blame_info pool:(apr_pool_t*)pool {
	NSMutableAttributedString	*line = [syntax_colouring process:blame_info.line];
	
	[self performSelectorOnMainThread:@selector(add:)
		withObject:@{
			@"revision":	[NSNumber numberWithUnsignedLongLong:blame_info.revision],
			@"author":		[NSString stringWithSVNString:blame_info.props.get("svn:author")],
			@"log":			[NSString stringWithSVNString:blame_info.props.get("svn:log")],
			@"lineno":		[NSNumber numberWithUnsignedInt:blame_info.line_no],
			@"line":		line
		}
		waitUntilDone:NO
	];
	return 0;
}

@end
