#import "SVNwrapper.h"
#import "SyntaxColouring.h"
#import <Cocoa/Cocoa.h>

@interface SVNBlame : NSWindowController <SVNdelegate> {
	NSMutableArray			*data;
	NSString				*filename;
	IBOutlet NSTableView	*table;
	ref_ptr<SVNcontext>		svn;
	SyntaxColouring			*syntax_colouring;
}

@property(retain) IBOutlet NSMutableArray	*data;
@property(retain) IBOutlet NSString			*filename;

-(void)svn_blame:(NSString*)path fromRevision:(SVNrevision)rev_start toRevision:(SVNrevision)rev_end;

@end
