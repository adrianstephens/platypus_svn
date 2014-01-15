#import "ui.h"

@interface SVNProperties : NSWindowController<MyRuleEditorDelegate, SVNdelegate> {
	Criterion				*criteria, *root;
	NSArray					*save_paths;
	NSMutableArray			*properties;
	NSInteger				current_row;
	bool					interactive;

	IBOutlet MyRuleEditor	*rules;
	ref_ptr<SVNcontext>		svn;
}

+(void)getCriteria:(Criterion*)c isDir:(bool)dir;

-(void)svn_props:(NSString*)path;
-(void)svn_props:(NSString*)path atRevision:(SVNrevision)revision;
-(void)svn_props_multi:(NSArray*)paths;
-(void)svn_props_multi:(NSArray*)paths atRevision:(SVNrevision)revision;
-(void)svn_revprops:(NSString*)repo atRevision:(SVNrevision)revision;

@end
