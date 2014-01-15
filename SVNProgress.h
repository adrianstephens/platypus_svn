#import "ui.h"

@interface SVNProgress : SVNWindowController {
	IBOutlet NSScrollView	*scroll;
	IBOutlet NSTableView	*table;
	NSMutableArray			*data;
	NSString				*status;
	bool					cancelled;
	IBOutlet NSButton		*button;

	NSString				*title;
	NSTimeInterval			start_time, prog_time;
	apr_off_t				transferred;
	bool					finished;
	int						num_conflicts;
@public
	ref_ptr<SVNcontext>		svn;
}

@property(retain) IBOutlet NSMutableArray	*data;
@property(retain) IBOutlet NSString			*status;
@property(retain) IBOutlet NSString			*title;
@property bool cancelled;

-(id)initWithTitle:(NSString*)init_title;
-(void)addentry:(NSString*)action path:(NSString*)path;
-(void)addentry:(NSString*)action path:(NSString*)path colour:(NSColor*)colour;
-(void)addentry:(NSString*)action path:(NSString*)path type:(NSString*)type colour:(NSColor*)colour;
-(void)addentry:(NSString*)action;
-(void)finishedWithError:(svn_error_t*)err;

@end
