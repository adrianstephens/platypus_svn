#import "ui.h"

@interface SVNImport : SVNWindowController {
@public
	ref_ptr<SVNcontext>		svn;
	IBOutlet NSComboBox		*repo;
	IBOutlet NSTextField	*message;
	NSArray					*paths;
}

-(void)svn_import:(NSArray*)_paths;

@end

