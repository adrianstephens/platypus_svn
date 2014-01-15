#import "SVNLog.h"
#import "SVNProgress.h"
#import "SVNProperties.h"
#import "SVNBlame.h"
#import "SVNBrowse.h"
#import "SVNEditor.h"
#import "date.h"

//------------------------------------------------------------------------------
//	SVNChangedPaths
//------------------------------------------------------------------------------

@interface SVNChangedPaths : NSObject {
@public
	NSString		*path;
	NSString		*copyfrom_path;
	svn_revnum_t	copyfrom_rev;
	char			action;
	svn_tristate_t	text_modified, props_modified;
}

-(NSString*)path;
-(NSString*)action;
-(NSString*)copyfrom_path;
-(NSNumber*)copyfrom_rev;
@end

@implementation SVNChangedPaths
+(SVNChangedPaths*)createWithPath:(const char*)path andCStruct:(const svn_log_changed_path2_t*)s {
	return [[SVNChangedPaths alloc] initWithPath:path andCStruct:s];
}
-(SVNChangedPaths*)initWithPath:(const char*)_path andCStruct:(const svn_log_changed_path2_t*)s {
	self			= [super init];
	path			= [[NSString stringWithUTF8String:_path] retain];
	copyfrom_path	= s->copyfrom_path	? [[NSString stringWithUTF8String:s->copyfrom_path]	retain] : nil;
	copyfrom_rev	= s->copyfrom_rev;
	action			= s->action;
	text_modified	= s->text_modified;
	props_modified	= s->props_modified;
	return self;
}
-(void)dealloc {
	if (path)
		[path release];
	if (copyfrom_path)
		[copyfrom_path release];
	[super dealloc];
}
-(NSString*)path			{ return path; }
-(NSString*)copyfrom_path	{ return copyfrom_path; }
-(NSNumber*)copyfrom_rev	{ return copyfrom_rev < 0 ? nil : [NSNumber numberWithUnsignedLongLong:copyfrom_rev]; }
-(NSString*)action			{
//	[NSString stringWithFormat:@"%c", action]; }
	switch (action) {
		case 'A': return @"Added";
		case 'M': return @"Modified";
		case 'D': return @"Deleted";
		case 'R': return @"Replaced";
		default: return nil;
	}
}

@end

//------------------------------------------------------------------------------
//	SVNLog
//------------------------------------------------------------------------------

@implementation SVNLog
@synthesize data;
@synthesize status;
@synthesize paths;
@synthesize date_from;
@synthesize date_to;

-(id)init {
	if (self = [self initWithWindowNibName:@"SVNLog"]) {
		data			= [[NSMutableArray alloc] init];
		prog_time		= [NSDate timeIntervalSinceReferenceDate];
		min_date		= [NSDate distantFuture];
		max_date		= [NSDate distantPast];
		self.date_from	= [NSDate date];
		self.date_to	= [NSDate date];

		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNLog"];
		[self setLogo];
		svn	= new SVNcontext;
	}
	return self;
}

-(void)windowDidLoad {
    [super windowDidLoad];
	[splitter setAutosaveName: @"logsplit"];
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

-(void)update_status {
	[self performSelectorOnMainThread:@selector(setStatus:) withObject:
		[NSString stringWithFormat:@"Showing %i revisions, from %li to %li",
			num_revisions, min_revision, max_revision
		]
		waitUntilDone:NO
	];
}

//------------------------------------------------------------------------------
//	buttons
//------------------------------------------------------------------------------

-(IBAction)ok:(id)sender {
	[self close];
}

-(IBAction)showall:(id)sender {
	dispatch_async(
		dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),	^ {
			APRarray<SVNrevisionrange*>	revs;
			SVNrevisionrange	range(SVNrevision(min_revision - 1), SVNrevision::start());
			revs.push_back(&range);
			svn_error_t	*err = svn->GetLog(self, paths, revs, 0);
			if (err) {
				self.status = svn->GetErrorMessage(err);
			} else {
				[self update_status];
			}
		}
	);
}

-(IBAction)next100:(id)sender {
	dispatch_async(
		dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),	^ {
			APRarray<SVNrevisionrange*>	revs;
			SVNrevisionrange	range(SVNrevision(min_revision - 1), SVNrevision::start());
			revs.push_back(&range);
			svn_error_t	*err = svn->GetLog(self, paths, revs, 100);
			if (err) {
				self.status = svn->GetErrorMessage(err);
			} else {
				[self update_status];
			}
		}
	);
}


-(void)svn_log:(NSArray*)_paths fromRevision:(SVNrevision)from {
	self.paths	= _paths;

	dispatch_async(
		dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),	^ {
			APRarray<SVNrevisionrange*>	revs;
			SVNrevisionrange	range(from, SVNrevision::start());
			revs.push_back(&range);
			svn_error_t	*err = svn->GetLog(self, _paths, revs, 100);
			if (err) {
				[self performSelectorOnMainThread:@selector(setStatus:) withObject:svn->GetErrorMessage(err) waitUntilDone:NO];
			} else {
				[self update_status];
				[self performSelectorOnMainThread:@selector(setDate_from:) withObject:min_date waitUntilDone:NO];
				[self performSelectorOnMainThread:@selector(setDate_to:) withObject:max_date waitUntilDone:NO];
			}
		}
	);
}

-(void)svn_log:(NSArray*)_paths {
	[self svn_log:_paths fromRevision:SVNrevision::head()];
}

//------------------------------------------------------------------------------
//	actions on log
//------------------------------------------------------------------------------

- (IBAction)browse:(id)sender {
	NSDictionary	*log		= [data objectAtIndex:[log_table selectedRow]];
	svn_revnum_t	revision	= [(NSNumber*)[log valueForKey:@"revision"] unsignedLongLongValue];
	SVNBrowse		*browse		= [SVNBrowse new];
	[browse setRevision:revision];
	[browse svn_browse:[paths objectAtIndex:0]];
}
- (IBAction)edit_author:(id)sender {
	NSInteger	row = [log_table clickedRow];
	[log_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[log_table editColumn:2 row:row withEvent:nil select:FALSE];
}
- (IBAction)edit_log:(id)sender {
	NSInteger	row = [log_table clickedRow];
	[log_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[log_table editColumn:4 row:row withEvent:nil select:FALSE];
}
- (IBAction)log_props:(id)sender {
	NSDictionary	*log		= [data objectAtIndex:[log_table selectedRow]];
	svn_revnum_t	revision	= [(NSNumber*)[log valueForKey:@"revision"] unsignedLongLongValue];
	svn_client_info2_t *info;
	if (svn_error_t *err = svn->GetInfo([paths objectAtIndex:0], revision, &info))
		svn->LogErrorMessage(err);
	else
		[[SVNProperties new] svn_revprops:[NSString stringWithUTF8String:info->repos_root_URL] atRevision:revision];
}

//------------------------------------------------------------------------------
//	actions on paths
//------------------------------------------------------------------------------
static svn_error_t *last_err;

-(SVNChangedPaths*)get_change:(svn_revnum_t*)revision {
	NSDictionary *log = [data objectAtIndex:[log_table selectedRow]];
	if (revision)
		*revision = [(NSNumber*)[log valueForKey:@"revision"] unsignedLongLongValue];
	return [[log valueForKey:@"paths"] objectAtIndex:[paths_table clickedRow]];
}
-(NSString*)URLof:(NSString*)path atRevision:(svn_revnum_t)revision {
	NSString			*temp	= [paths objectAtIndex:0];
	if ([temp characterAtIndex:0] == '/')
		temp = svn->GetWCRoot(temp);

	svn_client_info2_t	*info;
	if (svn_error_t *err = svn->GetInfo(temp, revision, &info)) {
		svn->LogErrorMessage(last_err = err);
		return nil;
	}
	return [NSString stringWithFormat:@"%s%@", info->repos_root_URL, path];
}

//p4merge [options] left right
//	p4merge [options] [base] left right
//	p4merge [options] [base] left right [merge]

-(IBAction)show_changes:(id)sender {
	svn_revnum_t		revision2;
	SVNChangedPaths		*change	= [self get_change:&revision2];

	NSString *url	= [self URLof:change->path atRevision:revision2];
	if (!url) {
		SVNErrorAlert(self.window, last_err);
		return;
	}

	NSString *fn	= [NSTemporaryDirectory() stringByAppendingPathComponent:[change->path lastPathComponent]];
	NSString *base	= [fn stringByDeletingPathExtension];
	NSString *ext	= [fn pathExtension];
	NSString *fn2	= [[NSString stringWithFormat:@"%@-rev%@", base, [NSNumber numberWithLongLong:revision2]] stringByAppendingPathExtension:ext];

	if (change->action == 'A') {
		if (svn_error_t *err = svn->GetFile(SVNstreamFILE([fn2 UTF8String]), url, revision2)) {
			SVNErrorAlert(self.window, err);
			return;
		}
		[[SVNEditor new] open:fn2];
	} else {
		svn_revnum_t	revision1 = revision2 - 1;
		NSString		*fn1	= [[NSString stringWithFormat:@"%@-rev%@", base, [NSNumber numberWithLongLong:revision1]] stringByAppendingPathExtension:ext];

		svn_error_t *err;
		if ((err = svn->GetFile(SVNstreamFILE([fn1 UTF8String]), url, revision1))
		||	(err = svn->GetFile(SVNstreamFILE([fn2 UTF8String]), url, revision2))
		) {
			SVNErrorAlert(self.window, err);
			return;
		}
	#if 0
		NSString *command = [[NSUserDefaults standardUserDefaults] stringForKey:@"diff_command"];
		[NSTask launchedTaskWithLaunchPath:command arguments:[NSArray arrayWithObjects:fn1, fn2, nil]];
	#else
		[[SVNEditor new] diff:fn2 base:fn1];
	#endif
	}
}

//-(IBAction)blame_changes:(id)sender {
//}
-(IBAction)show_changes_unified:(id)sender {
	svn_revnum_t		revision1, revision2;
	SVNChangedPaths		*change	= [self get_change:&revision2];
	revision1 = revision2 - 1;
	NSString	*temp	= [NSTemporaryDirectory() stringByAppendingPathComponent:[change->path lastPathComponent]];
	NSString	*url	= [self URLof:change->path atRevision:revision1];
	if (svn_error_t *err = svn->GetDiffs(temp, url, revision1, url, revision2))
		svn->LogErrorMessage(err);
	else
		[[SVNEditor new] open:temp];
}
-(IBAction)open:(id)sender {
	svn_revnum_t	revision;
	SVNChangedPaths	*change	= [self get_change:&revision];
	NSString *url	= [self URLof:change->path atRevision:revision];
	NSString *fn	= [NSTemporaryDirectory() stringByAppendingPathComponent:[change->path lastPathComponent]];
	svn->GetFile(SVNstreamFILE([fn UTF8String]), url, revision);
	[[NSWorkspace sharedWorkspace] openFile:fn];
}

-(IBAction)open_with:(NSMenuItem*)sender {
	svn_revnum_t	revision;
	SVNChangedPaths	*change	= [self get_change:&revision];
	NSString		*url	= [self URLof:change->path atRevision:revision];
	NSString		*fn		= [NSTemporaryDirectory() stringByAppendingPathComponent:[change->path lastPathComponent]];
	
	if (NSString *app = [sender representedObject]) {
		if (svn_error_t *err = svn->GetFile(SVNstreamFILE([fn UTF8String]), url, revision))
			SVNErrorAlert(self.window, err);
		else
			[[NSWorkspace sharedWorkspace] openFile:fn withApplication:app];
	} else {
		[self chooseApplication:^(NSURL *app) {
			if (svn_error_t *err = svn->GetFile(SVNstreamFILE([fn UTF8String]), url, revision))
				SVNErrorAlert(self.window, err);
			else
				[[NSWorkspace sharedWorkspace] openFile:fn withApplication:[app path]];
		}];
	}
}
-(IBAction)blame:(id)sender {
	svn_revnum_t	revision;
	SVNChangedPaths	*change	= [self get_change:&revision];
	NSString *url	= [self URLof:change->path atRevision:revision];
	[[SVNBlame new] svn_blame:url fromRevision:1 toRevision:revision];
}
-(IBAction)revert:(id)sender {
	svn_revnum_t	revision;
	SVNChangedPaths	*change	= [self get_change:&revision];
	--revision;
	NSString *url	= [self URLof:change->path atRevision:revision];
	NSString *fn	= change->path;
	if (svn_error_t *err = svn->GetFile(SVNstreamFILE([fn UTF8String]), url, revision))
		svn->LogErrorMessage(err);
}
-(IBAction)show_props:(id)sender {
	svn_revnum_t	revision;
	SVNChangedPaths	*change	= [self get_change:&revision];
	[[SVNProperties new] svn_props:[self URLof:change->path atRevision:revision] atRevision:revision];
}
-(IBAction)show_log:(id)sender {
	svn_revnum_t		revision;
	SVNChangedPaths		*change	= [self get_change:&revision];
	NSString			*path	= [self URLof:change->path atRevision:revision];
	[[SVNLog new] svn_log:[NSArray arrayWithObject:path] fromRevision:revision];
}
//-(IBAction)merge_logs:(id)sender {
//}
-(IBAction)save:(id)sender {
	svn_revnum_t	revision;
	SVNChangedPaths	*change	= [self get_change:&revision];
	if (change->action == 'D')
		--revision;
	
	NSSavePanel	*dlg	= [NSSavePanel savePanel];
	[dlg setNameFieldStringValue:[change->path lastPathComponent]];

	if ([dlg runModal] == NSOKButton) {
		NSURL		*output = [dlg URL];
		NSString	*url	= [self URLof:change->path atRevision:revision];
		svn_error_t	*err	= svn->GetFile(SVNstreamFILE([[output path] UTF8String]), url, revision);
		if (err)
			SVNErrorAlert(self.window, err);

	}
}
//-(IBAction)export:(id)sender {
//}

//------------------------------------------------------------------------------
//	NSMenuDelegate
//------------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu*)menu {
	NSString	*path	= [self get_change:NULL]->path;
	[[menu itemWithTitle:@"Open with"] setSubmenu:[self openWithFor:path]];
 }

//------------------------------------------------------------------------------
//	SVN delegate
//------------------------------------------------------------------------------

-(svn_error_t*)SVNlog:(svn_log_entry_t*)log_entry pool:(apr_pool_t*)pool {
	if (log_entry->revision == SVN_INVALID_REVNUM) {
		depth--;
		return 0;
	}
	if (max_revision == 0)
		max_revision = min_revision = log_entry->revision;
	else if (log_entry->revision > max_revision)
		max_revision = log_entry->revision;
	else if (log_entry->revision < min_revision)
		min_revision = log_entry->revision;
	num_revisions++;
	
	NSTimeInterval	time = [NSDate timeIntervalSinceReferenceDate];
	if (time - prog_time > 0.25) {
		prog_time = time;
		[self update_status];
	}
	
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	[info setValue:[NSNumber numberWithUnsignedLongLong:log_entry->revision]	forKey:@"revision"];
	
	APRhash		props(log_entry->revprops);
	for (APRhash::iterator i = props.begin(); i != props.end(); ++i) {
		const char		*key	= i.key();
		const char		*value	= ((svn_string_t*)*i)->data;
		if (strcmp(key, "svn:date") == 0) {
			NSDate	*date	= [NSDate dateWithTimeIntervalSinceReferenceDate:DateTime::ISO_8601(value)];
			if ([date compare:min_date] == NSOrderedAscending)
				min_date = date;
			if ([date compare:max_date] == NSOrderedDescending)
				max_date = date;
			[info
				setValue:date
				forKey:[NSString stringWithUTF8String:key]
			];
		} else {
			[info
				setValue:[NSString stringWithUTF8String:value]
				forKey:[NSString stringWithUTF8String:key]
			];
		}
	}
	
	NSMutableArray *changed_paths = [[NSMutableArray alloc] init];
	int			action_bits = 0;
	if (log_entry->changed_paths2) {
		APRhash		changes(log_entry->changed_paths2);
		for (APRhash::iterator i = changes.begin(); i != changes.end(); ++i) {
			const char				*key	= i.key();
			svn_log_changed_path2_t	*value	= *i;
			switch (value->action) {
				case 'A': action_bits |= 1; break;
				case 'D': action_bits |= 2; break;
				case 'R': action_bits |= 4; break;
				case 'M': action_bits |= 8; break;
			};
			[changed_paths addObject:[SVNChangedPaths createWithPath:key andCStruct:value]];
		}
	}
	
	const static NSString	*actions[16] = {
		@"    ",	@"   A",	@"  D ",	@"  DA",
		@" R  ",	@" R A",	@" RD ",	@" RDA",
		@"M   ",	@"M  A",	@"M D ",	@"M DA",
		@"MR  ",	@"MR A",	@"MRD ",	@"MRDA",
	};
	[info setValue:actions[action_bits]	forKey:@"actions"];
	[info setValue:changed_paths		forKey:@"paths"];

	[self performSelectorOnMainThread:@selector(add:) withObject:info waitUntilDone:NO];

	if (log_entry->has_children)
		depth++;

	return 0;
}

@end
