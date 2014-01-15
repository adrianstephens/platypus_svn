#import "SVNwrapper.h"

@interface SVNService : NSObject <SVNdelegate> {
	NSString	*cache_dir;
}

+(void)addLRU:(NSString*)list value:(id)value;
+(NSArray*)getLRU:(NSString*)list;

@end


