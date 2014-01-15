#import "SVNBrowse.h"
#import "SVNLog.h"
#import "SVNProperties.h"
#import "SVNProgress.h"
#import "SVNBlame.h"
#import "main.h"

NSMutableDictionary *FindEntry(NSMutableArray *array, NSString *name) {
	for (NSMutableDictionary *i in array) {
		if ([(NSString*)[i objectForKey:@"name"] isEqualToString:name])
			return i;
	}
	return 0;
}


@interface SVNBrowseAdder : NSObject <SVNdelegate> {
	NSMutableArray		*array;
	NSMutableDictionary	*root;
	id					obj;
}
-(id)initWithArray:(NSMutableArray*)_array on:(id)_obj;
@end

//------------------------------------------------------------------------------
//	SVNBrowseAdder
//------------------------------------------------------------------------------
@implementation SVNBrowseAdder

-(id)initWithArray:(NSMutableArray*)_array on:(id)_obj {
	if (self = [super init]) {
		array	= [_array retain];
		obj		= [_obj retain];
	}
	return self;
}
-(id)initWithArray:(NSMutableArray*)_array on:(id)_obj withRoot:(NSMutableDictionary*)_root {
	if (self = [self initWithArray:_array on:_obj])
		root = _root;
	return self;
}

-(void)dealloc {
	[obj release];
	[super dealloc];
}

-(void)add:(id)value {
	[obj willChangeValueForKey:@"data"];
	[array addObject:value];
	[obj didChangeValueForKey:@"data"];
}

-(svn_error_t*)SVNlist:(const svn_dirent_t*)entry path:(const char*)path abspath:(const char*)abs_path lock:(const svn_lock_t*)lock pool:(apr_pool_t*)pool {
	NSMutableDictionary *info;
	NSString	*name = [NSString stringWithUTF8String:path];
	
	if (!path[0]) {
		if (!root)
			return 0;
		info = root;
	} else {
		if (FindEntry(array, name))
			return 0;
		
		info = [NSMutableDictionary dictionaryWithDictionary:@{
			@"name":	name,
			@"path":	[[NSString stringWithUTF8String:abs_path] stringByAppendingPathComponent:name],
			@"isLeaf":	[NSNumber numberWithBool:entry->kind != svn_node_dir],
		}];
	}

	[info setValue:[NSNumber numberWithUnsignedLongLong:entry->created_rev] forKey:@"revision"];
	[info setValue:(NSDate*)SVNdate(entry->time)							forKey:@"date"];
	
	if (entry->last_author)
		[info setValue:[NSString stringWithUTF8String:entry->last_author]	forKey:@"author"];

	if (entry->kind != svn_node_dir) {
		[info setValue:[name getUTIDescription]								forKey:@"type"];
		[info setValue:[NSNumber numberWithUnsignedLongLong:entry->size]	forKey:@"size"];
	}
		
	if (lock)
		[info setValue:[NSString stringWithUTF8String:lock->owner]			forKey:@"lock"];

	if (info != root)
		[self performSelectorOnMainThread:@selector(add:) withObject:info waitUntilDone:NO];
	return 0;
}

@end

//------------------------------------------------------------------------------
//	SVNBrowse
//------------------------------------------------------------------------------

enum COLS {
	COL_PATH,
	COL_TYPE,
	COL_REVISION,
	COL_AUTHOR,
	COL_SIZE,
	COL_DATE,
	COL_LOCK
};

@implementation SVNBrowse

-(id)init {
	if (self = [self initWithWindowNibName:@"SVNBrowse"]) {
		[self setShouldCascadeWindows:NO];
		[self setWindowFrameAutosaveName:@"SVNBrowse"];
		[self setLogo];

		data		= [NSMutableArray new];
		revision	= SVNrevision::head();
		svn			= new SVNcontext;
		queue		= dispatch_queue_create("browse", NULL);
	}
	return self;
}

-(void)windowDidLoad {
    [super windowDidLoad];
	[outline registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
	[outline setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
	[outline setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
}

-(void)dealloc {
	[data release];
	[root release];
	dispatch_release(queue);

	[super dealloc];
}

-(void)windowWillClose:(NSNotification*)notification {
	[self release];
}

-(void)updateFolder:(NSMutableDictionary*)item {
	NSMutableArray	*children	= [item objectForKey:@"children"];
	if (!children) {
		children	= [[NSMutableArray new] autorelease];
		[item setValue:children forKey:@"children"];
	}
	
	NSProgressIndicator *prog	= [NSProgressIndicator new];
	[item setValue:prog		forKey:@"progress"];

	NSString		*path = [item objectForKey:@"path"];
	dispatch_async(queue, ^ {
		SVNBrowseAdder	*adder	= [[SVNBrowseAdder alloc] initWithArray:children on:self];
		svn_error_t		*err	= svn->GetList(adder, [self get_url:path], revision);
		[prog removeFromSuperview];
		[item removeObjectForKey:@"progress"];
		[prog release];
		if (err)
			svn->LogErrorMessage(err);
	});
}

-(void)listFolder:(NSMutableDictionary*)item {
	if ([item objectForKey:@"children"])
		return;
	[self updateFolder:item];
}

-(void)setRevision:(SVNrevision)_revision {
	revision = _revision;
}

-(void)setRoot:(NSString*)_root {
	if (!root || ![root isEqualToString:_root]) {
		[root release];
		root = [_root retain];
		
		NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{
			@"name":	root,
			@"path":	root,
			@"isLeaf":	[NSNumber numberWithBool:false],
		}];

		[self willChangeValueForKey:@"data"];
		[data removeAllObjects];
		[data addObject:item];
		[self didChangeValueForKey:@"data"];
	}
}

-(void)setURL:(NSString*)path isDir:(bool)dir {
	[SVNService addLRU:@"repository" value:path];
	[self willChangeValueForKey:@"data"];
	NSString		*relative	= [path relativeTo:root];
	NSArray			*comps		= [relative pathComponents];
	NSMutableArray	*array		= data;
	NSMutableDictionary *item	= [array objectAtIndex:0];
	NSIndexPath		*index		= [NSIndexPath indexPathWithIndex:0];

	path	= @"/";
	for (int i = 0, n = [comps count] - (dir ? 0 : 1); i < n; i++) {
		[self listFolder:item];
		array	= [item objectForKey:@"children"];
		
		NSString *name	= [comps objectAtIndex:i];
		path	= [path stringByAppendingPathComponent:name];
		name	= [name stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		item	= FindEntry(array, name);
		if (!item) {
			item = [NSMutableDictionary dictionaryWithDictionary:@{
				@"name":	name,
				@"path":	path,
				@"isLeaf":	[NSNumber numberWithBool:false],
			}];
			[array addObject:item];
		}
		index = [index indexPathByAddingIndex:[array indexOfObject:item]];
	}
	[self didChangeValueForKey:@"data"];
	[tree_controller setSelectionIndexPath:index];
}

-(void)browseFromInfo:(SVNClientInfo*)info {
	[self setRoot:info->repos_root_URL];
	[self setURL:info->URL isDir:info->kind == svn_node_dir];
	[url_text setStringValue:info->URL];
}

-(svn_error_t*)svn_browse:(NSString*)path {
	svn_client_info2_t	*info;
	svn_error_t *err = svn->GetInfo(path, revision, &info);
	if (!err)
		[self browseFromInfo:[SVNClientInfo createWithCType:info]];
	return err;
}

//------------------------------------------------------------------------------
//	actions
//------------------------------------------------------------------------------

-(NSTreeNode*)get_clicked_node {
	return [outline itemAtRow:[outline clickedRow]];
}

-(NSMutableDictionary*)get_clicked {
	return [[self get_clicked_node] representedObject];
}

-(NSString*)get_url:(NSString*)path {
	if ([path characterAtIndex:0] == '/')
		path = [root stringByAppendingString:path];
	return [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

-(IBAction)set_url:(id)sender {
	NSString			*url	= [sender stringValue];
	if ([url hasSuffix:@"/"])
		url = [url substringToIndex:[url length] - 1];

	dispatch_async(queue, ^ {
		svn_client_info2_t	*info;
		if (svn_error_t *err = svn->WithWindow([self window])->GetInfo(url, revision, &info)) {
			SVNErrorAlertMainThread([self window], err);

		} else {
			[self performSelectorOnMainThread:@selector(browseFromInfo:)
				withObject:[SVNClientInfo createWithCType:info]
				waitUntilDone:NO
			];
		}
	});
}

-(IBAction)select:(id)sender {
	NSInteger	i = [outline selectedRow];
	if (i != -1) {
		NSMutableDictionary *item = [[outline itemAtRow:i] representedObject];
		[url_text setStringValue:[self get_url:[item objectForKey:@"path"]]];
	}
}

-(IBAction)open:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	NSString			*fn		= [NSTemporaryDirectory() stringByAppendingPathComponent:[item objectForKey:@"name"]];
	svn->GetFile(SVNstreamFILE([fn UTF8String]), [self get_url:[item objectForKey:@"path"]], revision);
	[[NSWorkspace sharedWorkspace] openFile:fn];
}

-(IBAction)open_with:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	NSString			*url	= [self get_url:[item objectForKey:@"path"]];
	NSString			*fn		= [NSTemporaryDirectory() stringByAppendingPathComponent:[item objectForKey:@"name"]];
	
	if (NSString *app = [sender representedObject]) {
		svn->GetFile(SVNstreamFILE([fn UTF8String]), url, revision);
		[[NSWorkspace sharedWorkspace] openFile:fn withApplication:app];
	} else {
		[self chooseApplication:^(NSURL *app) {
			svn->GetFile(SVNstreamFILE([fn UTF8String]), url, revision);
			[[NSWorkspace sharedWorkspace] openFile:fn withApplication:[app path]];
		}];
	}
}

-(IBAction)show_log:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	[[SVNLog new] svn_log:[NSArray arrayWithObject:[self get_url:[item objectForKey:@"path"]]] fromRevision:revision];
}

-(IBAction)blame:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	[[SVNBlame new] svn_blame:[self get_url:[item objectForKey:@"path"]] fromRevision:1 toRevision:revision];
}

-(IBAction)checkout:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	NSSavePanel			*dlg	= [NSSavePanel savePanel];
	NSString			*name	= [item objectForKey:@"name"];

	if ([name isEqualToString:@"trunk"])
		name = [[[item objectForKey:@"path"] stringByDeletingLastPathComponent] lastPathComponent];

	[dlg setNameFieldStringValue:name];
	[dlg setCanCreateDirectories:YES];
	[dlg setAllowedFileTypes:[NSArray arrayWithObject:@"public.folder"]];

	[dlg beginSheetModalForWindow:[self window] completionHandler: ^(NSInteger result) {
		if (result == NSOKButton) {
			NSURL		*output = [dlg URL];
			
			SVNProgress	*prog = [[SVNProgress alloc] initWithTitle:@"Checkout"];
			dispatch_async(
				dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
			^ {
				APRarray<svn_revnum_t>	revs;
				[prog finishedWithError:prog->svn->Checkout(prog, [self get_url:[item objectForKey:@"path"]], [output path])];
			});
		}
	}];
}

-(IBAction)create_folder:(id)sender {
	NSTreeNode	*node = [self get_clicked_node];
	[outline expandItem:node expandChildren:NO];

	NSMutableDictionary	*item		= [node representedObject];
	NSMutableArray		*children	= [item objectForKey:@"children"];
	NSString			*path		= [item objectForKey:@"path"];
	NSMutableDictionary *info		= [NSMutableDictionary dictionaryWithDictionary:@{
		@"name":	@"new folder",
		@"path":	[path stringByAppendingPathComponent:@"?"],
		@"isLeaf":	[NSNumber numberWithBool:false],
	}];

	[self willChangeValueForKey:@"data"];
	[children addObject:info];
	[self didChangeValueForKey:@"data"];

	int	childindex = 0;
	for (NSTreeNode *child in [node childNodes]) {
		if ([child representedObject] == info)
			break;
		childindex++;
	}
	
	NSUInteger		indices[32], i = 0;
	indices[32 - ++i] = childindex;
	while (NSTreeNode *parent = [node parentNode]) {
		indices[32 - ++i] = [[parent childNodes] indexOfObject:node];
		node = parent;
	}

	NSIndexPath		*index		= [NSIndexPath indexPathWithIndexes:indices + 32 - i length:i];
	[tree_controller setSelectionIndexPath:index];
	NSInteger		row			= [outline selectedRow];
	[outline editColumn:0 row:row withEvent:nil select:YES];
}

-(IBAction)add_file:(id)sender {
	[outline expandItem:[self get_clicked_node] expandChildren:NO];

	NSMutableDictionary	*item		= [self get_clicked];
	NSString			*path		= [item objectForKey:@"path"];
	NSOpenPanel			*dlg		= [NSOpenPanel openPanel];
	[dlg setCanChooseDirectories:YES];
	[dlg setAllowsMultipleSelection:YES];

	[dlg beginSheetModalForWindow:[self window] completionHandler: ^(NSInteger result) {
		if (result == NSOKButton) {
			for (NSURL *i in [dlg URLs]) {
				NSString	*path2	= [path stringByAppendingPathComponent:[[i path] lastPathComponent]];
				SVNcontext::LogErrorMessage(
					svn->Import(self, [i path], [self get_url:path2])
				);
			}
			[self updateFolder:item];
		}
	}];
}

-(IBAction)rename:(id)sender {
	[outline editColumn:0 row:[outline clickedRow] withEvent:nil select:YES];
}

-(IBAction)remove:(id)sender {
	NSTreeNode			*node	= [self get_clicked_node];
	NSTreeNode			*parent	= [node parentNode];
	
	NSMutableDictionary	*item	= [node representedObject];
	SVNcontext::LogErrorMessage(
		svn->Delete(self, [NSArray arrayWithObject:[self get_url:[item objectForKey:@"path"]]])
	);

	NSMutableArray		*children	= [[parent representedObject] objectForKey:@"children"];
	[self willChangeValueForKey:@"data"];
	[children removeObject:item];
	[self didChangeValueForKey:@"data"];
}

-(IBAction)save:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	NSSavePanel			*dlg	= [NSSavePanel savePanel];
	[dlg setNameFieldStringValue:[item objectForKey:@"name"]];

	[dlg beginSheetModalForWindow:[self window] completionHandler: ^(NSInteger result) {
		if (result == NSOKButton) {
			NSURL		*output = [dlg URL];
			svn->GetFile(SVNstreamFILE([[output path] UTF8String]), [self get_url:[item objectForKey:@"path"]], revision);
		}
	}];
}

-(IBAction)copy_url:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	NSPasteboard		*pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:[NSArray arrayWithObject:[self get_url:[item objectForKey:@"path"]]]];
}

-(IBAction)show_props:(id)sender {
	NSMutableDictionary	*item	= [self get_clicked];
	[[SVNProperties new] svn_props:[self get_url:[item objectForKey:@"path"]] atRevision:revision];
}

-(svn_error_t*)SVNcommit:(const svn_commit_info_t*)commit_info pool:(apr_pool_t*)pool {
	return 0;
}

//------------------------------------------------------------------------------
//	NSMenuDelegate
//------------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu*)menu {
	NSMutableDictionary	*item	= [self get_clicked];
 	BOOL				dir		= ![[item objectForKey:@"isLeaf"] boolValue];
	
	for (NSMenuItem *i in [menu itemArray]) {
		SEL action = [i action];
		[i setEnabled: !(dir
			?		action == @selector(open:)
				||	action == @selector(blame:)
				||	action == @selector(save:)
			:		action == @selector(refresh:)
				||	action == @selector(add_file:)
				||	action == @selector(add_folder:)
				||	action == @selector(create_folder:)
			)
		];
	}

	NSString	*path		= [item objectForKey:@"path"];
	NSMenuItem	*openwith	= [menu itemWithTitle:@"Open with"];
	[openwith setSubmenu:[self openWithFor:path]];
	[openwith setEnabled:!dir];
}

//------------------------------------------------------------------------------
//	NSOutlineViewDelegate
//------------------------------------------------------------------------------

-(void)outlineViewItemWillExpand:(NSNotification*)n {
	NSTreeNode	*node = [[n userInfo] objectForKey:@"NSObject"];
	[self listFolder:[node representedObject]];
}


-(NSCell*)outlineView:(NSOutlineView*)ov dataCellForTableColumn:(NSTableColumn*)col item:(id)item {
	if (!col)
		return nil;
	NSString	*identifier = col.identifier;
	if (identifier && [identifier isEqualToString:@"name"]) {
		NSString		*ext	= [[[item representedObject] objectForKey:@"path"] pathExtension];
		IconTextCell	*cell	= [[IconTextCell new] autorelease];
		if ([ext isEqualToString:@""] && ![[[item representedObject] objectForKey:@"isLeaf"] boolValue])
			ext = NSFileTypeForHFSTypeCode(kGenericFolderIcon);
		cell.icon = [[NSWorkspace sharedWorkspace] iconForFileType:ext];
		return cell;
	}
	return [[NSTextFieldCell new] autorelease];
}

-(void)outlineView:(NSOutlineView*)ov willDisplayOutlineCell:(NSCell*)cell forTableColumn:(NSTableColumn*)col item:(id)item {
	if (item) {
		if (NSProgressIndicator *prog = [[item representedObject] objectForKey:@"progress"]) {
			NSRect	rect = [ov frameOfOutlineCellAtRow:[ov rowForItem:item]];
			[prog setFrame:rect];
			if (![prog superview]) {
				[prog setStyle:NSProgressIndicatorSpinningStyle];
				[prog setIndeterminate:YES];
				[prog startAnimation:self];
				[ov addSubview:prog];
			}
		}
	}
}

- (void)controlTextDidEndEditing:(NSNotification*)notification {
	int	i = [[[notification userInfo] valueForKey:@"NSTextMovement"]intValue];
	if (i == NSReturnTextMovement) {
		NSString	*value	= [[notification object] stringValue];
		NSMutableDictionary *info =  [[outline itemAtRow:[outline selectedRow]] representedObject];
		NSString	*path0	= [info objectForKey:@"path"];
		NSString	*path1	= [[path0 stringByDeletingLastPathComponent] stringByAppendingPathComponent:value];
		NSString	*url1	= [self get_url:path1];
		
		[info setObject:path1 forKey:@"path"];
	
		svn_error_t	*err;
		if ([[path0 lastPathComponent] isEqualToString:@"?"]) {
			err = svn->MakeDirs(self, [NSArray arrayWithObject:url1]);
		} else {
			NSString	*url0	= [self get_url:path0];
			err = svn->Rename(self, url0, url1);
		}
		SVNcontext::LogErrorMessage(err);
	}
}

//-----------------------------------------
// drag ...
//-----------------------------------------

-(BOOL)outlineView:(NSOutlineView*)ov writeItems:(NSArray*)items toPasteboard:(NSPasteboard*)pboard {
	drop_items	= [items retain];

	[pboard declareTypes:[NSArray arrayWithObject:NSFilesPromisePboardType] owner:self];
	[pboard setPropertyList:[NSArray arrayWithObject:@"public.item"] forType:NSFilesPromisePboardType];
	return YES;
}

-(NSArray*)outlineView:(NSOutlineView*)ov namesOfPromisedFilesDroppedAtDestination:(NSURL*)dest forDraggedItems:(NSArray*)items {
	drop_dest	= [[dest path] retain];
	
	NSMutableArray	*array = [NSMutableArray arrayWithCapacity:[items count]];
	for (NSTreeNode *node in items) {
		NSMutableDictionary *info	= [node representedObject];
		NSString			*path	= [info objectForKey:@"path"];
		NSLog(@"%@\n", path);
		[array addObject:[path lastPathComponent]];
	}
	return array;
}

-(void)outlineView:(NSOutlineView*)ov draggingSession:(NSDraggingSession*)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	if (operation & NSDragOperationDelete) {
		NSMutableArray	*paths		= [NSMutableArray new];
		[self willChangeValueForKey:@"data"];
		for (NSTreeNode *node in drop_items) {
			NSMutableDictionary *item		= [node representedObject];
			NSTreeNode			*parent		= [node parentNode];
			NSMutableArray		*children	= [[parent representedObject] objectForKey:@"children"];
			[children removeObject:item];

			[paths addObject:[self get_url:[item objectForKey:@"path"]]];
		}
		[self didChangeValueForKey:@"data"];
		SVNcontext::LogErrorMessage(svn->Delete(self, paths));
		[paths release];

	} else if (operation & NSDragOperationCopy) {
		for (NSTreeNode *node in drop_items) {
			NSMutableDictionary *item	= [node representedObject];
			NSString			*path	= [item objectForKey:@"path"];
			SVNcontext::LogErrorMessage(
				svn->GetFile([drop_dest stringByAppendingPathComponent:[path lastPathComponent]], [self get_url:path], revision)
			);
		}
	}
	[drop_items release];
	[drop_dest release];
	drop_items	= nil;
	drop_dest	= nil;
}

//-----------------------------------------
// ... and drop
//-----------------------------------------

-(NSDragOperation)outlineView:(NSOutlineView*)ov validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)childIndex {
	if (!item)
		return NSDragOperationNone;
	
	NSTreeNode			*node	= item;
	if ([[[node representedObject] objectForKey:@"isLeaf"] boolValue] && childIndex == NSOutlineViewDropOnItemIndex)
		return NSDragOperationNone;

	return NSDragOperationGeneric;
}

-(BOOL)outlineView:(NSOutlineView*)ov acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)childIndex {
	NSTreeNode			*node		= item;
	NSMutableDictionary	*folder		= [node representedObject];
	NSString			*path		= [folder objectForKey:@"path"];
	if ([[[node representedObject] objectForKey:@"isLeaf"] boolValue]) {
		NSTreeNode *target = [node parentNode];
		childIndex	= [[target childNodes] indexOfObject:node] + 1;
		node		= target;
	} else {            
		if (childIndex == NSOutlineViewDropOnItemIndex)
			childIndex = 0;
	}

	NSArray				*classes		= [NSArray arrayWithObject:[NSURL class]];
	SVNProgress			*prog			= [[SVNProgress alloc] initWithTitle:@"Import"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		__block NSInteger	insertionIndex	= childIndex;
		__block svn_error_t	*err			= 0;
		[info enumerateDraggingItemsWithOptions:0 forView:ov classes:classes searchOptions:nil usingBlock:^(NSDraggingItem *drag, NSInteger index, BOOL *stop) {
			NSString	*srce	= [drag.item path];
			NSString	*name	= [srce lastPathComponent];
			NSString	*path2	= [path stringByAppendingFormat:@"/%@", name];
			err = svn->Import(prog, srce, [self get_url:path2]);
			insertionIndex++;
		}];
		[prog finishedWithError:err];
		dispatch_async(queue, ^ {
			[self updateFolder:folder];
		});
	});

	return YES;
}

@end
