#import "ui.h"

@interface SVNEditor : NSWindowController {
	NSViewController	*vc;
}
-(void)open:(NSString*)path;
-(void)diff:(NSString*)path base:(NSString*)base;
@end

