#import "SVNwrapper.h"
#import <Cocoa/Cocoa.h>

//------------------------------------------------------------------------------
//	SVNWindowController
//------------------------------------------------------------------------------

@interface SVNWindowController : NSWindowController <SVNdelegate>
-(NSMenu*)openWithFor:(NSString*)path;
-(void)chooseApplication:(void(^)(NSURL *app))handler;
-(void)setLogo;
@end

//------------------------------------------------------------------------------
//	Criterion
//------------------------------------------------------------------------------
@interface Criterion : NSObject {
@public
	NSString		*name;
	NSMutableArray	*children;
}
@property(readwrite, copy) NSString *name;
+(id)criterion;
+(id)criterionWithName:(NSString*)name;
+(id)criterionWithName:(NSString*)name children:(id)children, ... NS_REQUIRES_NIL_TERMINATION;
+(id)boolCriterion;

-(void)addChild:(id)child;
-(NSUInteger)numberOfChildren;
-(id)childAtIndex:(NSUInteger)index;
-(id)displayValue:(id)data;
-(NSString*)output:(id)display after:(NSString*)input last:(bool)last;
-(bool)isComposite;
-(NSString*)matches:(NSString*)input;
@end

@interface SeparatorCriterion : Criterion
+(id)shared;
@end

@interface CompositeCriterion : Criterion {
@public
	NSString	*separators;
}
-(id)withSeparators:(NSString*)s;
@end

@interface TextFieldCriterion : Criterion
+(id)shared;
-(id)displayValue:(NSString*)input withWidth:(float)width;
@end

@interface MatchCriterion : Criterion
@end

@interface TokenFieldCriterion : TextFieldCriterion {
	float		width;
	NSString	*separators;
}
+(id)criterionWithName:(NSString*)name separators:(NSString*)separators width:(float)width children:(id)children, ... NS_REQUIRES_NIL_TERMINATION;
-(id)withWidth:(float)w;
-(id)withSeparators:(NSString*)s;
@end

//------------------------------------------------------------------------------
//	MyRuleEditor
//------------------------------------------------------------------------------

@interface MyRuleEditor : NSRuleEditor
-(int)getNewChildRow:(int)parent;
-(void)parse:(NSString*)value withCriteria:(Criterion*)criteria toParent:(NSInteger)parent;
-(NSString*)deparseRow:(int)row;
@end

@protocol MyRuleEditorDelegate <NSRuleEditorDelegate>
-(void)ruleEditor:(NSRuleEditor*)ruleeditor setParentRow:(NSInteger)parentRow;
@optional
-(void)ruleEditor:(NSRuleEditor*)ruleeditor removeRows:(NSIndexSet*)rowIndexes;
@end

//------------------------------------------------------------------------------
//	Misc. Custom Controls
//------------------------------------------------------------------------------

@interface PathCell : NSTextFieldCell
@end

@interface IconTextCell : PathCell {
	NSImage *icon;
}
@property(retain) NSImage *icon;
@end

@interface LabelledTextCell : NSTextFieldCell {
	NSCell	*label;
}
-(void)setLabel:(NSString*)s;
@end

@interface LabelledTextField : NSTextField
-(void)setLabel:(NSString*)s;
@end

//------------------------------------------------------------------------------
//	Alerts
//------------------------------------------------------------------------------

void SVNErrorAlert(NSWindow *window, svn_error_t *err);
void SVNErrorAlertMainThread(NSWindow *window, svn_error_t *err);
