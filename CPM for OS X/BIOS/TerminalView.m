//
//  CPMTerminalView.m
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalView.h"
#import "TerminalControlSequence.h"

@implementation CPMTerminalView
{
	NSMutableAttributedString *attributedString;
	NSMutableString *incomingString;

//	int selectionStartX, selectionStartY, selectionCurrentX, selectionCurrentY;

	CGFloat lineHeight, characterWidth;

	int flashCount;
	NSTimer *flashTimer;

	CPMTerminalControlSet *controlSet;

}

- (void)doCommonInit
{
	incomingString = [[NSMutableString alloc] init];
	controlSet = [[CPMTerminalControlSet ADM3AControlSet] retain];
	controlSet.delegate = self;

	NSFont *monaco = [NSFont fontWithName:@"Monaco" size:12.0f];

	lineHeight = (monaco.ascender - monaco.descender + monaco.leading);
	characterWidth = [monaco advancementForGlyph:'M'].width;
	_idealSize.width = characterWidth * controlSet.width;
	_idealSize.height = lineHeight * controlSet.height;

	flashTimer = [NSTimer
		scheduledTimerWithTimeInterval:1.0/2.5
		target:self
		selector:@selector(updateFlash:)
		userInfo:nil
		repeats:YES];
}

- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	[self doCommonInit];
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	[self doCommonInit];
	return self;
}

- (void)dealloc
{
	[attributedString release], attributedString = nil;
	controlSet.delegate = nil;
	[controlSet release], controlSet = nil;
	[super dealloc];
}

- (void)invalidate
{
	[flashTimer invalidate], flashTimer = nil;
}

- (void)writeCharacter:(char)character
{
	[controlSet writeCharacter:character];
}

- (void)viewWillDraw
{
	// create a string of the ASCII characters first

	NSString *asciiText = [NSString stringWithCString:(const char *)controlSet.characterBuffer encoding:NSASCIIStringEncoding];
	[attributedString release], attributedString = nil;
	attributedString = [[NSMutableAttributedString alloc] initWithString:asciiText];

	// establish the whole range as Monaco 12
	CTFontRef monaco = CTFontCreateWithName((CFStringRef)@"Monaco", 12.0f, NULL);
	[attributedString
		setAttributes:
		@{
			(id)kCTFontAttributeName : (id)monaco,
			(id)kCTForegroundColorAttributeName: (id)[[NSColor greenColor] CGColor]
		}
		range:NSMakeRange(0, attributedString.length)];

	uint8_t lastAttribute = 0;
	for(int y = 0; y < controlSet.height; y++)
	{
		uint16_t *attributes = [controlSet attributeBufferForY:y];
		for(int x = 0; x < controlSet.width; x++)
		{
			uint8_t attribute = attributes[x];

			if(attribute != lastAttribute)
			{
				NSMutableDictionary *newAttributes = [NSMutableDictionary dictionary];
				uint8_t attributeChanges = attribute^lastAttribute;
				lastAttribute = attribute;

				if(
					attributeChanges & (kCPMTerminalAttributeReducedIntensityOn|kCPMTerminalAttributeInverseVideoOn)
				)
				{
					NSColor *textColour = nil;
					switch(attribute & (kCPMTerminalAttributeReducedIntensityOn | kCPMTerminalAttributeInverseVideoOn))
					{
						default:
							textColour = [NSColor greenColor];
						break;
						case kCPMTerminalAttributeReducedIntensityOn:
							textColour = [NSColor colorWithDeviceRed:0.0f green:0.66f blue:0.0f alpha:1.0f];
						break;
						case kCPMTerminalAttributeInverseVideoOn:
							textColour = [NSColor colorWithDeviceRed:1.0f green:0.0f blue:1.0f alpha:1.0f];
						break;
						case kCPMTerminalAttributeInverseVideoOn | kCPMTerminalAttributeReducedIntensityOn:
							textColour = [NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:1.0f];
						break;
					}
					[newAttributes setValue:(id)[textColour CGColor] forKey:(id)kCTForegroundColorAttributeName];
				}

				if(attributeChanges&kCPMTerminalAttributeUnderlinedOn)
				{
					if(attribute & kCPMTerminalAttributeUnderlinedOn)
						[newAttributes setValue:@(kCTUnderlineStyleSingle) forKey:(id)kCTUnderlineStyleAttributeName];
					else
						[newAttributes setValue:@(kCTUnderlineStyleNone) forKey:(id)kCTUnderlineStyleAttributeName];
				}

				NSRange rangeFromHereToEnd;
				rangeFromHereToEnd.location = y*(controlSet.width+1) + x;
				rangeFromHereToEnd.length = attributedString.length - rangeFromHereToEnd.location;
				[attributedString
					addAttributes:newAttributes
					range:rangeFromHereToEnd];
			}
		}
	}
}

- (BOOL)canBecomeKeyView		{	return YES;	}
- (BOOL)acceptsFirstResponder	{	return YES;	}
- (BOOL)isOpaque				{	return YES;	}

- (void)updateFlash:(NSTimer *)timer
{
	flashCount++;
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    // get the view's bounds
	NSRect bounds = [self bounds];
	
	// set a black background
	[[NSColor blackColor] set];
	NSRectFill(bounds);

	// get context
	CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

	// work out scaler
	CGFloat scalerX = bounds.size.width / _idealSize.width;
	CGFloat scalerY = bounds.size.height / _idealSize.height;
	CGRect idealRect;
	idealRect.origin = CGPointMake(0.0f, 0.0f);
	idealRect.size = _idealSize;
	CGContextScaleCTM(context, scalerX, scalerY);

	// make sure the text matrix is the identity
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);

	// prepare Core Text
	CGContextSetShouldSmoothFonts(context, true);
	CGPathRef path = CGPathCreateWithRect(idealRect, NULL);
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)attributedString);
	CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), path, NULL);

	// TODO: render any solid areas necessary for inverse video, or for graphics
	CGContextSetAllowsAntialiasing(context, false);
	CGFloat yPosition = (lineHeight * controlSet.height) - lineHeight;
	for(int y = 0; y < controlSet.height; y++)
	{
		uint8_t lastAttribute = 0;
		int startingColumn = 0;
		NSColor *colour = nil;
		uint16_t *attributes = [controlSet attributeBufferForY:y];

		for(int x = 0; x < controlSet.width; x++)
		{
			uint8_t attribute = attributes[x]&(kCPMTerminalAttributeReducedIntensityOn|kCPMTerminalAttributeInverseVideoOn);

			if(attribute != lastAttribute)
			{
				lastAttribute = attribute;
				if(colour)
				{
					[colour set];
					NSRectFill(NSMakeRect((CGFloat)startingColumn * characterWidth, yPosition, (CGFloat)(x - startingColumn) * characterWidth, lineHeight));
				}
				startingColumn = x;

				switch(attribute)
				{
					default:
					case kCPMTerminalAttributeReducedIntensityOn:
						colour = nil;
					break;
					case kCPMTerminalAttributeInverseVideoOn:
						colour = [NSColor colorWithDeviceRed:0.0f green:1.0f blue:0.0f alpha:1.0f];
					break;
					case kCPMTerminalAttributeInverseVideoOn | kCPMTerminalAttributeReducedIntensityOn:
						colour = [NSColor colorWithDeviceRed:0.0f green:0.66f blue:0.0f alpha:1.0f];
					break;
				}
			}
		}

		if(colour)
		{
			[colour set];
			NSRectFill(NSMakeRect((CGFloat)startingColumn * characterWidth, yPosition, (CGFloat)(controlSet.width - startingColumn) * characterWidth, lineHeight));
		}
		yPosition -= lineHeight;
	}
	CGContextSetAllowsAntialiasing(context, true);

	// TODO: draw any graphics characters here

	// draw cursor?
	if(flashCount&1)
	{
		[[NSColor colorWithDeviceRed:0.0f green:0.5f blue:0.0f alpha:1.0f] set];
		NSRectFill(NSMakeRect(controlSet.cursorX * characterWidth, (controlSet.height - 1 - controlSet.cursorY) * lineHeight, characterWidth, lineHeight));
	}

	// render the text
	CTFrameDraw(frame, context);

	// clean up
	CGPathRelease(path);
	CFRelease(framesetter);
	CFRelease(frame);
}

/*

	This view implements copy and paste so as to work with the pasteboard

*/
- (void)copy:(id)sender
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
 
    // Telling the pasteboard we'll send a string, and attach the current output
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:self];
    [pasteboard setString:attributedString.string forType:NSPasteboardTypeString];
}

- (void)paste:(id)sender
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

	[self addStringToInputQueue:[pasteboard stringForType:NSPasteboardTypeString] filterToASCII:YES];
}

/*

	In conjunction with that, it implements mouse down/up/dragged to allow text selection

*/
- (CGPoint)textLocationFromMouseLocation:(CGPoint)mouseLocation
{
	return CGPointMake(0, 0);
}

- (void)mouseDown:(NSEvent *)theEvent
{
	NSLog(@"down %@", theEvent);
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	NSLog(@"dragged %@", theEvent);
}

- (void)mouseUp:(NSEvent *)theEvent
{
	NSLog(@"up %@", theEvent);
}


/*

	Keyboard text input

*/
- (void)keyDown:(NSEvent *)event
{
	switch([event keyCode])
	{
		// the cursor keys are remapped to the WordStar diamond,
		// since it seems to be quite widely used
		case 123:	[self addStringToInputQueue:@"\23" filterToASCII:NO];	break;	// left
		case 126:	[self addStringToInputQueue:@"\5" filterToASCII:NO];	break;	// up
		case 125:	[self addStringToInputQueue:@"\30" filterToASCII:NO];	break;	// down
		case 124:	[self addStringToInputQueue:@"\4" filterToASCII:NO];	break;	// right

		default:
		{
			NSString *characters = [event characters];
			[self addStringToInputQueue:characters filterToASCII:YES];
		}
		break;
	}
}

- (BOOL)hasCharacterToDequeue
{
	@synchronized(self)
	{
		return incomingString.length;
	}
}

- (unichar)dequeueBufferedCharacter
{
	@synchronized(self)
	{
		if(!incomingString.length) return 0;
		unichar character = [incomingString characterAtIndex:0];
		[incomingString deleteCharactersInRange:NSMakeRange(0, 1)];
		return character;
	}
}

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender
{
	// we'll drag and drop, yeah?
	return NSDragOperationLink;
}

- (void)addStringToInputQueue:(NSString *)string filterToASCII:(BOOL)filterToASCII
{
	NSString *filteredString = string;

	if(filterToASCII)
	{
		const char *asciiString = [string cStringUsingEncoding:NSASCIIStringEncoding];

		if(!asciiString) return;

		filteredString =
			[[[NSString alloc] initWithBytesNoCopy:(void *)asciiString length:strlen(asciiString) encoding:NSASCIIStringEncoding freeWhenDone:NO] autorelease];
	}

	if(![filteredString length]) return;

	@synchronized(self)
	{
		[incomingString appendString:filteredString];

		// TODO: is it safe to contact the delegate on this queue? Probably the delegate's
		// concern but at the minute this isn't being handled properly
		[self.delegate terminalViewDidAddCharactersToBuffer:self];
	}
}

- (void)terminalViewControlSetDidChangeOutput:(CPMTerminalControlSet *)controlSet
{
	[self setNeedsDisplay:YES];
}

- (void)terminalViewControlSet:(CPMTerminalControlSet *)controlSet addStringToInput:(NSString *)string
{
	[self addStringToInputQueue:string filterToASCII:NO];
}

@end
