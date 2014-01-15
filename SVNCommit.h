#import "SVNSelect.h"

@interface SVNCommit : SVNSelect
+(void)paths:(NSArray*)paths;
@end

@interface SVNGetLock : SVNSelect {
	bool	steal_locks;
}
+(void)paths:(NSArray*)paths;
@end

@interface SVNReleaseLock : SVNSelect {
	bool	break_locks;
}
+(void)paths:(NSArray*)paths;
@end

@interface SVNRevert : SVNSelect
+(void)paths:(NSArray*)paths;
@end