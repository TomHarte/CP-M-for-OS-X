//
//  CPMTerminalView.m
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalView.h"
#import "TerminalControlSequence.h"

#define kCPMTerminalViewWidth	80
#define kCPMTerminalViewHeight	24

#define kCPMTerminalAttributeInverseVideoOn			0x01
#define kCPMTerminalAttributeReducedIntensityOn		0x02
#define kCPMTerminalAttributeBlinkingOn				0x04
#define kCPMTerminalAttributeUnderlinedOn			0x08

@implementation CPMTerminalView
{
	char srcBuffer[kCPMTerminalViewWidth * kCPMTerminalViewHeight];
	char attributes[kCPMTerminalViewWidth * kCPMTerminalViewHeight];
	int cursorX, cursorY, currentAttribute;

	NSMutableAttributedString *attributedString;
	NSMutableString *incomingString;

	int selectionStartX, selectionStartY, selectionCurrentX, selectionCurrentY;

	CGFloat lineHeight, characterWidth;

	int flashCount;
	NSTimer *flashTimer;

	uint8_t inputQueue[8];
	NSUInteger inputQueueWritePointer;
	NSUInteger longestSequence;

	NSMutableDictionary *sequencesToActions;
}

- (void)doCommonInit
{
	incomingString = [[NSMutableString alloc] init];

	NSFont *monaco = [NSFont fontWithName:@"Monaco" size:12.0f];

	lineHeight = (monaco.ascender - monaco.descender + monaco.leading);
	characterWidth = [monaco advancementForGlyph:'M'].width;
	_idealSize.width = characterWidth * kCPMTerminalViewWidth;
	_idealSize.height = lineHeight * kCPMTerminalViewHeight;

	flashTimer = [NSTimer
		scheduledTimerWithTimeInterval:1.0/2.5
		target:self
		selector:@selector(updateFlash:)
		userInfo:nil
		repeats:YES];

	[self clearFrom:0 to:kCPMTerminalViewHeight*kCPMTerminalViewWidth];

	sequencesToActions = [[NSMutableDictionary alloc] init];

	// install the ASCII control characters
	[self installASCIIControlCharacters];

	// install the ADM-3A control codes
	[self installADM3AControlCodes];

	// hence determine the longest sequence we have
	for(CPMTerminalControlSequence *controlSequence in [sequencesToActions allValues])
	{
		if(controlSequence.requiredLength > longestSequence)
			longestSequence = controlSequence.requiredLength;
	}
}

- (void)installASCIIControlCharacters
{
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x08"
			action:^{	if(cursorX > 0) cursorX--;							}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x0c"
			action:^{	if(cursorX < kCPMTerminalViewWidth-1) cursorX++;	}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\n"
			action:^{	[self incrementY];									}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\r"
			action:^{	cursorX = 0;										}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x0b"
			action:^{	if(cursorY > 0) cursorY--;							}]];

	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x17"
			action:^{	[self clearFrom:cursorY*kCPMTerminalViewWidth + cursorX to:kCPMTerminalViewWidth*kCPMTerminalViewHeight];		}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x18"
			action:^{	[self clearFrom:cursorY*kCPMTerminalViewWidth + cursorX to:(cursorY+1)*kCPMTerminalViewWidth];					}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x1a"
			action:
			^{
				cursorX = cursorY = 0;
				[self clearFrom:0 to:kCPMTerminalViewHeight*kCPMTerminalViewWidth];
			}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x1e"
			action:^{	cursorX = cursorY = 0;					}]];
}

- (void)installADM3AControlCodes
{
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33="
			requiredLength:4
			action:
			^{
				cursorY = (inputQueue[2] - 32)%kCPMTerminalViewHeight;
				cursorX = (inputQueue[3] - 32)%kCPMTerminalViewWidth;
			}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33B0"
			action:^{	currentAttribute |= kCPMTerminalAttributeInverseVideoOn;		}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33C0"
			action:^{	currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;		}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33B1"
			action:^{	currentAttribute |= kCPMTerminalAttributeReducedIntensityOn;	}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33C1"
			action:^{	currentAttribute &= ~kCPMTerminalAttributeReducedIntensityOn;	}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33B2"
			action:^{	currentAttribute |= kCPMTerminalAttributeBlinkingOn;			}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33C2"
			action:^{	currentAttribute &= ~kCPMTerminalAttributeBlinkingOn;			}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33B3"
			action:^{	currentAttribute |= kCPMTerminalAttributeUnderlinedOn;			}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33C3"
			action:^{	currentAttribute &= ~kCPMTerminalAttributeUnderlinedOn;			}]];
}

- (void)addControlSequence:(CPMTerminalControlSequence *)controlSequence
{
	[sequencesToActions setObject:controlSequence forKey:controlSequence.start];
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
	[sequencesToActions release], sequencesToActions = nil;
	[incomingString release], incomingString = nil;
	[attributedString release], attributedString = nil;
	[super dealloc];
}

- (void)invalidate
{
	[flashTimer invalidate], flashTimer = nil;
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
		// this enqueuing process has a quick safeguard against overflow
		inputQueue[inputQueueWritePointer++] = character;

		// if we've gone beyond the length of things we can match without
		// matching anything then just pop the first character
		if(inputQueueWritePointer > longestSequence)
		{
			inputQueueWritePointer--;
			memmove(inputQueue, &inputQueue[1], inputQueueWritePointer);
		}

		// output anything that's safe ASCII
		while(inputQueueWritePointer && (inputQueue[0] >= 32) && (inputQueue[0] < 128))
		{
			[self writeNormalCharacter:inputQueue[0]];
			inputQueueWritePointer--;
			memmove(inputQueue, &inputQueue[1], inputQueueWritePointer);
		}

		// have a go at matching what's left, if there is anything
		if(inputQueueWritePointer)
		{
			while(1)
			{
				NSString *attemptedString = [[NSString alloc] initWithBytes:inputQueue length:inputQueueWritePointer encoding:NSASCIIStringEncoding];
				CPMTerminalControlSequence *foundMatch = nil;

				while(attemptedString.length)
				{
					CPMTerminalControlSequence *potentialMatch =
						[sequencesToActions valueForKey:attemptedString];

					if(potentialMatch && potentialMatch.requiredLength <= inputQueueWritePointer)
					{
						foundMatch = potentialMatch;
						break;
					}

					attemptedString = [attemptedString substringToIndex:attemptedString.length-1];
				}

				if(!foundMatch) break;

				foundMatch.action();
				inputQueueWritePointer -= foundMatch.requiredLength;
				memmove(inputQueue, &inputQueue[foundMatch.requiredLength], inputQueueWritePointer);
			}
		}
	});
}

- (void)clearFrom:(int)start to:(int)end
{
	memset(&srcBuffer[start], 32, end-start);
	memset(&attributes[start], 0, end-start);
	[self setNeedsDisplay:YES];
//	currentAttribute = 0;
}

- (void)writeNormalCharacter:(char)character
{
	if(cursorX == kCPMTerminalViewWidth)
	{
		cursorX = 0;
		[self incrementY];
	}

	srcBuffer[(cursorY * kCPMTerminalViewWidth) + cursorX] = character;
	attributes[(cursorY * kCPMTerminalViewWidth) + cursorX] = currentAttribute;
	cursorX++;

	[self setNeedsDisplay:YES];
}

- (void)viewWillDraw
{
	// create a string of the ASCII characters first
	NSMutableString *asciiText = [NSMutableString stringWithCapacity:(kCPMTerminalViewWidth+1)*kCPMTerminalViewHeight];
	for(int y = 0; y < kCPMTerminalViewHeight; y++)
	{
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
