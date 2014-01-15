#import "ui.h"

//------------------------------------------------------------------------------
//	SVNWindowController
//------------------------------------------------------------------------------

@implementation SVNWindowController

-(NSMenu*)openWithFor:(NSString*)path {
	NSMenu		*menu	= [[[NSMenu alloc] initWithTitle:@"Open with"] autorelease];
	NSString	*uti	= [path getUTI];
	NSArray		*array	= (NSArray*)LSCopyAllRoleHandlersForContentType((CFStringRef)uti, kLSRolesAll);

	for (NSString *bundle_id in array) {
		if (NSString *path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundle_id]) {
			NSString	*name	= [[NSFileManager defaultManager] displayNameAtPath:path];
			NSImage		*icon	= [[NSWorkspace sharedWorkspace] iconForFile:path];
			NSMenuItem	*mi		= [[[NSMenuItem alloc] initWithTitle:name action:@selector(open_with:) keyEquivalent:@""] autorelease];
			[mi setImage:icon];
			[mi setRepresentedObject:path];
			[menu addItem:mi];
		}
	}

	if ([menu numberOfItems] == 0) {
		NSMenuItem	*mi	=[[NSMenuItem new] autorelease];
		[mi setTitle:@"<none>"];
		[mi setEnabled:NO];
		[menu addItem:mi];
	}
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[[[NSMenuItem alloc] initWithTitle:@"Other..." action:@selector(open_with:) keyEquivalent:@""] autorelease]];
	return menu;
}

-(void)chooseApplication:(void(^)(NSURL *app))handler {
	NSArray		*dirs	= [[NSFileManager defaultManager] URLsForDirectory:NSApplicationDirectory inDomains: NSLocalDomainMask];
	NSOpenPanel *dlg	= [NSOpenPanel openPanel];
	[dlg setMessage:		@"Choose an application to open the document"];
//	[dlg setPrompt:			@"Add Application"];
	[dlg setDirectoryURL:	[dirs objectAtIndex:0]];
	[dlg setAllowsMultipleSelection:NO];
	[dlg setCanChooseDirectories:	NO];
	[dlg beginSheetModalForWindow:[self window] completionHandler: ^(NSInteger result) {
		if (result == NSOKButton)
			handler([[dlg URLs] objectAtIndex:0]);
	}];
}

-(void)setLogo {
	NSWindow *window = [self window];
	[window setRepresentedFilename:@" "];
	[[window standardWindowButton:NSWindowDocumentIconButton] setImage:[NSImage imageNamed:@"logo"]];
}

@end

//------------------------------------------------------------------------------
//	Criteria
//------------------------------------------------------------------------------

@implementation Criterion
@synthesize name;

+(id)criterion {
	return [[self class] criterionWithName:nil children:nil];
}

+(id)criterionWithName:(NSString*)name {
	return [[self class] criterionWithName:name children:nil];
}

+(id)criterionWithName:(NSString*)name children:(id)children, ... {
	Criterion *crit = [[[[self class] alloc] init] autorelease];
	crit.name = name;
	va_list ap;
	va_start(ap, children);
	for (id next = children; next; next = va_arg(ap, id))
		[crit addChild:next];
	va_end(ap);
	return crit;
}

+(id)boolCriterion {
	static Criterion	*boolCriterion;
	if (!boolCriterion)
		boolCriterion = [Criterion criterionWithName:@":" children:
			[MatchCriterion criterionWithName:@"no"],
			[MatchCriterion criterionWithName:@"yes"],
			nil
		];
	return boolCriterion;
}

-(void)dealloc {
	self.name = nil;
	[children release];
	[super dealloc];
}

-(void)addChild:(id)child {
	if (!children)
		children = [NSMutableArray new];
	[children addObject:child];
}

-(NSUInteger)numberOfChildren {
	return [children count];
}

-(id)childAtIndex:(NSUInteger)index {
	return [children objectAtIndex:index];
}

-(id)displayValue:(NSString*)input {
	return self.name;
}

-(NSString*)output:(id)display after:(NSString*)input last:(bool)last {
	return input;
}

-(bool)isComposite {
	return false;
}

-(NSString*)matches:(NSString*)input {
	return input;
}
@end

//----------------------------------------

@implementation SeparatorCriterion
+(id)shared {
	static SeparatorCriterion *shared;
	@synchronized(self)  {
		if (!shared)
			shared = [SeparatorCriterion new];
		return shared;
	}
}
-(id)displayValue:(NSString*)input {
	return [NSMenuItem separatorItem];
}
-(NSString*)matches:(NSString*)input {
	return nil;
}
@end

//----------------------------------------

@implementation CompositeCriterion
-(id)withSeparators:(NSString*)s {
	separators = s;
	return self;
}
-(bool)isComposite {
	return true;
}
-(NSUInteger)numberOfChildren {
	return 0;
}
@end

//----------------------------------------

@implementation TextFieldCriterion
+(id)shared {
	static TextFieldCriterion *shared;
	@synchronized(self)  {
		if (!shared)
			shared = [TextFieldCriterion new];
		return shared;
	}
}
-(NSString*)matches:(NSString*)input {
	return @"";
}
-(id)displayValue:(NSString*)input withWidth:(float)width {
	if (name) {
		LabelledTextField	*text	= [[[LabelledTextField alloc] initWithFrame:NSMakeRect(0, 0, width, 18)] autorelease];
		[text setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[[text cell] setWraps:NO];
		[text setStringValue:input];
		[text setLabel:name];
		return text;
	} else {
		NSTextField	*text	= [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, width, 18)] autorelease];
		[text setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[[text cell] setWraps:NO];
		[text setStringValue:input];
		return text;
	}
}
-(id)displayValue:(NSString*)input {
	return [self displayValue:[input stringByReplacingOccurrencesOfString:@"\n" withString:@";"] withWidth:600];
}
-(NSString*)output:(id)display after:(NSString*)input last:(bool)last {
	NSString	*text	= [(NSTextField*)display stringValue];
	NSUInteger	length	= [input length];

	if (length == 0)
		return text;
		
	if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:[input characterAtIndex:length - 1]])
		input = [input stringByAppendingString:@" "];
		
	return [input stringByAppendingString:text];
}
@end

//----------------------------------------

@implementation MatchCriterion
-(NSString*)matches:(NSString*)input {
	NSUInteger	length = [name length];
	if ([input hasPrefix:name]) {
		if ([input length] == length)
			return @"";
		unichar c = [input characterAtIndex:length];
		if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == ':' || c == '-' || c == '_')
			return nil;
		return [input substringFromIndex:length + 1];
	}
	return nil;
}
-(NSString*)output:(id)display after:(NSString*)input last:(bool)last {
	NSUInteger	length	= [input length];
	if (length == 0)
		return name;
		
	if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:[input characterAtIndex:length - 1]])
		input = [input stringByAppendingString:@" "];
		
	return [input stringByAppendingString:name];
}
@end

//----------------------------------------


@implementation TokenFieldCriterion
+(id)criterionWithName:(NSString*)name separators:(NSString*)separators width:(float)width children:(id)children, ... {
	TokenFieldCriterion *crit = [[[self class] new] autorelease];
	crit.name = name;
	va_list ap;
	va_start(ap, children);
	for (id next = children; next; next = va_arg(ap, id))
		[crit addChild:next];
	va_end(ap);
	crit->width			= width;
	crit->separators	= separators;
	return crit;
}

-(id)withWidth: (float)w {
	width = w;
	return self;
}
-(id)withSeparators:(NSString*)s {
	separators = s;
	return self;
}
-(NSRange)findEnd:(NSString*)input {
	return [input rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:separators ? separators : @" \t\n\r;"]];
}
-(NSString*)matches:(NSString*)input {
	NSRange		r = [self findEnd:input];
	return r.location == NSNotFound ? @"" : [input substringFromIndex:r.location + 1];
}
-(id)displayValue:(NSString*)input {
	NSRange		r = [self findEnd:input];
	return [self displayValue:r.location == NSNotFound ? input : [input substringToIndex:r.location] withWidth:width ? width : 100];
}
-(NSString*)output:(id)display after:(NSString*)input last:(bool)last {
	input =[super output:display after:input last:last];
	if (!separators)
		return input;
	return [input stringByAppendingString:last
		? [separators substringFromIndex:[separators length] - 1]
		: [separators substringToIndex:1]
	];
}
@end

//------------------------------------------------------------------------------
//	MyRuleEditor
//------------------------------------------------------------------------------

@implementation MyRuleEditor

-(void)insertRowAtIndex:(NSInteger)rowIndex withType:(NSRuleEditorRowType)rowType asSubrowOfRow:(NSInteger)parentRow animate:(BOOL)shouldAnimate {
	[(id<MyRuleEditorDelegate>)self.delegate ruleEditor:self setParentRow:parentRow];
	[super insertRowAtIndex:rowIndex withType:rowType asSubrowOfRow:parentRow animate:shouldAnimate];
#if 0
	NSMutableArray	*c = [NSMutableArray new];
	NSMutableArray	*v = [NSMutableArray new];
	for (id crit = nil; [self.delegate ruleEditor:self numberOfChildrenForCriterion:crit withRowType:NSRuleEditorRowTypeSimple];) {
		crit = [self.delegate ruleEditor:self child:0 forCriterion:crit withRowType:NSRuleEditorRowTypeSimple];
		[c addObject:crit];
		[v addObject:[self.delegate ruleEditor:self displayValueForCriterion:crit inRow:rowIndex]];
	}
	[super setCriteria:c andDisplayValues:v forRowAtIndex:rowIndex];
#endif
}

-(void)removeRowsAtIndexes:(NSIndexSet*)rowIndexes includeSubrows:(BOOL)includeSubrows {
	[(id<MyRuleEditorDelegate>)self.delegate ruleEditor:self removeRows:rowIndexes];
	[super removeRowsAtIndexes:rowIndexes includeSubrows:YES];
}

-(void)setCriteria:(NSArray*)criteria andDisplayValues:(NSArray*)values forRowAtIndex:(NSInteger)rowIndex {
	[super setCriteria:criteria andDisplayValues:values forRowAtIndex:rowIndex];
}

-(int)getNewChildRow:(int)parent {
	int	row = [[self subrowIndexesForRow:parent] lastIndex];
	
	while (row != -1 && [self rowTypeForRow:row] == NSRuleEditorRowTypeCompound) {
		parent	= row;
		row		= [[self subrowIndexesForRow:parent] lastIndex];
	}

	return row == -1 ? parent + 1 : row + 1;
}

-(void)parse:(NSString*)value withCriteria:(Criterion*)criteria toParent:(NSInteger)parent {
	NSMutableArray	*c	= [NSMutableArray new];
	NSMutableArray	*v	= [NSMutableArray new];
	
	struct {
		CompositeCriterion	*comp;
		NSInteger			parent;
	} stack[8], *sp = stack;
	
	Criterion	*crit		= criteria;
	NSString	*input		= value;
	NSInteger	ancestor	= parent;
	for (;;) {
		Criterion *next = 0;
		for (Criterion *i in crit->children) {
			if (NSString *rem = [i matches:input]) {
				[c addObject:i];
				[v addObject:[i displayValue:input]];
				next	= i;
				input	= rem;
				break;
			}
		}
		if (!next) {
			NSRange		r = [input rangeOfString:@" "];
			NSString*	s;
			if (r.location == NSNotFound) {
				s		= input;
				input	= @"";
			} else {
				s		= [input substringToIndex:r.location];
				input	= [input substringFromIndex:r.location + 1];
			}
			Criterion *i = [MatchCriterion criterionWithName:s];
			[c addObject:i];
			[v addObject:s];
			[crit addChild:i];
			if (crit == criteria) {
				TextFieldCriterion	*t = [TextFieldCriterion shared];
				[i addChild:t];
				[c addObject:t];
				[v addObject:[t displayValue:value]];
				break;
			}
			next	= i;
		}
		crit = next;
			
		if ([crit isComposite]) {
			sp->comp	= (CompositeCriterion*)crit;
			sp->parent	= parent;
			++sp;
			int	row = [self getNewChildRow:parent];
			[self insertRowAtIndex:row withType:NSRuleEditorRowTypeCompound asSubrowOfRow:parent animate:FALSE];
			[self setCriteria:c andDisplayValues:v forRowAtIndex:row];
			[c removeAllObjects];
			[v removeAllObjects];
			parent = row;
		}

		if ([crit->children count] == 0) {
			if (parent == ancestor || [input length] == 0)
				break;
			int	row = [self getNewChildRow:parent];
			[self insertRowAtIndex:row withType:NSRuleEditorRowTypeSimple asSubrowOfRow:parent animate:FALSE];
			[self setCriteria:c andDisplayValues:v forRowAtIndex:row];
			[c removeAllObjects];
			[v removeAllObjects];
			
		
			if (sp > stack) {
				if (sp[-1].comp->separators) {
					while ([input length] && [[NSCharacterSet characterSetWithCharactersInString:sp[-1].comp->separators] characterIsMember:[input characterAtIndex:0]])
						input =  [input substringFromIndex:1];
				} else if (![[NSCharacterSet alphanumericCharacterSet] characterIsMember:[input characterAtIndex:0]]) {
					--sp;
					parent = sp->parent;
					while (![[NSCharacterSet alphanumericCharacterSet] characterIsMember:[input characterAtIndex:0]])
						input =  [input substringFromIndex:1];
				}
				crit	= sp[-1].comp;
			}
		}

	}

	if ([c count]) {
		int	row = [self getNewChildRow:parent];
		[self insertRowAtIndex:row withType:NSRuleEditorRowTypeSimple asSubrowOfRow:parent animate:FALSE];
		[self setCriteria:c andDisplayValues:v forRowAtIndex:row];
	}
}

-(NSString*)deparseRow:(int)row to:(NSString*)output isLast:(bool)last {
	NSArray		*c		= [self criteriaForRow:row];
	NSArray		*v		= [self displayValuesForRow:row];

	for (int j = 0, n = [c count]; j < n; j++)
		output = [(Criterion*)[c objectAtIndex:j] output:[v objectAtIndex:j] after:output last:last];

	if ([self rowTypeForRow:row] == NSRuleEditorRowTypeCompound) {
		CompositeCriterion	*comp = [c lastObject];
		NSIndexSet	*set = [self subrowIndexesForRow:row];
		for (NSUInteger i = [set firstIndex]; i != NSNotFound; i = [set indexGreaterThanIndex:i]) {
			output = [self deparseRow:i to:output isLast:i == [set lastIndex]];
			if (comp->separators && i != [set lastIndex])
				output = [output stringByAppendingString:comp->separators];
		}
	}
	return output;
}

-(NSString*)deparseRow:(int)row {
	return [self deparseRow:row to:@"" isLast:true];
}

@end

//------------------------------------------------------------------------------
//	PathCell
//------------------------------------------------------------------------------

@implementation PathCell

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView*)controlView withIcon:(NSImage*)icon {
	NSRect    icon_rect, path_rect;
	NSDivideRect(cellFrame, &icon_rect, &path_rect, cellFrame.size.height, NSMinXEdge);
	
    [[self attributedStringValue] drawInRect: path_rect];
	icon_rect.size.width = icon_rect.size.height = 16;
	[icon drawInRect:icon_rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1 respectFlipped:YES hints:nil];
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView*)controlView {
	[self drawInteriorWithFrame:cellFrame inView:controlView
		withIcon:[[NSWorkspace sharedWorkspace] iconForFileType:[[self title] pathExtension]]
	];
}

@end

//------------------------------------------------------------------------------
//	IconTextCell
//------------------------------------------------------------------------------

@implementation IconTextCell
@synthesize icon;

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView*)controlView {
	[self drawInteriorWithFrame:cellFrame inView:controlView withIcon:icon];
}

@end

//------------------------------------------------------------------------------
//	LabelledTextCell
//------------------------------------------------------------------------------

@implementation LabelledTextCell

-(id)init {
	if (self = [super init]) {
		label = [[NSCell alloc] initTextCell:@""];
	}
	return self;
}

-(void)setLabel:(NSString*)s {
    [label setObjectValue:s];
}

-(void)setFont:(NSFont*)fontObj {
	[super setFont:fontObj];
	[label setFont:fontObj];
}

-(void)drawWithFrame:(NSRect)cellFrame inView:(NSView*)controlView {
	NSRect    label_rect, edit_rect;
	NSDivideRect(cellFrame, &label_rect, &edit_rect, cellFrame.size.width / 2, NSMinXEdge);
	label_rect.origin.y += 2;
	[label drawWithFrame:label_rect inView:controlView];
	[super drawWithFrame:edit_rect inView:controlView];
}

-(void)editWithFrame:(NSRect)aRect inView:(NSView*)controlView editor:(NSText*)textObj delegate:(id)anObject event:(NSEvent*)theEvent {
	aRect.size.width	/= 2;
	aRect.origin.x		+= aRect.size.width;
	[super editWithFrame:aRect inView:controlView editor:textObj delegate:anObject event:theEvent];
}

-(void)selectWithFrame:(NSRect)aRect inView:(NSView*)controlView editor:(NSText*)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength {
	aRect.size.width	/= 2;
	aRect.origin.x		+= aRect.size.width;
	[super selectWithFrame:aRect inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

@end

//------------------------------------------------------------------------------
//	LabelledTextField
//------------------------------------------------------------------------------

@implementation LabelledTextField

+(Class)cellClass {
    return [LabelledTextCell class];
}

-(void)setLabel:(NSString*)s {
    [self.cell setLabel:s];
}

-(void)setFont:(NSFont*)fontObj {
	[self.cell setFont:fontObj];
}

@end

//------------------------------------------------------------------------------
//	SVNErrorAlert
//------------------------------------------------------------------------------

void SVNErrorAlert(NSWindow *window, svn_error_t *err) {
	NSAlert	*alert = [NSAlert new];
	[alert addButtonWithTitle:@"OK"];
	[alert setMessageText:@"Subversion Error"];
	[alert setInformativeText: SVNcontext::GetErrorMessage(err, true)];
	[alert setAlertStyle:NSInformationalAlertStyle];
	
	[alert beginSheetModalForWindow:window
		modalDelegate:nil
		didEndSelector:nil
		contextInfo:nil
	];
	[alert release];
}

void SVNErrorAlertMainThread(NSWindow *window, svn_error_t *err) {
	dispatch_async(dispatch_get_main_queue(), ^ {
		SVNErrorAlert(window, err);
	});
}

