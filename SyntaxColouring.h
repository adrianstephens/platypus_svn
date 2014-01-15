#ifndef SyntaxColouring_h
#define SyntaxColouring_h

#import <Cocoa/Cocoa.h>

struct rgb8 {
	typedef unsigned char comp;
	comp	r, g, b;
	operator NSColor*()	const {
		return [NSColor colorWithDeviceRed: r / 255.f green: g / 255.f blue: b / 255.f alpha:1];
	}
};

struct crgb8 : rgb8 {
	crgb8(comp _r, comp _g, comp _b) { r = _r; g = _g; b = _b; }
};

@interface SyntaxColouring : NSObject {
	bool	comment;
}

-(NSMutableAttributedString*)process:(const char*)input;
-(NSMutableAttributedString*)processString:(NSString*)input;

@end

#endif
