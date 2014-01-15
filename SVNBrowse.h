#import "ui.h"

@interface SVNBrowse : SVNWindowController {
	IBOutlet NSOutlineView		*outline;
	IBOutlet NSTreeController	*tree_controller;
	IBOutlet NSTextField		*url_text;
	IBOutlet NSTextField		*rev_text;
	
	NSMutableArray			*data;
	NSString				*root;
	NSString				*drop_dest;
	NSArray					*drop_items;
	SVNrevision				revision;
	ref_ptr<SVNcontext>		svn;
	dispatch_queue_t		queue;
}

-(svn_error_t*)svn_browse:(NSString*)path;
-(void)setRevision:(SVNrevision)revision;

@end
