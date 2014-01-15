#import "SVNCommit.h"
#import "SVNProgress.h"
#import "SVNLog.h"
#import "SVNProperties.h"
#import "SVNBlame.h"
#import "SVNEditor.h"
#import <Cocoa/Cocoa.h>

//------------------------------------------------------------------------------
//	SVNCommit
//------------------------------------------------------------------------------

@implementation SVNCommit

+(void)paths:(NSArray*)paths {
	[[SVNCommit new] getFiles:paths all:false];
}

-(id)init {
	return self = [super initWithTitle:@"SVN Commit"];
}

-(void)dealloc {
	[super dealloc];
}

- (IBAction)ok_pressed:(id)sender {
	NSMutableArray	*commits	= [NSMutableArray array];
	NSMutableArray	*deletes	= [NSMutableArray array];
	svn_error_t		*err		= 0;
	SVNProgress		*ui2	= [[SVNProgress alloc] initWithTitle:@"Commit"];
	
	for (NSDictionary *info in [self getSelected]) {
		SVNClientStatus *client = [info valueForKey:@"status"];

		if (client->local.node_status == svn_wc_status_missing) {
			[deletes addObject:client->path];
			
		} else if (client->local.node_status == svn_wc_status_unversioned) {
			if ((err = svn->Add(ui2, client->path)))
				break;
		}
		
		[commits addObject:client->path];
	}
	
	if (err) {
		[ui2 finishedWithError:err];
		
	} else {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
			svn_error_t *err = [deletes count] ? svn->Delete(ui2, deletes) : 0;
			if (!err && !(err = svn->Commit(ui2, commits, message)))
				[ui2 addentry:@"Completed"];
			[ui2 finishedWithError:err];
		});
	}
	[self close];
}

-(svn_error_t*)SVNstatus:(const svn_client_status_t*)client_status path:(const char*)path pool:(apr_pool_t*)pool {
    BOOL selected = NO;
	
	if (client_status->node_status == svn_wc_status_missing) {
		selected = YES;
		
	} else {
		switch (client_status->node_status) {
			case svn_wc_status_normal:
				if (client_status->prop_status == svn_wc_status_normal || client_status->prop_status == svn_wc_status_none)
					return 0;
				break;
			case svn_wc_status_added:
			case svn_wc_status_deleted:
			case svn_wc_status_modified:
			case svn_wc_status_replaced:
				selected = YES;
			default:
				break;
		}
		switch (client_status->prop_status) {
			case svn_wc_status_added:
			case svn_wc_status_deleted:
			case svn_wc_status_modified:
				selected = YES;
			default:
				break;
		}
	}

	[self performSelectorOnMainThread:@selector(add:)
		withObject:[NSMutableDictionary dictionaryWithDictionary:@{
			@"selected":	[NSNumber numberWithBool:selected],
			@"status":		[SVNClientStatus createWithCType: client_status],
		}]
		waitUntilDone:NO
	];
	return 0;
}

@end

//------------------------------------------------------------------------------
//	SVNGetLock
//------------------------------------------------------------------------------

@implementation SVNGetLock

+(void)paths:(NSArray*)paths {
	[[SVNGetLock new] getFiles:paths all:true];
}

-(id)init {
	return self = [super initWithTitle:@"SVN Get Lock"];
}

- (IBAction)ok_pressed:(id)sender {
	SVNProgress	*prog	= [[SVNProgress alloc] initWithTitle:@"Get Lock"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		svn_error_t *err = svn->Lock(prog, [self getSelectedPaths], message, steal_locks);
		if (!err)
			[prog addentry:@"Completed"];
		[prog finishedWithError:err];
	});
	[self close];
}

-(svn_error_t*)SVNstatus:(const svn_client_status_t*)client_status path:(const char*)path pool:(apr_pool_t*)pool {
	if (!client_status->lock && client_status->node_status != svn_wc_status_none && client_status->node_status != svn_wc_status_unversioned) {
		[self performSelectorOnMainThread:@selector(add:)
			withObject:[NSMutableDictionary dictionaryWithDictionary:@{
				@"selected":	@YES,
				@"status":		[SVNClientStatus createWithCType: client_status]
			}]
			waitUntilDone:NO
		];
	}
	return 0;
}

@end

//------------------------------------------------------------------------------
//	SVNReleaseLock
//------------------------------------------------------------------------------

@implementation SVNReleaseLock

+(void)paths:(NSArray*)paths {
	[[SVNReleaseLock new] getFiles:paths all:true];
}

-(id)init {
	return self = [super initWithTitle:@"SVN Release Lock"];
}

- (IBAction)ok_pressed:(id)sender {
	SVNProgress	*prog	= [[SVNProgress alloc] initWithTitle:@"Get Lock"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		svn_error_t *err = svn->Unlock(prog, [self getSelectedPaths], break_locks);
		if (!err)
			[prog addentry:@"Completed"];
		[prog finishedWithError:err];
	});
	[self close];
}

-(svn_error_t*)SVNstatus:(const svn_client_status_t*)client_status path:(const char*)path pool:(apr_pool_t*)pool {
	if (client_status->lock) {
		[self performSelectorOnMainThread:@selector(add:)
			withObject:[NSMutableDictionary dictionaryWithDictionary:@{
				@"selected":	@YES,
				@"status":		[SVNClientStatus createWithCType: client_status]
			}]
			waitUntilDone:NO
		];
	}
	return 0;
}
@end

//------------------------------------------------------------------------------
//	SVNRevert
//------------------------------------------------------------------------------

@implementation SVNRevert

+(void)paths:(NSArray*)paths {
	[[SVNRevert new] getFiles:paths all:true];
}

-(id)init {
	return self = [super initWithTitle:@"SVN Revert"];
}

- (IBAction)ok_pressed:(id)sender {
	SVNProgress	*prog	= [[SVNProgress alloc] initWithTitle:@"Revert"];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
		svn_error_t *err = svn->Revert(prog, [self getSelectedPaths]);
		if (!err)
			[prog addentry:@"Completed"];
		[prog finishedWithError:err];
	});
	[self close];
}

-(svn_error_t*)SVNstatus:(const svn_client_status_t*)client_status path:(const char*)path pool:(apr_pool_t*)pool {
    BOOL selected = NO;

	switch (client_status->node_status) {
		case svn_wc_status_none:
		case svn_wc_status_unversioned:
			return 0;

		case svn_wc_status_added:
		case svn_wc_status_missing:
		case svn_wc_status_deleted:
		case svn_wc_status_replaced:
		case svn_wc_status_modified:
		case svn_wc_status_merged:
		case svn_wc_status_conflicted:
			selected = YES;
			break;
			
		default:
			break;
	}


	if (client_status->node_status >= svn_wc_status_normal) {
		[self performSelectorOnMainThread:@selector(add:)
			withObject:[NSMutableDictionary dictionaryWithDictionary:@{
				@"selected":	[NSNumber numberWithBool:selected],
				@"status":		[SVNClientStatus createWithCType: client_status]
			}]
			waitUntilDone:NO
		];
	}
	return 0;
}
@end



