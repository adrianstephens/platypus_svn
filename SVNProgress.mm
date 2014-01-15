#import "SVNProgress.h"
#import "SVNLog.h"
#import "SVNEditor.h"
#import "SyntaxColouring.h"	//just for rgb8

const char *plural(int n) { return n == 1 ? "" : "s"; }

NSString *GetTime(NSTimeInterval time) {
	unsigned	t		= unsigned(time);
	unsigned	secs	= t % 60;
	unsigned	mins	= (t / 60) % 60;
	unsigned	hrs		= t / 3600;
	
	NSString	*res	= @"";
	if (hrs)
		res = [res stringByAppendingFormat:@"%u hour%s", hrs, plural(hrs)];
	if (mins)
		res = [res stringByAppendingFormat:@"%s%u minute%s", hrs ? ", " : "", mins, plural(mins)];
	if (secs || t == 0)
		res = [res stringByAppendingFormat:@"%s%u second%s", hrs || mins ? " and " : "", secs, plural(secs)];
	return res;
}

NSString *GetMemory(apr_off_t bytes) {
	static const char *unit_names[] = {"bytes", "kBytes", "MBytes", "GBytes", "TBytes"};
	int	units = 0;
	while (bytes >> ((units + 1) * 10))
		units++;
	float	disp	= units ? float(bytes >> ((units - 1) * 10)) / 1024 : float(bytes);
		
	return [NSString stringWithFormat:@"%.2f %s", disp, unit_names[units]];
}

//------------------------------------------------------------------------------
//	SVNprogress
//------------------------------------------------------------------------------

@implementation SVNProgress
@synthesize data;
@synthesize cancelled;
@synthesize title;
@synthesize status;

-(id)initWithWindow:(NSWindow*)window {
	if (self = [super initWithWindow:window]) {
		data		= [NSMutableArray new];
		cancelled	= false;
		finished	= false;
		start_time	= [NSDate timeIntervalSinceReferenceDate];
		prog_time	= start_time;
		svn			= new SVNcontext;
	}
	return self;
}

-(id)initWithTitle:(NSString*)init_title {
	if (self = [super initWithWindowNibName:@"SVNProgress"]) {
		self.title	= init_title;
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNProgress"];
		[self setLogo];
	}
	return self;
}

-(void)dealloc {
	[status release];
	[data release];
	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

NSPoint TopLeft(NSScrollView *scroll) {
	return NSMakePoint(
		0,
		[[scroll documentView] isFlipped]
			? NSMaxY([[scroll documentView] frame]) - NSHeight([[scroll contentView] bounds])
			: 0
	);
}
bool CanScroll(NSScrollView *scroll) {
	return NSHeight([[scroll documentView] frame]) > NSHeight([[scroll contentView] bounds]);
}

-(void)add:(id)value {
	float	pos		= [[scroll verticalScroller] floatValue];
	bool	test	= pos == 0 && !CanScroll(scroll);

	[self willChangeValueForKey:@"data"];
	[self.data addObject:value];
	[self didChangeValueForKey:@"data"];

	if (pos == 1 || (test && CanScroll(scroll)))
		[[scroll documentView] scrollPoint:TopLeft(scroll)];
}

-(void)addentry:(NSString*)action path:(NSString*)path {
	[self performSelectorOnMainThread:@selector(add:)
		withObject:@{
			@"action": action,
			@"path": path,
			@"colour": [NSColor blackColor]
		}
		waitUntilDone:NO
	];
}
-(void)addentry:(NSString*)action path:(NSString*)path colour:(NSColor*)colour {
	[self performSelectorOnMainThread:@selector(add:)
		withObject:@{
			@"action": action,
			@"path": path,
			@"colour": colour
		}
		waitUntilDone:NO
	];
}
-(void)addentry:(NSString*)action path:(NSString*)path type:(NSString*)type colour:(NSColor*)colour {
	[self performSelectorOnMainThread:@selector(add:) withObject:@{
		@"action": action, @"path": path, @"type": type, @"colour": colour
	} waitUntilDone:NO];
}

-(void)addentry:(NSString*)action {
	[self performSelectorOnMainThread:@selector(add:)
		withObject:@{
			@"action": action,
			@"colour": [NSColor blackColor]
		}
		waitUntilDone:NO
	];
}

-(IBAction)cancel:(id)sender {
	if (finished) {
		[self close];
	} else {
		cancelled = true;
	}
}

-(void)finishedWithError:(svn_error_t*)err {
	finished		= true;
	button.title	= @"Close";
	if (err) {
		[self performSelectorOnMainThread:@selector(setStatus:) withObject:
			SVNcontext::GetErrorMessage(err)
			waitUntilDone:NO
		];
		while ((err = err->child)) {
			[self performSelectorOnMainThread:@selector(add:) withObject:@{
				@"colour":	[NSColor redColor],
				@"action":	@"error",
				@"path":	[NSString stringWithUTF8String:err->message],
			} waitUntilDone:NO];
		}
	} else {
		[self performSelectorOnMainThread:@selector(setStatus:) withObject:
			[GetMemory(transferred) stringByAppendingFormat:@" transferred in %@", GetTime([NSDate timeIntervalSinceReferenceDate] - start_time)]
			waitUntilDone:NO
		];
	}
}

//------------------------------------------------------------------------------
//	actions on paths
//------------------------------------------------------------------------------
-(NSString*)get_selection1 {
	NSDictionary *entry = [data objectAtIndex:[table clickedRow]];
	return [entry valueForKey:@"path"];
}
-(NSArray*)get_selection {
	return [NSArray arrayWithObject:[self get_selection1]];
}

- (IBAction)compare:(id)sender {
	NSString *local	= [self get_selection1];
	NSString *repos	= [NSTemporaryDirectory() stringByAppendingPathComponent:[local lastPathComponent]];

	svn_client_info2_t	*info;
	if (svn_error_t *err = svn->GetInfo(local, SVNrevision::head(), &info)) {
		svn->LogErrorMessage(err);
		return;
	}
	NSString			*url	= [NSString stringWithUTF8String:info->URL];
	svn->GetFile(SVNstreamFILE([repos UTF8String]), url, SVNrevision::head());
#if 0
	NSString *command = [[NSUserDefaults standardUserDefaults] stringForKey:@"diff_command"];
	[NSTask launchedTaskWithLaunchPath:command arguments:[NSArray arrayWithObjects:local, repos, nil]];
#else
	[[SVNEditor new] diff:local base:repos];
#endif
}
- (IBAction)show_log:(id)sender {
	[[[SVNLog alloc] init] svn_log:[self get_selection]];
}
- (IBAction)open:(id)sender {
	[[NSWorkspace sharedWorkspace] openFile:[self get_selection1]];
}
- (IBAction)open_with:(id)sender {
	NSString	*fn = [self get_selection1];
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
		[NSArray arrayWithObject: [NSURL fileURLWithPath: [self get_selection1]]]
	];
}
-(IBAction)copy_path:(id)sender {
	NSPasteboard	*pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:[NSArray arrayWithObject:[self get_selection1]]];
}

//------------------------------------------------------------------------------
//	NSMenuDelegate
//------------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu*)menu {
	NSString	*path	= [self get_selection1];
	[[menu itemWithTitle:@"Open with"] setSubmenu:[self openWithFor:path]];
 }
 
//------------------------------------------------------------------------------
//	SVN delegate
//------------------------------------------------------------------------------

-(void)SVNnotify:(const svn_wc_notify_t*)notify pool:(apr_pool_t*)pool {
	static crgb8
		col_conflict(255,0,0),
		col_add		(128,0,128),
		col_modified(0,0,128),
		col_deleted	(128,0,0),
		col_merge	(0,128,0);
		
	crgb8		col(0, 0, 0);
	NSString	*action = nil;
	NSString	*path	= [NSString stringWithUTF8String:notify->path];

	if (notify->content_state == svn_wc_notify_state_conflicted || notify->prop_state == svn_wc_notify_state_conflicted) {
		col		= col_conflict;
		action	= @"Conflicted";
		num_conflicts++;
	} else switch (notify->action) {
		case svn_wc_notify_update_shadowed_add:
		case svn_wc_notify_add:
		case svn_wc_notify_update_add:
			col		= col_add;
			action	= @"Added";
			break;
		case svn_wc_notify_commit_added:
		case svn_wc_notify_commit_copied:
			col		= col_add;
			action	= @"Adding";
			break;
		case svn_wc_notify_copy:
			action	= @"Copied";
			break;
		case svn_wc_notify_commit_modified:
			col		= col_modified;
			action	= @"Modified";
			break;
		case svn_wc_notify_update_shadowed_delete:
		case svn_wc_notify_delete:
		case svn_wc_notify_update_delete:
		case svn_wc_notify_exclude:
			action	= @"Deleted";
			col		= col_deleted;
			break;
		case svn_wc_notify_commit_deleted:
		case svn_wc_notify_update_external_removed:
			action	= @"Deleting";
			col		= col_deleted;
			break;
		case svn_wc_notify_restore:
			action	= @"Restored";
			break;
		case svn_wc_notify_revert:
			action	= @"Reverted";
			break;
		case svn_wc_notify_resolved:
			action	= @"Resolved";
			break;
		case svn_wc_notify_update_replace:
		case svn_wc_notify_commit_copied_replaced:
		case svn_wc_notify_commit_replaced:
			action	= @"Replacing";
			col		= col_deleted;
			break;
		case svn_wc_notify_exists:
			if (notify->content_state == svn_wc_notify_state_merged || notify->prop_state == svn_wc_notify_state_merged) {
				col		= col_merge;
				action	= @"Merged";
			} else {
				action	= @"Versioned";
			}
			break;
		case svn_wc_notify_update_started:
			action	= @"Updating";
			break;
		case svn_wc_notify_update_shadowed_update:
		case svn_wc_notify_merge_record_info:
		case svn_wc_notify_update_update:
			if (notify->kind == svn_node_dir && (
				notify->prop_state == svn_wc_notify_state_inapplicable
			||	notify->prop_state == svn_wc_notify_state_unknown
			||	notify->prop_state == svn_wc_notify_state_unchanged
			))
			break;
			if (notify->content_state == svn_wc_notify_state_merged || notify->prop_state == svn_wc_notify_state_merged) {
				col		= col_merge;
				action	= @"Merged";
			} else if (notify->content_state == svn_wc_notify_state_changed || notify->prop_state == svn_wc_notify_state_changed) {
				action	= @"Updated";
			} else {
				break;
			}
			if (notify->lock_state == svn_wc_notify_lock_state_unlocked)
				action	= [NSString stringWithFormat:@"%@, Unlocked", action];
			break;

		case svn_wc_notify_update_external:
			action	= @"External";
			break;

		case svn_wc_notify_merge_completed:
		case svn_wc_notify_update_completed:
			action	= @"Completed";
			path	= [NSString stringWithFormat:@"%s at revision: %li", notify->path, notify->revision];
			if (num_conflicts) {
			}
			break;
		case svn_wc_notify_commit_postfix_txdelta:
			action	= @"Sending content";
			break;
		case svn_wc_notify_failed_revert:
			action	= @"Failed revert";
			col		= col_conflict;
			break;
		case svn_wc_notify_status_completed:
		case svn_wc_notify_status_external:
			action	= @"Status";
			break;
		case svn_wc_notify_skip:
			if (notify->content_state == svn_wc_notify_state_missing) {
				action	= @"Skipped missing target";
				col		= col_conflict;
			} else {
				action	= @"Skipped";
				if (notify->content_state == svn_wc_notify_state_obstructed)
					col= col_conflict;
			}
			break;
		case svn_wc_notify_update_skip_working_only:
			action	= @"Skipped, no versioned parent";
			col		= col_conflict;
			num_conflicts++;
			break;
		case svn_wc_notify_locked:
			if (notify->lock && notify->lock->owner)
				action	= [NSString stringWithFormat:@"%@%s", @"Locked by ", notify->lock->owner];
			break;
		case svn_wc_notify_unlocked:
			action	= @"Unlocked";
			break;
		case svn_wc_notify_failed_lock:
			action	= @"Lock failed";
			col		= col_conflict;
			break;
		case svn_wc_notify_failed_unlock:
			action	= @"Unlock failed";
			col		= col_conflict;
			break;
		case svn_wc_notify_changelist_set:
			action	= [NSString stringWithFormat:@"Assigned to changelist '%s'", notify->changelist_name];
			break;
		case svn_wc_notify_changelist_clear:
			action	= @"Removed from changelist";
			break;
		case svn_wc_notify_changelist_moved:
			action	= [NSString stringWithFormat:@"Changelist '%s' moved", notify->changelist_name];
			break;
		case svn_wc_notify_foreign_merge_begin:
		case svn_wc_notify_merge_begin:
			if (svn_merge_range_t *range = notify->merge_range) {
				if (range->start == range->end || range->start == range->end - 1)
					action = [NSString stringWithFormat:@"Merging r%ld", range->end];
				else if (range->start - 1 == range->end)
					action = [NSString stringWithFormat:@"Reverse merging r%ld", range->start];
				else if (range->start < range->end)
					action = [NSString stringWithFormat:@"Merging r%ld through r%ld", range->start + 1, range->end];
				else
					action = [NSString stringWithFormat:@"Reverse merging r%ld through r%ld", range->start, range->end + 1];
			} else {
				action	= @"Merging differences between repository URLs";
			}
			break;
		case svn_wc_notify_property_added:
		case svn_wc_notify_property_modified:
		case svn_wc_notify_revprop_set:
			action = [NSString stringWithFormat:@"Property '%s' set", notify->prop_name];
			break;
		case svn_wc_notify_property_deleted:
		case svn_wc_notify_property_deleted_nonexistent:
		case svn_wc_notify_revprop_deleted:
			action = [NSString stringWithFormat:@"Property '%s' deleted", notify->prop_name];
			break;
		case svn_wc_notify_update_skip_obstruction:
			action	= @"Skipped obstructing working copy";
			col		= col_conflict;
			num_conflicts++;
			break;
		case svn_wc_notify_tree_conflict:
			action	= @"Tree conflict";
			col		= col_conflict;
			num_conflicts++;
			break;
		case svn_wc_notify_failed_external:
			action	= @"External failed";
			col		= col_conflict;
			break;
		case svn_wc_notify_merge_record_info_begin:
			if (svn_merge_range_t *range = notify->merge_range) {
				if (range->start == range->end || range->start == range->end)
					action = [NSString stringWithFormat:@"Recording mergeinfo for merge of r%ld", range->end];
				else if (range->start - 1 == range->end)
					action = [NSString stringWithFormat:@"Recording mergeinfo for reverse merge of r%ld", range->start];
				else if (range->start < range->end)
					action = [NSString stringWithFormat:@"Recording mergeinfo for merge of r%ld through r%ld", range->start + 1, range->end];
				else
					action = [NSString stringWithFormat:@"Recording mergeinfo for reverse merge of r%ld through r%ld", range->start, range->end + 1];
			} else {
				action	= @"Recording mergeinfo for merge between URLs";
			}
			break;
		case svn_wc_notify_merge_elide_info:
			action	= @"Eliding mergeinfo";
			break;
		case svn_wc_notify_url_redirect:
			action	= @"Redirecting to url";
//			path	= url.GetUIPathString();
			break;
		case svn_wc_notify_path_nonexistent:
			action	= @"Not under version control";
			col		= col_conflict;
			num_conflicts++;
			break;
		case svn_wc_notify_update_skip_access_denied:
			action	= @"Skipped, access denied";
			col		= col_conflict;
			num_conflicts++;
			break;
		case svn_wc_notify_skip_conflicted:
			action	= @"Skipped, remains conflicted";
			col		= col_conflict;
			num_conflicts++;
			break;
/*		case svn_wc_notify_update_broken_lock:
			action	= @"Lock broken";
			break;
		case svn_wc_notify_left_local_modifications:
			action	= @"Left local modifications";
			break;
*/		case svn_wc_notify_upgraded_path:
		case svn_wc_notify_failed_conflict:
		case svn_wc_notify_failed_missing:
		case svn_wc_notify_failed_out_of_date:
		case svn_wc_notify_failed_no_parent:
		case svn_wc_notify_failed_locked:
		case svn_wc_notify_failed_forbidden_by_server:
//		case svn_wc_notify_failed_obstruction:
//		case svn_wc_notify_conflict_resolver_starting:
//		case svn_wc_notify_conflict_resolver_done:
		default:
			break;
    }
	
	if (action)
		[self addentry:action path:path type:(notify->mime_type ? [NSString stringWithUTF8String:notify->mime_type] : @"") colour:col];
	
	for (svn_error_t *err = notify->err; err; err = err->child)
		[self addentry:@"Error" path:[NSString stringWithUTF8String:err->message] colour:[NSColor colorWithDeviceRed:1 green:0 blue:0 alpha:1]];
}

-(void)SVNprogress:(apr_off_t)progress total:(apr_off_t)total pool:(apr_pool_t*)pool {
	transferred	= progress;
	
	NSTimeInterval	time = [NSDate timeIntervalSinceReferenceDate];
	if (time - prog_time < 0.5)
		return;

	prog_time = time;
	
	if (total == -1)
		self.status = [GetMemory(progress) stringByAppendingString:@" transferred"];
	else
		self.status = [NSString stringWithFormat:@"%@ transferred, out of %@", GetMemory(progress), GetMemory(total)];
}

-(svn_error_t*)SVNcancel {
	return cancelled
		? svn_error_create(SVN_ERR_CANCELLED, NULL, "User Cancelled Action.")
		: SVN_NO_ERROR;
}

@end

