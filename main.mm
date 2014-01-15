#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "main.h"
#import "icons.h"

#import "SVNProgress.h"
#import "SVNCommit.h"
#import "SVNProperties.h"
#import "SVNLog.h"
#import "SVNBlame.h"
#import "SVNBrowse.h"
#import "SVNImport.h"
#import "SVNSettings.h"

#if 0
@interface MyApplication : NSApplication
@end

@implementation MyApplication : NSApplication
-(id)init {
	if (self = [super init]) {
	}
	return self;
}

-(BOOL)sendAction:(SEL)anAction to:(id)aTarget from:(id)sender {
	NSLog(@"action:%@\n",  NSStringFromSelector(anAction));
	return [super sendAction:anAction to:aTarget from:sender];
}
@end
#endif

void RecycleFiles(NSArray *paths) {
//	NSString		*trash = [NSHomeDirectory() stringByAppendingPathComponent:@".Trash"];

	NSString		*source = [[paths objectAtIndex:0] stringByDeletingLastPathComponent];
	NSMutableArray	*files	= [NSMutableArray arrayWithCapacity:[paths count]];
	NSInteger		tag;

	for (NSString *path in paths) {
		if (![source isEqualToString:[path stringByDeletingLastPathComponent]]) {
			[[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation
				source:source destination:@"" files:files tag:&tag
			];
			[files removeAllObjects];
			source = [path stringByDeletingLastPathComponent];
		}
		[files addObject:[path lastPathComponent]];
	}
	[[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation
		source:source destination:@"" files:files tag:&tag
	];
}

@implementation SVNService

+(void)addLRU:(NSString*)list value:(id)value {
	NSUserDefaults	*defs	= [NSUserDefaults standardUserDefaults];
	NSDictionary	*dict	= [defs dictionaryForKey:@"LRU"];
	NSMutableArray	*lru	= [dict objectForKey:list];
	
	if (!lru) {
		lru		= [NSMutableArray new];
		NSMutableDictionary	*temp = [NSMutableDictionary dictionaryWithDictionary:dict];
		[temp setObject:lru forKey:list];
		dict	= temp;
	}
	
	if ([lru indexOfObject:value] == NSNotFound) {
		if ([lru count] > [defs integerForKey:@"lru_items"])
			[lru removeObjectAtIndex:0];
		[lru addObject:value];
		[[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"LRU"];
	}
}

+(NSArray*)getLRU:(NSString*)list {
	return [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"LRU"] objectForKey:list];
}

-(void)dealloc {
	[cache_dir release];
	[super dealloc];
}

-(void)applicationDidFinishLaunching:(NSNotification*)notification {
	cache_dir = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] retain];

	NSDictionary *defaults = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"defaults"];
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
 	[[NSApplication sharedApplication] setServicesProvider:self];
}

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
	return YES;
}

-(void)doCommit:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString**)error {
	[SVNCommit paths:[pboard propertyListForType:NSFilenamesPboardType]];
}

-(void)doUpdate:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString**)error {
	SVNProgress	*prog = [[SVNProgress alloc] initWithTitle:@"Update"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		APRarray<svn_revnum_t>	revs;
		[prog finishedWithError:prog->svn->Update(prog, [pboard propertyListForType:NSFilenamesPboardType], revs, SVNrevision::head())];
	});
}

-(void)doAdd:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString**)error {
	NSArray				*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	SVNcontext			svn;
	NSString			*parent = [[paths objectAtIndex:0] stringByDeletingLastPathComponent];
	svn_client_info2_t	*info	= 0;
	svn_error_t			*err	= svn.GetInfo(parent, SVNrevision::head(), &info);
	if (err) {
		[[SVNImport new] svn_import:paths];
	} else {
		SVNProgress	*prog = [[SVNProgress alloc] initWithTitle:@"Add"];
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
			svn_error_t *err = 0;
			for (NSString *path in paths) {
				if ((err = prog->svn->Add(prog, path)))
					break;
			}
			[prog finishedWithError:err];
		});
	}
}

-(void)doRemove:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString**)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	SVNcontext		svn;
	if (svn_error_t *err = svn.Delete(nil, paths))
		SVNErrorAlert(nil, err);
}

-(void)doRevert:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString**)error {
#if 1
	[SVNRevert paths:[pboard propertyListForType:NSFilenamesPboardType]];
#else
	NSArray		*paths = [pboard propertyListForType:NSFilenamesPboardType];
//	RecycleFiles(paths);
			
	SVNProgress	*prog = [[SVNProgress alloc] initWithTitle:@"Revert"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		[prog finishedWithError:prog->svn->Revert(prog, paths)];
	});
#endif
}

-(void)doResolve2:(NSString*)path {
	SVNProgress	*prog = [[SVNProgress alloc] initWithTitle:@"Resolve"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		[prog finishedWithError:prog->svn->Resolve(prog, path)];
	});
}

-(void)doResolve:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString**)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	NSString		*path	= [paths objectAtIndex:0];
	NSString		*dir	= [path stringByDeletingLastPathComponent];
	
	NSArray			*files	= [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
	NSString		*match	= [[path lastPathComponent] stringByAppendingPathExtension:@"r*"];
	NSPredicate		*pred	= [NSPredicate predicateWithFormat:@"SELF like %@", match];
	NSArray			*matches= [files filteredArrayUsingPredicate:pred];

	if ([matches count] != 2) {
		[[NSAlert alertWithMessageText:@"Subversion" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@ does not need resolving.", path] runModal];
		return;
	}
	
	NSString		*base	= [matches objectAtIndex:0];
	NSString		*left	= [matches objectAtIndex:1];
	
	if ([base compare:left] == NSOrderedDescending) {
		base = left;
		left = [matches objectAtIndex:0];
	}
	
	NSString		*merge	= [[[[[[NSUserDefaults standardUserDefaults] stringForKey:@"merge_command"]
		stringByReplacingOccurrencesOfString:@"%base"	withString:[dir stringByAppendingPathComponent:base] ]
		stringByReplacingOccurrencesOfString:@"%theirs"	withString:[dir stringByAppendingPathComponent:left] ]
		stringByReplacingOccurrencesOfString:@"%mine"	withString:[path stringByAppendingPathExtension:@"mine"] ]
		stringByReplacingOccurrencesOfString:@"%merged"	withString:path
	];
		
	NSArray *args = [merge componentsSeparatedByString:@" "];
	NSTask	*task = [NSTask launchedTaskWithLaunchPath:[args objectAtIndex:0] arguments:[args subarrayWithRange:NSMakeRange(1, [args count] - 1)]];
	task.terminationHandler = ^(NSTask *task) {
		NSLog(@"Merger terminated with status=%i\n", task.terminationStatus);
		[self performSelectorOnMainThread:@selector(doResolve2:) withObject:path waitUntilDone:NO];
	};
}

-(void)doProps:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	[[SVNProperties new] svn_props_multi:paths];
}

-(void)doLock:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	[SVNGetLock paths:[pboard propertyListForType:NSFilenamesPboardType]];
}

-(void)doUnlock:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	[SVNReleaseLock paths:[pboard propertyListForType:NSFilenamesPboardType]];
}

-(void)doLog:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	[[SVNLog new] svn_log:[pboard propertyListForType:NSFilenamesPboardType]];
}

-(void)doUpgrade:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	SVNProgress		*prog	= [[SVNProgress alloc] initWithTitle:@"Upgrade"];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		svn_error_t *err = 0;
		for (NSString *path in paths) {
			if ((err = prog->svn->Upgrade(prog, path)))
				break;
		}
		[prog finishedWithError:err];
	});
}

-(void)doBlame:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	[[SVNBlame new] svn_blame:[paths objectAtIndex:0] fromRevision:1 toRevision:SVNrevision::head()];
}

-(void)doCleanup:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	
	SVNProgress		*prog	= [[SVNProgress alloc] initWithTitle:@"Cleanup"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		//chflags -R nouchg *
		NSFileManager	*fm			= [NSFileManager defaultManager];
		NSDictionary	*attribs	= @{NSFileImmutable:@NO};
		
		for (NSString *path in paths) {
			[prog addentry:@"Checking for immutable files" path:path];
			for (NSString *file in [fm enumeratorAtPath:path]) {
				NSError			*error;
				NSString		*fullfile = [path stringByAppendingPathComponent:file];
				NSDictionary	*attribs0 = [fm attributesOfItemAtPath:fullfile error:&error];
				if ([[attribs0 objectForKey:NSFileImmutable] boolValue]) {
					if (![fm setAttributes:attribs ofItemAtPath:fullfile error:&error]) {
						[prog addentry:@"Failed to clear immutable" path:fullfile type:[error.userInfo objectForKey:NSLocalizedDescriptionKey] colour:[NSColor redColor]];
					} else {
						[prog addentry:@"Clear immutable" path:fullfile colour:[NSColor greenColor]];
					}
				}
			}
		}

		svn_error_t *err = 0;
		for (NSString *path in paths) {
			[prog addentry:@"Cleaning up" path:path];
			if ((err = prog->svn->Cleanup(prog, path)))
				break;
		}
		[prog finishedWithError:err];
	});
}

-(void)doBrowse:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString **)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	[[SVNBrowse new] svn_browse:[paths objectAtIndex:0]];
}

-(void)doImport:(NSPasteboard*)pboard userData:(NSString*)user error:(NSString**)error {
	NSArray			*paths	= [pboard propertyListForType:NSFilenamesPboardType];
	[[SVNImport new] svn_import:paths];
}

-(IBAction)doPreferences:(id)sender {
	APRInit();
	[SVNSettings new];
}

-(IBAction)doBrowse:(id)sender {
	[[SVNBrowse new] svn_browse:[[SVNService getLRU:@"repository"] objectAtIndex:0]];
}

//------------------------------------------------------------------------------
//	SVN delegate
//------------------------------------------------------------------------------

-(svn_error_t*)SVNstatus:(const svn_client_status_t*)client_status path:(const char*)path pool:(apr_pool_t*)pool {
	NSString	*overlay = 0;
	switch (client_status->node_status) {
		case svn_wc_status_missing:
		case svn_wc_status_none:
		case svn_wc_status_unversioned:	return 0;
		case svn_wc_status_normal:		overlay= @"Checkmark.icns";	break;
		case svn_wc_status_added:		overlay= @"Added.icns";		break;
		case svn_wc_status_deleted:		overlay= @"Deleted.icns";	break;
		case svn_wc_status_modified:
		case svn_wc_status_replaced:	overlay= @"Modified.icns";	break;
		case svn_wc_status_conflicted:	overlay= @"Conflict.icns";	break;
		case svn_wc_status_ignored:		overlay= @"Ignored.icns";	break;
		default:						break;
	}
	NSString	*local = [NSString stringWithUTF8String:client_status->local_abspath];
	NSString	*type	= client_status->kind == svn_node_dir ? NSFileTypeForHFSTypeCode(kGenericFolderIcon) : [local pathExtension];
	NSImage		*icon;
#if 1
	if (overlay) {
		NSString	*cache	= [[[cache_dir stringByAppendingPathComponent:[overlay stringByDeletingPathExtension]] stringByAppendingPathExtension:type] stringByAppendingPathExtension:@"icns"];
		icon	= [[[NSImage alloc] initWithContentsOfFile:cache] autorelease];
		if (!icon) {
			icon = [[[NSWorkspace sharedWorkspace] iconForFileType:type] composite:[NSImage imageNamed:overlay]];
			[icon writeToICNSFile:cache];
		}
	} else {
		icon = [[NSWorkspace sharedWorkspace] iconForFileType:type];
	}
#else
	icon = [[NSWorkspace sharedWorkspace] iconForFileType:type];
	if (overlay)
		icon = [icon composite:[NSImage imageNamed:overlay]];
#endif
	
	[[NSWorkspace sharedWorkspace] setIcon:icon forFile:local options:0];

	return 0;
}

@end

//------------------------------------------------------------------------------
//	main
//------------------------------------------------------------------------------

int main (int argc, const char *argv[]) {
#if 1
    return NSApplicationMain(argc, argv);
#else
	NSAutoreleasePool *ns_pool = [NSAutoreleasePool new];
	NSRegisterServicesProvider([SVNService new], @"SVNService");
	[[NSApplication sharedApplication] run];
	[ns_pool release];
	return 0;
#endif
}
