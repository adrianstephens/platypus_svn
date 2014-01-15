#import "ui.h"

//------------------------------------------------------------------------------
//	SVNlogUI
//------------------------------------------------------------------------------

@interface SVNLog : SVNWindowController {
	NSMutableArray			*data;
	NSString				*status;
	NSArray					*paths;
	NSTimeInterval			prog_time;
	int						depth;
	int						num_revisions;
	svn_revnum_t			min_revision, max_revision;
	NSDate					*min_date, *max_date;
	IBOutlet NSSplitView	*splitter;
	IBOutlet NSTableView	*log_table;
	IBOutlet NSTableView	*paths_table;
	IBOutlet NSDate			*date_from;
	IBOutlet NSDate			*date_to;
	ref_ptr<SVNcontext>		svn;
}

@property(retain) IBOutlet	NSMutableArray	*data;
@property(retain) IBOutlet	NSString		*status;
@property(retain)			NSArray			*paths;
@property(retain)			NSDate			*date_from;
@property(retain)			NSDate			*date_to;

-(void)svn_log:(NSArray*)_paths;
-(void)svn_log:(NSArray*)_paths fromRevision:(SVNrevision)from;

@end
