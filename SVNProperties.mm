#import "SVNProperties.h"
#import "SVNProgress.h"

/*
VERSIONED:
svn:executable	file	make the file executable in Unix-hosted working copies
svn:special		file	the file is not an ordinary file, but a symbolic link or other special object
svn:needs-lock	file	make the file read-only in the working copy, as a reminder that the file should be locked before editing begins

svn:mime-type	file	mime type
svn:eol-style	file	[native,CRLF,LF,CR]	how to manipulate the file's line-endings in the working copy and in exported trees
svn:keywords	file	list of keywords used, expanded within the file
	$Date$					Date of last known commit
	$LastChangedDate$		Synonym for $Date$
	$Revision$				Revision of last known commit.
	$Author$				Author who made the last known commit.
	$HeadURL$				The full URL of this file in the repository.
	$Id$					A compressed combination of the previous four keywords.

svn:ignore		dir		list of unversioned file patterns to be ignored by svn status and other subcommands
svn:externals	dir		multiline list of other paths and URLs the client should check out
svn:mergeinfo			Used by Subversion to track merge data

UNVERSIONED:
svn:author				the authenticated username of the person who created the revision
svn:autoversioned		the revision was created via the autoversioning feature
svn:date				UTC time the revision was created, in ISO 8601 format
svn:log					log message describing the revision
svn:rdump-lock			used to temporarily enforce mutually exclusive access to the repository by svnrdump load

SVNSYNC(UNVERSIONED):
svn:sync-currently-copying	revision number from the source repository which is currently being mirrored to this one
svn:sync-from-uuid			UUID of the repository of which this repository has been initialized as a mirror
svn:sync-from-url			URL of the repository directory of which this repository has been initialized as a mirror
svn:sync-last-merged-rev	revision of the source repository which was most recently and successfully mirrored to this one
svn:sync-lock				Used to temporarily enforce mutually exclusive access to the repository

TORTOISE:
tsvn:logminsize			minimum length of a log message for a commit
tsvn:lockmsgminsize		minimum length of a lock message
tsvn:logwidthmarker		laces a marker to indicate the maximum width in the log message entry dialog
tsvn:logtemplate		holds a multi-line text string which will be inserted in the commit message box when you start a commit
tsvn:logtemplatecommit	used for all commits from a working copy.
tsvn:logtemplatebranch	used when creating a branch/tag, or when you copy files or folders directly in the repository browser.
tsvn:logtemplateimport	used for imports.
tsvn:logtemplatedelete	used when deleting items directly in the repository browser
tsvn:logtemplatemove	used when renaming or moving items in the repository browser
tsvn:logtemplatemkdir	used when creating directories in the repository browser
tsvn:logtemplatepropset	used when modifying properties in the repository browser
tsvn:logtemplatelock	used when getting a lock
tsvn:autoprops			e.g. *.sh = svn:eol-style=native;svn:executable sets two properties on files with the .sh extension.
tsvn:logfilelistenglish	whether the file status is inserted in English or in the localized language
tsvn:projectlanguage	sets the language module the spell checking engine should use
tsvn:logsummary			regex used to extract a portion of the log message which is then shown in the log dialog as the log message summary.
tsvn:logrevregex		regex which matches references to revisions in a log message

CLIENT-SIDE HOOK SCRIPTS:
tsvn:startcommithook
tsvn:precommithook
tsvn:postcommithook
tsvn:startupdatehook
tsvn:preupdatehook
tsvn:postupdatehook

CUSTOM PROPERTIES:
tsvn:userfileproperties
tsvn:userdirproperties
	<propname>=bool;<label>(YESVALUE;NOVALUE;<checkboxtext>)
	<propname>=state;<label>(DEFVAL;VAL1;TEXT1;VAL2;TEXT2;VAL3;TEXT3;...)
	<propname>=singleline;<label>(<regex>)
	<propname>=multiline;<label>(<regex>)

BUGTRAQ:
bugtraq:url				URL of your bug tracking tool
bugtraq:warnifnoissue	true to warn on empty issue-number text field
bugtraq:message			activates bug tracking system in input field mode
bugtraq:label			text shown on the commit dialog to label the edit box where you enter the issue number
bugtraq:number			If true only numbers are allowed in the issue-number text field
bugtraq:append			defines if the bug-ID is appended (true) to the end of the log message or inserted (false) at the start of the log message

*/

//----------------------------------------

@interface OutputCriterion : Criterion
@end

@implementation OutputCriterion
-(id)displayValue:(NSString*)input {
	return @"";
}
-(NSString*)output:(id)display after:(NSString*)input last:(bool)last {
	return [input stringByAppendingString:name];
}
@end

//----------------------------------------

@interface CheckBoolCriterion : Criterion
@end

@implementation CheckBoolCriterion
-(NSString*)matches:(NSString*)input {
	return [input isEqualToString:@"true"] || [input isEqualToString:@"false"] ? input : nil;
}
@end

//------------------------------------------------------------------------------------

@implementation SVNProperties

+(void)getCriteria:(Criterion*)c isDir:(bool)dir {
	Criterion *boolCriterion	= [Criterion boolCriterion];
	Criterion *textCriterion	= [TextFieldCriterion shared];
	Criterion *separator		= [SeparatorCriterion shared];

	if (dir) {
		[c addChild:[MatchCriterion criterionWithName:@"svn:ignore" children:
			[[CompositeCriterion criterionWithName:@"ignore the following files:" children:
				[[TokenFieldCriterion criterion] withSeparators:@"\n"],
				nil
			] withSeparators:@"\n"],
			nil
		]];
//		children:textCriterion, nil]];
		
		[c addChild:[MatchCriterion criterionWithName:@"svn:externals"	children:
			[[CompositeCriterion criterionWithName:@"use the following external mappings:" children:
				[Criterion criterionWithName:@"map"		children:
					[[TokenFieldCriterion criterionWithName:nil children:
						[Criterion criterionWithName:@"to"		children:
							[TokenFieldCriterion criterion],
							nil
						],
						nil
					] withWidth:600],
					nil
				],
				nil
			] withSeparators:@"\n"],
			nil
		]];
		
		Criterion *custom = [[CompositeCriterion criterionWithName:@"use the following custom properties:" children:
			[TokenFieldCriterion criterionWithName:nil separators:@"=" width:100 children:
				[Criterion criterionWithName:@"of type" children:
					[MatchCriterion criterionWithName:@"bool" children:
						[OutputCriterion criterionWithName:@";"			children:
						[Criterion criterionWithName:@"label:"			children: [TokenFieldCriterion criterionWithName:nil	separators:@"(" width:100 children:
						[Criterion criterionWithName:@"yes value:"		children: [TokenFieldCriterion criterionWithName:nil	separators:@";"	width:100 children:
						[Criterion criterionWithName:@"no value:"		children: [TokenFieldCriterion criterionWithName:nil	separators:@";"	width:100 children:
						[Criterion criterionWithName:@"check box text:"	children: [[TokenFieldCriterion criterion] withSeparators:@")"],
						nil], nil], nil], nil], nil], nil], nil], nil], nil
					],
					[MatchCriterion criterionWithName:@"state" children:
						[OutputCriterion criterionWithName:@";"			children:
						[Criterion criterionWithName:@"label:"			children:[TokenFieldCriterion criterionWithName:nil		separators:@"("	width:100 children:
						[Criterion criterionWithName:@"default:"		children:[TokenFieldCriterion criterionWithName:nil		separators:@";"	width:100 children:
						[CompositeCriterion criterionWithName:@"with the following values:" children:
							[Criterion criterionWithName:@"value:"		children:[TokenFieldCriterion criterionWithName:nil		separators:@";"	width:100 children:
							[Criterion criterionWithName:@"label:"		children:[[TokenFieldCriterion criterion] withSeparators:@";)"],
							nil], nil], nil], nil
						], nil], nil], nil], nil], nil], nil
					],
					[MatchCriterion criterionWithName:@"singleline" children:
						[OutputCriterion criterionWithName:@";"			children:
						[Criterion criterionWithName:@"label:"			children:[TokenFieldCriterion criterionWithName:nil		separators:@"("	width:100 children:
						[Criterion criterionWithName:@"validation:"		children:[[TokenFieldCriterion criterion] withSeparators:@")"],
						nil], nil], nil], nil], nil
					],
					[MatchCriterion criterionWithName:@"multiline" children:
						[OutputCriterion criterionWithName:@";"			children:
						[Criterion criterionWithName:@"label:"			children:[TokenFieldCriterion criterionWithName:nil		separators:@"("	width:100 children:
						[Criterion criterionWithName:@"validation:"		children:[[TokenFieldCriterion criterion] withSeparators:@")"],
						nil], nil], nil], nil], nil
					],
					nil
				],
				nil
			],
			nil
		] withSeparators:@"\n"];
		
		[c addChild:separator];
		[c addChild:[MatchCriterion criterionWithName:@"tsvn:userfileproperties"	children:custom, nil]];
		[c addChild:[MatchCriterion criterionWithName:@"tsvn:userdirproperties"		children:custom, nil]];

		[c addChild:separator];
		[c addChild:[MatchCriterion criterionWithName:@"bugtraq:url"				children:textCriterion, nil]];
		[c addChild:[MatchCriterion criterionWithName:@"bugtraq:message"			children:textCriterion, nil]];
		[c addChild:[MatchCriterion criterionWithName:@"bugtraq:label"				children:textCriterion, nil]];
		[c addChild:[MatchCriterion criterionWithName:@"bugtraq:warnifnoissue"		children:boolCriterion, nil]];
		[c addChild:[MatchCriterion criterionWithName:@"bugtraq:number"				children:boolCriterion, nil]];
		[c addChild:[MatchCriterion criterionWithName:@"bugtraq:append"				children:boolCriterion, nil]];

		[c addChild:[MatchCriterion criterionWithName:@"psvn:iconoverlays"			children:boolCriterion, nil]];
		
	} else {
	
		[c addChild:[MatchCriterion criterionWithName:@"svn:executable"]];
		[c addChild:[MatchCriterion criterionWithName:@"svn:special"]];
		[c addChild:[MatchCriterion criterionWithName:@"svn:needs-lock"]];
		
		[c addChild:separator];
		
		[c addChild:[MatchCriterion criterionWithName:@"svn:eol-style" children:
			[MatchCriterion criterionWithName:@"native"],
			[MatchCriterion criterionWithName:@"CRLF"],
			[MatchCriterion criterionWithName:@"LF"],
			[MatchCriterion criterionWithName:@"CR"],
			nil
		]];
		
		[c addChild:[MatchCriterion criterionWithName:@"svn:mime-type"	children:textCriterion, nil]];
		[c addChild:[MatchCriterion criterionWithName:@"svn:keywords"	children:textCriterion, nil]];
	}
	
	
	[c addChild:separator];

	[c addChild:[Criterion criterionWithName:@"custom property"	children:
		[TokenFieldCriterion criterionWithName:nil	children:
			[Criterion criterionWithName:@"of type"		children:
				[CheckBoolCriterion criterionWithName:@"bool"		children:boolCriterion, nil],
				[Criterion criterionWithName:@"text"				children:textCriterion, nil],
				[Criterion criterionWithName:@"binary"],
				nil
			],
			nil
		],
		nil
	]];
}


-(id)init {
	if (self = [self initWithWindowNibName:@"SVNProperties"]) {
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNProperties"];
		[self window];
		properties	= [NSMutableArray new];
		svn			= new SVNcontext;
	}
	return self;
}
-(void)dealloc {
	[criteria release];
	[save_paths release];
	[properties release];
	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

-(void)add:(id)value {
	[properties addObject:value];
	[rules parse:value withCriteria:[criteria childAtIndex:0] toParent:0];
}

-(void)interactive:(NSNumber*)val {
	interactive = [val boolValue];
}

bool ComparePropertyNames(NSString *prop1, NSString *prop2) {
	NSRange		space1	= [prop1 rangeOfString:@" "];
	NSRange		space2	= [prop2 rangeOfString:@" "];

	if (space1.length && space2.length && space1.length != space2.length)
		return false;
		
	if (space1.length)
		prop1 = [prop1 substringToIndex:space1.location];
	if (space2.length)
		prop2 = [prop2 substringToIndex:space2.location];
		
	return [prop1 isEqualToString:prop2];
}

-(IBAction)ok:(id)sender {
	NSIndexSet	*set = [rules subrowIndexesForRow:0];
	for (NSUInteger i = [set firstIndex]; i != NSNotFound; i = [set indexGreaterThanIndex:i]) {
		NSString	*output = [rules deparseRow:i];
		NSString	*found	= nil;
		
		for (NSString *prev in properties) {
			if (ComparePropertyNames(output, prev)) {
				found = prev;
				break;
			}
		}
		
		if (!found || ![output isEqualToString:found]) {
			NSRange	space = [output rangeOfString:@" "];
			if (space.length) {
				svn->SetProp(self, save_paths,
					[output substringToIndex:space.location],
					[[output substringFromIndex:space.location + 1] dataUsingEncoding:NSUTF8StringEncoding]
				);
			} else {
				svn->SetProp(self, save_paths, output, [NSData data]);
			}
		}
		
		if (found)
			[properties removeObject:found];
		found = nil;
	}
	for (NSString *prop in properties) {
		NSRange		space	= [prop rangeOfString:@" "];
		if (space.length)
			prop = [prop substringToIndex:space.location];
		svn->SetProp(self, save_paths, prop, nil);
	}

	[self close];
}

-(IBAction)cancel:(id)sender {
	[self close];
}

//NSRuleEditorDelegate

-(void)ruleEditor:(NSRuleEditor*)editor setParentRow:(NSInteger)parentRow {
	if (parentRow == -1) {
		root = criteria;
	} else {
		NSArray *array = [editor criteriaForRow:parentRow];
		root = [array lastObject];
	}
}

-(NSInteger)ruleEditor:(NSRuleEditor*)editor numberOfChildrenForCriterion:(id)criterion withRowType:(NSRuleEditorRowType)rowType {
	if (criterion == nil)
		return [root->children count];
	return [criterion numberOfChildren];
}

-(void)ruleEditor:(NSRuleEditor*)editor removeRows:(NSIndexSet*)rowIndexes {
	current_row = -1;
}

-(id)ruleEditor:(NSRuleEditor*)editor child:(NSInteger)index forCriterion:(id)criterion withRowType:(NSRuleEditorRowType)rowType {
	if (criterion == nil)
		return [root->children objectAtIndex:index];
		
	return [criterion childAtIndex:index];
}

-(id)ruleEditor:(NSRuleEditor*)editor displayValueForCriterion:(id)criterion inRow:(NSInteger)row {
	current_row = row;
	return [criterion displayValue:@""];
}

-(void)ruleEditorRowsDidChange:(NSNotification*)notification {
	if (!interactive || current_row < 0)
		return;
		
	NSInteger			row		= current_row;
	NSRuleEditorRowType	type	= [rules rowTypeForRow:row];
	NSRuleEditorRowType	want	= NSRuleEditorRowTypeSimple;
	NSArray				*crits	= [rules criteriaForRow:row];
	
	for (Criterion *crit in crits) {
		if ([crit isComposite])
			want = NSRuleEditorRowTypeCompound;
	}

	if (type != want) {
		interactive = false;
		NSInteger	p = [rules parentRowForRow:row];
		[rules insertRowAtIndex:current_row withType:want asSubrowOfRow:p animate:FALSE];
		[rules setCriteria:crits andDisplayValues:@[] forRowAtIndex:row];
		[rules removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:row + 1] includeSubrows:YES];
		interactive = true;
	}
}

//---------------------

-(void)svn_props:(NSString*)path atRevision:(SVNrevision)revision {
	save_paths = [@[path] retain];
	
	bool	dir = [path isDir];
	[[self window] setRepresentedFilename:path];

	Criterion	*c	= [CompositeCriterion criterionWithName:path];
	[c addChild:[MatchCriterion criterionWithName:@"select property"]];
	[[self class] getCriteria:c isDir:dir];

	criteria	= [[Criterion criterionWithName:nil children:c, nil] retain];

	[rules insertRowAtIndex:0 withType:NSRuleEditorRowTypeCompound asSubrowOfRow:-1 animate:FALSE];
	[rules setCriteria:@[c] andDisplayValues:@[path] forRowAtIndex:0];
	[rules setCanRemoveAllRows:NO];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		if (svn_error_t *err = svn->GetProps(self, path, revision))
			SVNErrorAlertMainThread(self.window, err);
		[self performSelectorOnMainThread:@selector(interactive:) withObject:@true waitUntilDone:NO];
	});
}

-(void)svn_props:(NSString*)path {
	[self svn_props:path atRevision:SVNrevision::unspecified()];
}

-(void)svn_props_multi:(NSArray*)paths atRevision:(SVNrevision)revision {
	if ([paths count] == 1) {
		[self svn_props:[paths objectAtIndex:0] atRevision:revision];
	} else {
		save_paths = [paths retain];
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
			svn_error_t *err = 0;
			for (NSString *path in paths) {
				if ((err = svn->GetProps(self, path, revision)))
					break;
			}
			if (err)
				SVNErrorAlertMainThread(self.window, err);
		});
	}
}

-(void)svn_props_multi:(NSArray*)paths {
	[self svn_props_multi:paths atRevision:SVNrevision::unspecified()];
}

-(void)svn_revprops:(NSString*)repo atRevision:(SVNrevision)revision {
	APRhash props = svn->GetRevProps(repo, revision);
	for (APRhash::iterator i = props.begin(); i != props.end(); ++i) {
		NSMutableString	*info = [NSMutableString stringWithUTF8String:i.key()];
		svn_string_t *s = *i;
		if (s->data)
			[info appendFormat:@" %s", s->data];
		[self add:info];
	}
	interactive = true;
}

-(svn_error_t*)SVNprops:(const APRhash&)props path:(const char*)path pool:(apr_pool_t*)pool {
	for (APRhash::iterator i = props.begin(); i != props.end(); ++i) {
		NSMutableString	*info = [NSMutableString stringWithUTF8String:i.key()];
		svn_string_t *s = *i;
		if (s->data)
			[info appendFormat:@" %s", s->data];
		[self performSelectorOnMainThread:@selector(add:) withObject:info waitUntilDone:NO];
	}
	return 0;
}
@end
