#import "SVNEditor.h"
#import "SyntaxColouring.h"

@interface LineReader : NSObject {
    NSFileHandle		*handle;
    NSUInteger			chunk_size;
    NSData	*delimiter;
}

-(void)setDelimiter:(NSString*)string;
@property(nonatomic)		NSUInteger chunk_size;

-(id)initWithFilePath:(NSString*)path;
-(NSString*)readLine;
@end

@interface NSData (Find)
- (NSUInteger)find:(NSData*)data;
@end

@implementation NSData (Find)
-(NSUInteger)find:(NSData*)data {
    const char	*find	= (const char*)[data bytes];
    NSUInteger	length	= [data length];
	const char	*start	= (const char*)[self bytes];
	const char	*end	= start + [self length] - length;

    for (const char *p = start, *n; (n = (const char*)memchr(p, *find, end - p)); p = n + 1) {
		if (length == 1 || memcmp(p + 1, find + 1, length - 1) == 0)
			return n - start;
	}
	return NSNotFound;
}

@end

@implementation LineReader
@synthesize chunk_size;

-(void)setDelimiter:(NSString*)string {
	delimiter = [[string dataUsingEncoding:NSUTF8StringEncoding] retain];
}

-(id)initWithFilePath:(NSString*)path {
    if (self = [super init]) {
        if (!(handle = [NSFileHandle fileHandleForReadingAtPath:path])) {
            [self release];
			return nil;
        }
		[handle retain];

		self.delimiter	= @"\n";
		self.chunk_size	= 10;
    }
    return self;
}

-(void)dealloc {
    [handle closeFile];
    [handle release];
    [delimiter release];
    [super dealloc];
}

-(NSString*)readLine {
    NSAutoreleasePool	*pool = [NSAutoreleasePool new];
    NSMutableData		*data = [[NSMutableData new] autorelease];
    for (;;) {
        NSData		*chunk	= [handle readDataOfLength:chunk_size];
		if ([chunk length] == 0)
			break;
        NSUInteger	lineend = [chunk find:delimiter];
        if (lineend != NSNotFound) {
            //include the length so we can include the delimiter in the string
			NSUInteger	prev_len = [chunk length], new_len = lineend + [delimiter length];
		    [handle seekToFileOffset:[handle offsetInFile] + new_len - prev_len];
            chunk	= [chunk subdataWithRange:NSMakeRange(0, new_len)];
			[data appendData:chunk];
            break;
        }
        [data appendData:chunk];
    }

	if ([data length] == 0) {
		[pool release];
		return nil;
	}
    NSString	*line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [pool release];
    return [line autorelease];
}

@end

struct FileDataSource {
	LineReader	*base, *path;

	svn_error_t*	open(apr_off_t *prefixes, apr_off_t *suffixes, const svn_diff_datasource_e *sources, apr_size_t num_sources) {
		return 0;
	}
	svn_error_t*	close(svn_diff_datasource_e source) {
		return 0;
	}
	svn_error_t*	get_next_token(apr_uint32_t *hash, void **token, svn_diff_datasource_e source) {
		if (NSString *line = [(source == svn_diff_datasource_original ? base : path) readLine]) {
			*hash	= [line hash];
			*(NSString**)token = [line retain];
		} else {
			*token = 0;
		}
		return 0;
	}
	svn_error_t*	compare(void *ltoken, void *rtoken, int *cmp) {
		*cmp = ltoken == rtoken ? 0 : [(NSString*)ltoken compare:(NSString*)rtoken];
		return 0;
	}
	void			discard(void *token)	{
		[(NSString*)token release];
	}
	void			discard_all()			{}

	FileDataSource(NSString *_base, NSString *_path) {
		base = [[LineReader alloc] initWithFilePath:_base];
		path = [[LineReader alloc] initWithFilePath:_path];
	}
	~FileDataSource() {
		[base release];
		[path release];
	}
};

struct StringArrayDataSource {
	NSTextView			*text;
	SyntaxColouring		*syntax_colouring;
	NSDictionary		*normal, *added, *deleted;

	struct Lines {
		NSArray	*array;
		int		line;
		Lines(NSString *fn) : line(0) {
			array = [[[[NSString stringWithContentsOfFile:fn encoding:NSUTF8StringEncoding error:nil]
				stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
				componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\n"]
			] retain];
		}
		~Lines() {
			[array release];
		}
		NSString	*Next() {
			if (line < [array count])
				return [array objectAtIndex:line++];
			return nil;
		}
		NSString	*operator[](int i) {
			return [array objectAtIndex:i];
		}
	} base, path;
	
	svn_error_t*	open(apr_off_t *prefixes, apr_off_t *suffixes, const svn_diff_datasource_e *sources, apr_size_t num_sources) {
		return 0;
	}
	svn_error_t*	close(svn_diff_datasource_e source) {
		return 0;
	}
	svn_error_t*	get_next_token(apr_uint32_t *hash, void **token, svn_diff_datasource_e source) {
		if (NSString *line = (source == svn_diff_datasource_original ? base : path).Next()) {
			*hash	= [line hash];
			*(NSString**)token = line;
		} else {
			*token = 0;
		}
		return 0;
	}
	svn_error_t*	compare(void *ltoken, void *rtoken, int *cmp) {
		*cmp = ltoken == rtoken ? 0 : [(NSString*)ltoken compare:(NSString*)rtoken];
		return 0;
	}
	void			discard(void *token)	{}
	void			discard_all()			{}
	
	void			addline(NSString *line, NSDictionary *attributes) {
		if ([line length]) {
			NSMutableAttributedString	*aline	= [syntax_colouring processString:line];
			[aline addAttributes:attributes range:NSMakeRange(0, [line length])];
			[[text textStorage] appendAttributedString:aline];
		}
		[[text textStorage] appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
	}
	
	svn_error_t*	common(const SVNDiffPacket &packet) {
		for (int i = packet.original.start; i < packet.original.start + packet.original.length; i++)
			addline(base[i], normal);
		return 0;
	}
	
	svn_error_t*	diff_modified(const SVNDiffPacket &packet) {
		for (int i = packet.original.start; i < packet.original.start + packet.original.length; i++)
			addline(base[i], deleted);

		for (int i = packet.modified.start; i < packet.modified.start + packet.modified.length; i++)
			addline(path[i], added);
		return 0;
	}
	svn_error_t*	diff_latest(const SVNDiffPacket &packet)					{ return 0; }
	svn_error_t*	diff_common(const SVNDiffPacket &packet)					{ return 0; }
	svn_error_t*	conflict(const SVNDiffPacket &packet, svn_diff_t *resolved)	{ return 0; }

	StringArrayDataSource(NSTextView *_text, NSString *_base, NSString *_path) : text(_text), base(_base), path(_path) {
		syntax_colouring = [SyntaxColouring new];
		normal	= @{
			NSBackgroundColorAttributeName:		[NSColor whiteColor],
			NSFontAttributeName:				[NSFont fontWithName:@"Menlo" size:11],
		};
		added	= @{
			NSBackgroundColorAttributeName:		[NSColor colorWithDeviceRed:1 green:0.8f blue:0.8f alpha:1],
			NSFontAttributeName:				[NSFont fontWithName:@"Menlo" size:11],
//			NSUnderlineStyleAttributeName:		[NSNumber numberWithBool:true]
		};
		deleted	= @{
			NSBackgroundColorAttributeName:		[NSColor colorWithDeviceRed:0.8f green:0.8f blue:1 alpha:1],
			NSFontAttributeName:				[NSFont fontWithName:@"Menlo" size:11],
			NSStrikethroughStyleAttributeName:	[NSNumber numberWithBool:true]
		};

	}
	~StringArrayDataSource() {
		[syntax_colouring release];
	}
};

//------------------------------------------------------------------------------
//	SVNEditorText
//------------------------------------------------------------------------------

@interface SVNEditorText : NSViewController {
	IBOutlet NSTextView *textview;
}
@end

@implementation SVNEditorText

-(id)init {
	if (self = [super initWithNibName:@"SVNEditorText" bundle:nil]) {
		[self loadView];
		NSMutableParagraphStyle	*style = [NSMutableParagraphStyle new];
		[style setDefaultTabInterval:48];
		[textview setDefaultParagraphStyle:style];
		[style release];
		[[textview textStorage] setFont:[NSFont fontWithName:@"Menlo" size:11]];
	//	[textview setTypingAttributes:
	//		[NSDictionary dictionaryWithObject:[NSFont fontWithName:@"Menlo" size:11] forKey:NSFontAttributeName]
	//	];
	}
	return self;
}

-(id)initWithPath:(NSString*)path {
	if (self = [self init]) {
		SVNdiff	svn_diff;
		StringArrayDataSource	fds(textview, path, path);
		svn_diff_t	*diff = svn_diff.MakeDiff2(fds);
		svn_diff.ProcessDiff(fds, diff);
	}
	return self;
}

-(id)initWithPaths:(NSString*)path base:(NSString*)base {
	if (self = [self init]) {
		SVNdiff	svn_diff;
	//	FileDataSource	fds(base, path);
		StringArrayDataSource	fds(textview, base, path);
		svn_diff_t	*diff = svn_diff.MakeDiff2(fds);//base, path);
		svn_diff.ProcessDiff(fds, diff);
	//	svn_diff.ProcessDiffObj(self, diff);
	}
	return self;
}

@end

//------------------------------------------------------------------------------
//	SVNEditorImage
//------------------------------------------------------------------------------

@interface SVNEditorImage : NSViewController {
	NSImage					*image;
	IBOutlet NSImageView	*left;
	IBOutlet NSImageView	*right;
}
@end

@implementation SVNEditorImage

-(id)init {
	if (self = [super initWithNibName:@"SVNEditorImage" bundle:nil])
		[self loadView];
	return self;
}

-(id)initWithPath:(NSString*)path {
	if (self = [self init]) {
		image = [[NSImage alloc] initWithContentsOfFile:path];
		[left setImage:image];
	}
	return self;
}

-(id)initWithPaths:(NSString*)path base:(NSString*)base {
	if (self = [self init]) {
		image = [[NSImage alloc] initWithContentsOfFile:path];
		[left setImage:image];

		NSImage *base_image = [[NSImage alloc] initWithContentsOfFile:base];
		[right setImage:base_image];
	}
	return self;
}

@end
//------------------------------------------------------------------------------
//	SVNEditor
//------------------------------------------------------------------------------

@implementation SVNEditor

-(id)init {
	if (self = [self initWithWindowNibName:@"SVNEditor"]) {
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNEditor"];
//		[self setLogo];
	}
	return self;
}

void AddEdgeConstraint(NSLayoutAttribute edge, NSView *superview, NSView *subview) {
	[superview addConstraint:
		[NSLayoutConstraint constraintWithItem:subview
			attribute:edge
			relatedBy:NSLayoutRelationEqual
			toItem:superview
			attribute:edge
			multiplier:1
			constant:0
		]
	];
}

-(void)set_vc:(NSViewController*)_vc {
	vc					= _vc;
	NSView	*view		= (NSView*)self.window.contentView;
	NSView	*subview	= vc.view;
	
	[view addSubview:subview];
	[subview setTranslatesAutoresizingMaskIntoConstraints:NO];
	AddEdgeConstraint(NSLayoutAttributeLeft,	view, subview);
	AddEdgeConstraint(NSLayoutAttributeRight,	view, subview);
	AddEdgeConstraint(NSLayoutAttributeTop,		view, subview);
	AddEdgeConstraint(NSLayoutAttributeBottom,	view, subview);
}

-(void)dealloc {
	[vc release];
	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

-(void)open:(NSString*)path {
	[[self window] setRepresentedFilename:path];
	
	NSArray *image_utis = [NSImage imageTypes];
	if ([image_utis indexOfObject:[path getUTI]] != NSNotFound) {
		[self set_vc:[[SVNEditorImage alloc] initWithPath:path]];
	} else {
		[self set_vc:[[SVNEditorText alloc] initWithPath:path]];
	}
}

-(void)diff:(NSString*)path base:(NSString*)base {
	[self window];

	NSArray *image_utis = [NSImage imageTypes];
	if ([image_utis indexOfObject:[path getUTI]] != NSNotFound) {
		[self set_vc:[[SVNEditorImage alloc] initWithPaths:path base:base]];
	} else {
		[self set_vc:[[SVNEditorText alloc] initWithPaths:path base:base]];
	}
}

@end

