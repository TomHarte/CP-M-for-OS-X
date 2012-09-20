//
//  CPMTerminalView.m
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalView.h"

typedef enum
{
	CPMTerminalViewEscapeStatusNone,
	CPMTerminalViewEscapeStatusExpectingCharacter,
	CPMTerminalViewEscapeStatusExpectingNumber,
	CPMTerminalViewEscapeStatusExpectingXCoordinate,
	CPMTerminalViewEscapeStatusExpectingYCoordinate,
} CPMTerminalViewEscapeStatus;

#define kCPMTerminalViewWidth	80
#define kCPMTerminalViewHeight	25

#define kCPMTerminalAttributeInverseVideoOn			0x01
#define kCPMTerminalAttributeReducedIntensityOn		0x02
#define kCPMTerminalAttributeBlinkingOn				0x04
#define kCPMTerminalAttributeUnderlinedOn			0x08

@implementation CPMTerminalView
{
	char srcBuffer[kCPMTerminalViewWidth * kCPMTerminalViewHeight];
	char attributes[kCPMTerminalViewWidth * kCPMTerminalViewHeight];
	int cursorX, cursorY, currentAttribute;

	CPMTerminalViewEscapeStatus escapeStatus;
	BOOL escapeCharacterWasB;

	NSMutableAttributedString *attributedString;
	NSMutableString *incomingString;
	NSMutableArray *inverseRegions, *halfIntensityInverseRegions;
	
	int selectionStartX, selectionStartY, selectionCurrentX, selectionCurrentY;

	CGFloat lineHeight, characterWidth;

	int flashCount;
	NSTimer *flashTimer;
}

- (void)doCommonInit
{
	incomingString = [[NSMutableString alloc] init];

	NSFont *monaco = [NSFont fontWithName:@"Monaco" size:12.0f];

	lineHeight = (monaco.ascender - monaco.descender + monaco.leading);
	characterWidth = [monaco advancementForGlyph:'M'].width;
	_idealSize.width = characterWidth * kCPMTerminalViewWidth;
	_idealSize.height = lineHeight * kCPMTerminalViewHeight;
	
	inverseRegions = [[NSMutableArray alloc] init];
	halfIntensityInverseRegions = [[NSMutableArray alloc] init];

	flashTimer = [NSTimer
		scheduledTimerWithTimeInterval:1.0/2.5
		target:self
		selector:@selector(updateFlash:)
		userInfo:nil
		repeats:YES];

	[self clearFrom:0 to:kCPMTerminalViewHeight*kCPMTerminalViewWidth];
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

- (void)incrementY
{
	cursorY++;

	if(cursorY == kCPMTerminalViewHeight)
	{
		memcpy(srcBuffer, &srcBuffer[kCPMTerminalViewWidth], (kCPMTerminalViewHeight-1)*kCPMTerminalViewWidth);
		memset(&srcBuffer[kCPMTerminalViewWidth*(kCPMTerminalViewHeight-1)], 32, kCPMTerminalViewWidth);

		memcpy(attributes, &attributes[kCPMTerminalViewWidth], (kCPMTerminalViewHeight-1)*kCPMTerminalViewWidth);
		memset(&attributes[kCPMTerminalViewWidth*(kCPMTerminalViewHeight-1)], 0, kCPMTerminalViewWidth);
		cursorY --;
	}
}

- (void)writeCharacter:(char)character
{
	dispatch_async(dispatch_get_main_queue(),
	^{
//		printf("%c", character);

		switch(escapeStatus)
		{
			case CPMTerminalViewEscapeStatusNone:
				[self writeNormalCharacter:character];
			break;
			
			case CPMTerminalViewEscapeStatusExpectingCharacter:
				[self writeEscapeCharacter:character];
			break;

			case CPMTerminalViewEscapeStatusExpectingNumber:
				[self writeEscapeNumber:character];
			break;

			case CPMTerminalViewEscapeStatusExpectingYCoordinate:
				escapeStatus = CPMTerminalViewEscapeStatusExpectingXCoordinate;
				cursorY = (character - 32)%kCPMTerminalViewHeight;
			break;

			case CPMTerminalViewEscapeStatusExpectingXCoordinate:
				escapeStatus = CPMTerminalViewEscapeStatusNone;
				cursorX = (character - 32)%kCPMTerminalViewWidth;
			break;
		}
	});
}

- (void)writeEscapeCharacter:(char)character
{
	escapeStatus = CPMTerminalViewEscapeStatusNone;
	switch(character)
	{
		default:
			NSLog(@"unknown escape character %02x", character);
		break;
		case 'B':
		case 'C':
			escapeStatus = CPMTerminalViewEscapeStatusExpectingNumber;
			escapeCharacterWasB = (character == 'B');
		break;

		case '=':
			escapeStatus = CPMTerminalViewEscapeStatusExpectingYCoordinate;
		break;
	}
}

- (void)writeEscapeNumber:(char)character
{
	escapeStatus = CPMTerminalViewEscapeStatusNone;

#define applyAttribute(attr)	\
			if(escapeCharacterWasB)\
				currentAttribute |= attr;\
			else\
				currentAttribute &= ~attr;

	switch(character)
	{
		default:
			NSLog(@"ignored control %c", character);
		break;
		case '0':
			applyAttribute(kCPMTerminalAttributeInverseVideoOn);
		break;
		case '1':
			applyAttribute(kCPMTerminalAttributeReducedIntensityOn);
		break;
		case '3':
			applyAttribute(kCPMTerminalAttributeUnderlinedOn);
		break;
		case '4':
			applyAttribute(kCPMTerminalAttributeBlinkingOn);
		break;
	}
	
#undef applyAttribute
}

- (void)clearFrom:(int)start to:(int)end
{
	memset(&srcBuffer[start], 32, end-start);
	memset(&attributes[start], 0, end-start);
//	currentAttribute = 0;
}

- (void)writeNormalCharacter:(char)character
{
	[self setNeedsDisplay:YES];
	if(character < 32)
	{
//		NSLog(@"control code %02x", character);
		switch(character)
		{
			default: break;

			case 7:
				if(cursorX > 0) cursorX--;
			return;
			case 8:
				cursorX--;
			return;
			case 12:
				if(cursorX < kCPMTerminalViewWidth-1) cursorX++;
			return;
			case 10:
				[self incrementY];
			return;
			case 11:
				if(cursorY > 0) cursorY--;
			return;
			case '\r':
				cursorX = 0;
			return;

			case 23:	// erase from cursor to end of screen
				[self clearFrom:cursorY*kCPMTerminalViewWidth + cursorX to:kCPMTerminalViewWidth*kCPMTerminalViewHeight];
			return;

			case 24:	// erase from cursor to end of line
				[self clearFrom:cursorY*kCPMTerminalViewWidth + cursorX to:(cursorY+1)*kCPMTerminalViewWidth];
			return;

			case 26:	// clear screen
				cursorX = cursorY = 0;
				[self clearFrom:0 to:kCPMTerminalViewHeight*kCPMTerminalViewWidth];
			return;

			case 30:	// home cursor (?)
				cursorX = cursorY = 0;
//				NSLog(@"should home cursor (?)");
			return;
			
			case 27: escapeStatus = CPMTerminalViewEscapeStatusExpectingCharacter; return;
		}
	}

	if(cursorX == kCPMTerminalViewWidth)
	{
		cursorX = 0;
		
		[self incrementY];
	}

	if(character < 32) character = 32;

	srcBuffer[(cursorY * kCPMTerminalViewWidth) + cursorX] = character;
	attributes[(cursorY * kCPMTerminalViewWidth) + cursorX] = currentAttribute;
	cursorX++;
}

- (void)dumpAttributes
{
	for(int y = 0; y < kCPMTerminalViewHeight; y++)
	{
		NSMutableString *attributesString = [NSMutableString string];
		for(int x = 0; x < kCPMTerminalViewWidth; x++)
		{
			[attributesString appendFormat:@"%02x", attributes[y*kCPMTerminalViewWidth + x]];
		}
		NSLog(@"%@", attributesString);
	}
}

- (void)viewWillDraw
{
//	NSLog(@"=====");
	// create a string of the ASCII characters first
	NSMutableString *asciiText = [NSMutableString stringWithCapacity:(kCPMTerminalViewWidth+1)*kCPMTerminalViewHeight];
	for(int y = 0; y < kCPMTerminalViewHeight; y++)
	{
//		for(int x = 0; x < kCPMTerminalViewWidth; x++)
//		{
//			unichar character = srcBuffer[y*kCPMTerminalViewWidth + x];

//			[asciiText appendFormat:@"%c", character];
//		}

		NSString *stringForLine = [[NSString alloc] initWithBytesNoCopy:&srcBuffer[y*kCPMTerminalViewWidth] length:kCPMTerminalViewWidth encoding:NSUTF8StringEncoding freeWhenDone:NO];
		[asciiText appendString:stringForLine];
		[stringForLine release];

		[asciiText appendFormat:@"\n"];
	}

	[attributedString release];
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

	[inverseRegions removeAllObjects];
	[halfIntensityInverseRegions removeAllObjects];

	uint8_t lastAttribute = 0;
	for(int y = 0; y < kCPMTerminalViewHeight; y++)
	{
		for(int x = 0; x < kCPMTerminalViewWidth; x++)
		{
			uint8_t attribute = attributes[y*kCPMTerminalViewWidth + x];

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
//							textColour = [NSColor colorWithDeviceRed:1.0f green:0.0f blue:1.0f alpha:1.0f];
//						break;
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
				rangeFromHereToEnd.location = y*(kCPMTerminalViewWidth+1) + x;
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
	CGFloat yPosition = (lineHeight * kCPMTerminalViewHeight) - lineHeight;
	for(int y = 0; y < kCPMTerminalViewHeight; y++)
	{
		uint8_t lastAttribute = 0;
		int startingColumn = 0;
		NSColor *colour = nil;

		for(int x = 0; x < kCPMTerminalViewWidth; x++)
		{
			uint8_t attribute = attributes[y*kCPMTerminalViewWidth + x]&(kCPMTerminalAttributeReducedIntensityOn|kCPMTerminalAttributeInverseVideoOn);

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
			NSRectFill(NSMakeRect((CGFloat)startingColumn * characterWidth, yPosition, (CGFloat)(kCPMTerminalViewWidth - startingColumn) * characterWidth, lineHeight));
		}
		yPosition -= lineHeight;
	}
	CGContextSetAllowsAntialiasing(context, true);

	// TODO: draw any graphics characters here

	// draw cursor?
	if(flashCount&1)
	{
		[[NSColor colorWithDeviceRed:0.0f green:0.5f blue:0.0f alpha:1.0f] set];
		NSRectFill(NSMakeRect(cursorX * characterWidth, (kCPMTerminalViewHeight - 1 - cursorY) * lineHeight, characterWidth, lineHeight));
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

	[self addStringToInputQueue:[pasteboard stringForType:NSPasteboardTypeString]];
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
	NSString *characters = [event characters];
	[self addStringToInputQueue:characters];
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

- (void)addStringToInputQueue:(NSString *)string
{
	@synchronized(self)
	{
		const char *asciiString = [string cStringUsingEncoding:NSASCIIStringEncoding];

		if(!asciiString) return;

		NSString *postAsciiString =
			[[[NSString alloc] initWithBytesNoCopy:(void *)asciiString length:strlen(asciiString) encoding:NSASCIIStringEncoding freeWhenDone:NO] autorelease];

		if(![postAsciiString length]) return;

		[incomingString appendString:postAsciiString];
		[self.delegate terminalViewDidAddCharactersToBuffer:self];
	}
}

@end
