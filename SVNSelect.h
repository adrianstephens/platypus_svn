#import "ui.h"

@interface SVNSelect : SVNWindowController {
	IBOutlet NSTableView	*table;
	IBOutlet NSString		*message;
	NSString				*status;
	NSString				*title;
	NSMutableArray			*data;
	ref_ptr<SVNcontext>		svn;
}

@property(retain) IBOutlet NSMutableArray	*data;
@property(retain) IBOutlet NSString			*status;
@property(retain) IBOutlet NSString			*title;

-(id)initWithTitle:(NSString*)init_title;
-(void)getFiles:(NSArray*)paths all:(bool)all;
-(NSArray*)getSelected;
-(NSArray*)getSelectedPaths;

@end
