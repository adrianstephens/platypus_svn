#import "Icons.h"

NS_INLINE NSRect NSMakeRect(NSPoint p, NSSize s) {
    NSRect r;
    r.origin = p;
    r.size = s;
    return r;
}

@implementation NSImage (Icons)

-(NSImage*)composite:(NSImage*)overlay {
	NSArray *reps	= [self representations];
	NSImage	*result	= [[NSImage new] autorelease];
	for (int r = 0, nr = [reps count]; r < nr; r++) {
		NSSize		size	= [[reps objectAtIndex:r] size];
		NSRect		rect	= {{0, 0}, {size.width, size.height} };
		NSImage		*temp	= [[[NSImage alloc] initWithSize:size] autorelease];
		
		[temp lockFocus];

		[self setSize:size];
		[self drawInRect:rect fromRect:NSZeroRect operation:NSCompositeCopy fraction:1];

		[overlay setSize:size];
		[overlay drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];
		
		[temp unlockFocus];

		[result addRepresentation:[[temp representations] objectAtIndex:0]];
//		[temp release];
	}
	return result;
}

typedef unsigned char	uint8;

struct ICNSheader {
	UInt32		name, length;
	ICNSheader(const char *_name, UInt32 _length) {
		memcpy(&name, _name, 4);
		_length	= (_length >> 16) | (_length << 16);
		UInt32	t = _length & 0xff00ff00;
		length	= (t >> 8) | ((_length - t) << 8);
	}
	void write(NSFileHandle *handle) {
		NSData	*save	= [NSData dataWithBytesNoCopy:this length:sizeof(ICNSheader) freeWhenDone:FALSE];
		[handle writeData:save];
	}
};

void SaveBlock(NSFileHandle *handle, NSData	*data, const char *name) {
	ICNSheader(name, 8 + [data length]).write(handle);
	[handle writeData:data];
}


void RLEencode(NSMutableData *dest, uint8 *srce, size_t length) {
	uint8	c = srce[0];
	for (int i = 0; i < length;) {
		int		s = i, run;
		uint8	p;
		do {
			p	= c;
			run	= 1;
			while (++i < length && (c = srce[i]) == p && run < 0x82)
				run++;
		} while (i < length && run <= 2);

		if (run < 3)
			run = 0;

		while (i - run > s) {
			int	t = i - run - s;
			if (t > 0x80)
				t = 0x80;
			uint8	b = t - 1;
			[dest appendBytes:&b length:1];
			[dest appendBytes:srce + s length:t];
			s = s + t;
		}

		if (run) {
			uint8	b[2] = {run + 0x80 - 3, p};
			[dest appendBytes:b length:2];
		}
	}
}

- (void)writeToICNSFile:(NSString*)filePath {
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
		[[NSFileManager defaultManager] createFileAtPath:filePath contents:[NSData data] attributes:nil];

	NSFileHandle	*handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
	if (!handle)
		@throw [NSException exceptionWithName:NSDestinationInvalidException reason:@"Failed to open destination file" userInfo:nil];
	[handle truncateFileAtOffset:0];

	UInt32			length	= 8;
	NSArray			*reps	= [self representations];
	int				nr0		= [reps count];
	int				*sizes	= new int[nr0];

	int	nr = 0;
	for (int i = 0; i < nr0; i++) {
		int	w = [(NSImageRep*)[reps objectAtIndex:i] pixelsWide];
		for (int j = 0; j < nr; j++) {
			if (sizes[j] == w) {
				w = 0;
				break;
			}
		}
		if (w)
			sizes[nr++] = w;
	}
		

	NSMutableArray	*data	= [NSMutableArray arrayWithCapacity:nr];
	for (int r = 0; r < nr; r++) {
		int					size	= sizes[r];
		NSRect				rect	= NSMakeRect(0, 0, size, size);
		NSBitmapImageRep	*bm		= [[NSBitmapImageRep alloc]
			initWithCGImage:[self CGImageForProposedRect:&rect context:NULL hints:nil]
		];
		if (size > 32) {
			NSData	*save = [[bm representationUsingType:NSPNGFileType properties:nil] retain];
			[data addObject:save];
			length += [save length] + 8;

		} else {
			NSBitmapFormat	fmt	= [bm bitmapFormat];
			int				w	= [bm pixelsWide], h = [bm pixelsHigh], n = w * h;
			uint8			*planes[5];
			[bm getBitmapDataPlanes:planes];

			if (![bm isPlanar]) {
				int		stride	= [bm bytesPerRow];
				int		spp		= [bm samplesPerPixel];
				uint8	*p		= planes[0];
				
				planes[0] = (uint8*)malloc(n * 4);
				planes[3] = (planes[2] = (planes[1] = planes[0] + n) + n) + n;
				
				int	r = 0, a = 3;
				if (fmt & NSAlphaFirstBitmapFormat) {
					r = 1;
					a = 0;
				}
				
				a -= r;
				for (int y = 0, o = 0; y < h; y++) {
					uint8	*s	= p + y * stride + r;
					for (int x = w; x--; o++, s += spp) {
						planes[0][o] = s[0];
						planes[1][o] = s[1];
						planes[2][o] = s[2];
						planes[3][o] = s[a];
					}
				}
			}
			
			NSMutableData	*rgb	= [NSMutableData dataWithCapacity:n * 3];
			NSData			*alpha	= [NSData dataWithBytes:planes[3] length:n];

			for (int i = 0; i < 3; i++)
				RLEencode(rgb, planes[i], n);

			if (![bm isPlanar])
				free(planes[0]);

			[data addObject:[NSArray arrayWithObjects:rgb, alpha, nil]];
			length += 16 + [rgb length] + [alpha length];
		}
	}

	ICNSheader("icns", length).write(handle);

	for (int r = 0; r < nr; r++) {
		int		size	= sizes[r];
		if (size > 32) {
			const char	*name	= "????";
			switch (size) {
				case 128:	name = "ic07"; break;
				case 256:	name = "ic08"; break;
				case 512:	name = "ic09"; break;
				case 1024:	name = "ic10"; break;
			}
			SaveBlock(handle, [data objectAtIndex:r], name);
		} else {
			NSArray		*array	= [data objectAtIndex:r];
			switch (size) {
				case 16:
					SaveBlock(handle, [array objectAtIndex:0], "is32");
					SaveBlock(handle, [array objectAtIndex:1], "s8mk");
					break;
				case 32:
					SaveBlock(handle, [array objectAtIndex:0], "il32");
					SaveBlock(handle, [array objectAtIndex:1], "l8mk");
					break;
			}
		}
	}
	delete[] sizes;

	[handle closeFile];
}

@end
