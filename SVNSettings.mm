#import "SVNSettings.h"
#import "SVNProperties.h"

/*
[auth]
password-stores			comma-delimited order of system-provided password stores: gnome-keyring, kwallet, keychain, windows-crypto-api
store-passwords			deprecated
store-auth-creds		deprecated

[helpers]
diff-cmd				differencing program
diff-extensions			options passed to the file content differencing engine (default -u)
diff3-cmd				three-way differencing program
diff3-has-program-arg	true if diff3-cmd accepts a --diff-program command-line parameter.
editor-cmd				program to query the user for certain types of textual metadata or interactively resolving conflicts
merge-tool-cmd			three-way merge program

[tunnels]

[miscellany]
enable-auto-props		automatically set properties on newly added or imported files (default no)
global-ignores			names of files and directories that Subversion should not display unless they are versioned (default=*.o *.lo *.la *.al .libs *.so *.so.[0-9]* *.a *.pyc *.pyo *.rej *~ #*# .#* .*.swp .DS_Store.)
interactive-conflicts	boolean option that specifies whether Subversion should try to resolve conflicts interactively
log-encoding			default character set encoding for commit log messages
mime-types-file			path of a MIME types mapping file
no-unlock				boolean do not to release locks on files you've just committed
preserved-conflict-file-exts	space-delimited list of file extensions to preserve when generating conflict filenames
use-commit-times		working copy files to have timestamps that reflect the last time they were changed in the repository


'none'            (System character set)
'utf8'
'utf8-bom'        (UTF-8 with a Byte-Order Mark [BOM])
'utf16'           (UTF-16 with the default byte-order with a BOM)
'utf16-nobom'     (UTF-16 default byte-order )
'utf16be'         (UTF-16 big-endian byte-order)
'utf16be-bom'     (UTF-16 big-endian byte-order with BOM)
'utf16le'         (UTF-16 little-endian byte-order)
'utf16le-bom'     (UTF-16 little-endian byte-order with a BOM)
'utf32'           (UTF-32 with the default byte-order with a BOM)
'utf32-nobom'     (UTF-32 default byte-order )
'utf32be'         (UTF-32 big-endian byte-order)
'utf32be-bom'     (UTF-32 big-endian byte-order with BOM)
'utf32le'         (UTF-32 little-endian byte-order)
'utf32le-bom'     (UTF-32 little-endian byte-order with a BOM)
'iso8859-1'
'winansi'         (Windows code page 1252)
'macosroman'
'iso8859-15'
'shiftjis'
'eucjp'
'iso8859-5'
'koi8-r'
'cp1251'          (Windows code page 1251)
'cp949'           (Windows code page 949)
'cp936'           (Simplified Chinese GBK)
'cp950'           (Traditional Chinese Big5)
*/

@implementation SVNSettings
static SVNSettings	*shared;

+(SVNSettings*)new {
	if (!shared)
		shared = [[SVNSettings alloc] init];
	[shared.window makeKeyAndOrderFront:self];
	return shared;
}

struct config_section_context {
	SVNSettings		*self;
	svn_config_t	*cfg;
	config_section_context(SVNSettings *_self, svn_config_t *_cfg) : self(_self), cfg(_cfg) {}
	operator void*()	{ return this; }
};

struct config_context {
	SVNSettings		*self;
	Criterion		*crit;
	int				row;
	config_context(SVNSettings *_self, Criterion *_crit, int _row) : self(_self), crit(_crit), row(_row) {}
	operator void*()	{ return this; }
};

-(bool)gotValue:(const char*)name value:(const char*)value criteria:(Criterion*)crit row:(int)row pool:(APRpool)_pool {
	NSLog(@"%s=%s\n", name, value);
	[rules parse:[NSString stringWithFormat:@"%s %s", name, value] withCriteria:crit toParent:row];
	return true;
}

svn_boolean_t config_enumerator(const char *name, const char *value, void *baton, apr_pool_t *pool) {
	config_context	*ctx = (config_context*)baton;
	return [ctx->self gotValue:name value:value criteria:ctx->crit row:ctx->row pool:pool];
}

-(bool)gotSection:(const char*)name config:(svn_config_t*)cfg pool:(APRpool)_pool {
	NSLog(@"section:%s\n", name);
	
	int			row = [rules getNewChildRow:-1];
	Criterion	*c	= strcmp(name, "miscellany") == 0 ? crit_misc
					: strcmp(name, "auto-props") == 0 ? crit_autoprops
					: strcmp(name, "global")	 == 0 ? crit_global
					: crit_general;
				
	[rules insertRowAtIndex:row withType:NSRuleEditorRowTypeCompound asSubrowOfRow:-1 animate:FALSE];
	[rules setCriteria:@[c] andDisplayValues:@[[NSString stringWithUTF8String:name]] forRowAtIndex:row];
	
	svn_config_enumerate2(cfg, name, &config_enumerator, config_context(self, c, row), _pool);
	return true;
}

svn_boolean_t config_section_enumerator(const char *name, void *baton, apr_pool_t *pool) {
	config_section_context	*ctx = (config_section_context*)baton;
	return [ctx->self gotSection:name config:ctx->cfg pool:pool];
}

-(id)init {
	if (self = [self initWithWindowNibName:@"SVNSettings"]) {
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNSettings"];
		[self window];
		
		dummy	= [[Criterion criterionWithName:nil children:[Criterion criterionWithName:@"dummy"], nil] retain];

		Criterion	*textCriterion	= [TextFieldCriterion shared];
		Criterion	*boolCriterion	= [Criterion boolCriterion];

		Criterion	*crit_diff		= [Criterion criterionWithName:@"Difference Viewer" children:
			[MatchCriterion criterionWithName:@"built-in"],
			[Criterion criterionWithName:@"external" children: textCriterion, nil],
			nil
		];
		Criterion	*crit_merge		= [Criterion criterionWithName:@"Merge Tool" children:
			[MatchCriterion criterionWithName:@"built-in"],
			[Criterion criterionWithName:@"external" children: textCriterion, nil],
			nil
		];
		
		NSUserDefaults	*defs		= [NSUserDefaults standardUserDefaults];

		[rules parse:[defs stringForKey:@"diff_command"]
			withCriteria:	[Criterion criterionWithName:nil children:crit_diff, nil]
			toParent:		-1
		];

		[rules parse:[defs stringForKey:@"merge_command"]
			withCriteria:	[Criterion criterionWithName:nil children:crit_merge, nil]
			toParent:		-1
		];
		
		crit_misc		= [CompositeCriterion criterionWithName:@"Miscellany"];
		[crit_misc addChild:[MatchCriterion criterionWithName:@"enable-auto-props"		children:boolCriterion, nil]];
		[crit_misc addChild:[MatchCriterion criterionWithName:@"interactive-conflicts"	children:boolCriterion, nil]];
		[crit_misc addChild:[MatchCriterion criterionWithName:@"no-unlock"				children:boolCriterion, nil]];
		[crit_misc addChild:[MatchCriterion criterionWithName:@"use-commit-times"		children:boolCriterion, nil]];
		[crit_misc addChild:[MatchCriterion criterionWithName:@"mime-types-file"		children:textCriterion, nil]];
		[crit_misc addChild:[MatchCriterion criterionWithName:@"log-encoding"			children:
			[MatchCriterion criterionWithName:@"US-ASCII"],
			[MatchCriterion criterionWithName:@"UTF-8"],
			[MatchCriterion criterionWithName:@"UTF-16"],
			[MatchCriterion criterionWithName:@"UTF-32"],
			[MatchCriterion criterionWithName:@"ISO-8859-1"],
			[MatchCriterion criterionWithName:@"ISO-8859-2"],
			[MatchCriterion criterionWithName:@"ISO-8859-3"],
			[MatchCriterion criterionWithName:@"ISO-8859-4"],
			[MatchCriterion criterionWithName:@"ISO-8859-5"],
			[MatchCriterion criterionWithName:@"ISO-8859-6"],
			[MatchCriterion criterionWithName:@"ISO-8859-7"],
			[MatchCriterion criterionWithName:@"ISO-8859-8"],
			[MatchCriterion criterionWithName:@"ISO-8859-9"],
			[MatchCriterion criterionWithName:@"ISO-8859-10"],
			[MatchCriterion criterionWithName:@"ISO-8859-15"],
			[MatchCriterion criterionWithName:@"Shift_JIS"],
			[MatchCriterion criterionWithName:@"EUC-JP"],
			[MatchCriterion criterionWithName:@"ISO-2022-KR"],
			[MatchCriterion criterionWithName:@"EUC-KR"],
			[MatchCriterion criterionWithName:@"ISO-2022-JP"],
			[MatchCriterion criterionWithName:@"ISO-2022-JP-2"],
			[MatchCriterion criterionWithName:@"ISO-8859-6-E"],
			[MatchCriterion criterionWithName:@"ISO-8859-6-I"],
			[MatchCriterion criterionWithName:@"ISO-8859-8-E"],
			[MatchCriterion criterionWithName:@"ISO-8859-8-I"],
			[MatchCriterion criterionWithName:@"GB2312"],
			[MatchCriterion criterionWithName:@"Big5"],
			[MatchCriterion criterionWithName:@"KOI8-R"],
			[MatchCriterion criterionWithName:@"cp1251"],
			[MatchCriterion criterionWithName:@"cp949"],
			[MatchCriterion criterionWithName:@"cp936"],
			[MatchCriterion criterionWithName:@"cp950"],
			nil]
		];
		[crit_misc addChild:[CompositeCriterion criterionWithName:@"global-ignores"					children:textCriterion, nil]];
		[crit_misc addChild:[CompositeCriterion criterionWithName:@"preserved-conflict-file-exts"	children:textCriterion, nil]];
		
#if 1
		Criterion	*props	= [CompositeCriterion criterionWithName:@"has properties" children:[MatchCriterion criterionWithName:@"select property"], nil];
		[SVNProperties getCriteria:props isDir:false];
		
		crit_autoprops		= [CompositeCriterion criterionWithName:@"auto-props" children:
			[TokenFieldCriterion criterionWithName:nil children:props, nil],
			nil
		];
#else
		crit_autoprops		= [CompositeCriterion criterionWithName:@"auto-props" children:
			[TokenFieldCriterion criterionWithName:nil children:
				[CompositeCriterion criterionWithName:@"has properties" children:
					[TokenFieldCriterion criterion],
					nil
				],
				nil
			],
			nil
		];
#endif

		crit_global		= [CompositeCriterion criterionWithName:@"global" children:
			[MatchCriterion criterionWithName:@"http-proxy-exceptions"				children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"http-proxy-host"					children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"http-proxy-port"					children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"http-proxy-username"				children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"http-proxy-password"				children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"http-auth-types"					children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"http-timeout"						children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"ssl-trust-default-ca"				children:boolCriterion, nil],
			[MatchCriterion criterionWithName:@"ssl-authority-files"				children:textCriterion, nil],
			[MatchCriterion criterionWithName:@"store-plaintext-passwords"			children:boolCriterion, nil],
			[MatchCriterion criterionWithName:@"store-ssl-client-cert-pp"			children:boolCriterion, nil],
			[MatchCriterion criterionWithName:@"store-ssl-client-cert-pp-plaintext"	children:boolCriterion, nil],
			nil
		];
		
		crit_general	= [CompositeCriterion criterionWithName:@"others" children:textCriterion, nil];

		const char *config_path;
		svn_config_get_user_config_path(&config_path, NULL, NULL, pool);

		APRhash	config;
		svn_config_get_config(&config, NULL, pool);
		for (APRhash::iterator i = config.begin(); i != config.end(); ++i) {
			const char		*key	= i.key();
			svn_config_t	*cfg	= *i;
			NSLog(@"category:%s\n", key);
			
			svn_config_enumerate_sections2(cfg, &config_section_enumerator, config_section_context(self, cfg), pool);
		}
		interactive = true;
	}
	return self;
}
-(void)dealloc {
	shared	= nil;
//	[criteria release];
	[dummy release];
	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

-(IBAction)ok:(id)sender {
	[self close];
}

-(IBAction)cancel:(id)sender {
	[self close];
}

//NSRuleEditorDelegate

-(void)ruleEditor:(NSRuleEditor*)editor setParentRow:(NSInteger)parentRow {
	if (parentRow == -1) {
		criteria = dummy;
	} else {
		NSArray *array = [editor criteriaForRow:parentRow];
		criteria = [array lastObject];
	}
}

-(void)ruleEditor:(NSRuleEditor*)editor removeRows:(NSIndexSet*)rowIndexes {
	current_row = -1;
}

-(NSInteger)ruleEditor:(NSRuleEditor*)editor numberOfChildrenForCriterion:(id)criterion withRowType:(NSRuleEditorRowType)rowType {
	if (criterion == nil)
		return [criteria->children count];
	return [criterion numberOfChildren];
}

-(id)ruleEditor:(NSRuleEditor*)editor child:(NSInteger)index forCriterion:(id)criterion withRowType:(NSRuleEditorRowType)rowType {
	if (criterion == nil)
		return [criteria->children objectAtIndex:index];
		
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

@end
