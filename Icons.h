#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface NSImage (Icons)

-(NSImage*)composite:(NSImage*)overlay;
-(void)writeToICNSFile:(NSString*)filePath;

@end
