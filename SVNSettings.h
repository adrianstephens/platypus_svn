#import "ui.h"

@interface SVNSettings : NSWindowController<MyRuleEditorDelegate, SVNdelegate> {
	APRpool		pool;
	Criterion	*criteria, *dummy;
	Criterion	*crit_misc, *crit_autoprops, *crit_global, *crit_general;
	NSInteger	current_row;
	bool		interactive;
	
	IBOutlet MyRuleEditor	*rules;
}

+(SVNSettings*)new;

@end
