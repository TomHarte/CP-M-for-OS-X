//
//  CPMTerminalView.m
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalView.h"
#import "TerminalControlSequence.h"
#import "TerminalControlSet+Actions.h"

#import "TerminalControlSet+ADM3A.h"
#import "TerminalControlSet+Hazeltine1500.h"
#import "TerminalControlSet+VT52.h"
#import "TerminalControlSet+Osborne.h"
#import "TerminalControlSet+ANSI.h"

@interface CPMTerminalView () <NSDraggingDestination>
@end

@implementation CPMTerminalView
{
	NSMutableAttributedString *_attributedString;
	NSMutableString *_incomingString;

	IntegerPoint _selectionStartPoint, _selectionCurrentPoint;
	NSTimeInterval _selectionStartTimeSinceReferenceDate;
	BOOL _hasSelection;

	CGFloat _lineHeight, _characterWidth;

//	int _flashCount;
//	NSTimer *_flashTimer;

	CPMTerminalControlSet *_controlSet;
	NSMutableArray *_candidateControlSets;
}

- (void)doCommonInit
{
	_incomingString = [[NSMutableString alloc] init];

	_candidateControlSets = [[NSMutableArray alloc] init];
	[_candidateControlSets addObject:[CPMTerminalControlSet ADM3AControlSet]];
	[_candidateControlSets addObject:[CPMTerminalControlSet osborneControlSet]];
	[_candidateControlSets addObject:[CPMTerminalControlSet hazeltine1500ControlSet]];
	[_candidateControlSets addObject:[CPMTerminalControlSet VT52ControlSet]];
	[_candidateControlSets addObject:[CPMTerminalControlSet ANSIControlSet]];

	for(CPMTerminalControlSet *set in _candidateControlSets)
	{
		set.isTrackingCodePoints = YES;
	}

	NSFont *monaco = [NSFont fontWithName:@"Monaco" size:12.0f];

	_lineHeight = (monaco.ascender - monaco.descender + monaco.leading);
	_characterWidth = [monaco advancementForGlyph:'M'].width;

	[self setControlSet:_candidateControlSets[0]];

//	_flashTimer = [NSTimer
//		scheduledTimerWithTimeInterval:0.9
//		target:self
//		selector:@selector(updateFlash:)
//		userInfo:nil
//		repeats:YES];
//	if([_flashTimer respondsToSelector:@selector(setTolerance:)])
//		[_flashTimer setTolerance:0.5];

	// accept drag and drop for filenames
	[self registerForDraggedTypes:@[@"public.file-url"]];
}

- (void)setControlSet:(CPMTerminalControlSet *)newControlSet
{
	NSUInteger oldWidth = _controlSet.width;
	NSUInteger oldHeight = _controlSet.height;
	_controlSet.delegate = nil;

	_controlSet = newControlSet;
	_controlSet.delegate = self;

	if(oldWidth != _controlSet.width || oldHeight != _controlSet.height)
	{
		_idealSize.width = _characterWidth * _controlSet.width;
		_idealSize.height = _lineHeight * _controlSet.height;

		if([self.delegate respondsToSelector:@selector(terminalViewDidChangeIdealRect:)])
			dispatch_async(dispatch_get_main_queue(),
			^{
				[self.delegate terminalViewDidChangeIdealRect:self];
			});
	}
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

- (void)invalidate
{
//	[_flashTimer invalidate], _flashTimer = nil;
}

- (void)writeCharacter:(char)character
{
	// perform accounting to decide who's ahead
	if([_candidateControlSets count])
	{
		// send the character to all control sets
		for(CPMTerminalControlSet *set in _candidateControlSets)
			[set writeCharacter:character];

		// sort by recognised percentage
		[_candidateControlSets sortUsingComparator:
			^NSComparisonResult(CPMTerminalControlSet *obj1, CPMTerminalControlSet *obj2)
			{
				NSUInteger recognisedQuantity1 = [[obj1 recognisedControlPoints] count];
				NSUInteger recognisedQuantity2 = [[obj2 recognisedControlPoints] count];

				if(recognisedQuantity1 < recognisedQuantity2) return NSOrderedDescending;
				if(recognisedQuantity1 > recognisedQuantity2) return NSOrderedAscending;
				return NSOrderedSame;
			}];

		// switch to the current best recogniser
		CPMTerminalControlSet *topSet = _candidateControlSets[0];
		if(topSet != _controlSet)
		{
			[self setControlSet:topSet];
			[self setNeedsDisplay:YES];
		}

		// if there's a suitably large margin between positions one and two, and
		// quite a few control codes have occurred then kill the rest of the list
		NSUInteger controlSetTotalRecognised = [[_controlSet recognisedControlPoints] count];
		if(controlSetTotalRecognised > 10)
		{
			// get all control points recognised to date
			NSMutableSet *allControlPoints = [NSMutableSet set];
			for(CPMTerminalControlSet *set in _candidateControlSets)
				[allControlPoints unionSet:[set recognisedControlPoints]];

			float totalPointsToDate = (float)[allControlPoints count];

			float recognisedPercentage1 = (float)controlSetTotalRecognised / totalPointsToDate;
			float recognisedPercentage2 = (float)[[_candidateControlSets[1] recognisedControlPoints] count] / totalPointsToDate;

			// if the topmost one is at least 20% ahead, or we've had at least 150 control codes
			// without establishing a clear winner then award victory and kill all the losers
			if(
				(recognisedPercentage1 > recognisedPercentage2 + 0.2f) ||
				(controlSetTotalRecognised > 150)
			)
			{
				_candidateControlSets = nil;
				_controlSet.isTrackingCodePoints = NO;
			}
		}
	}
	else
	{
		[_controlSet writeCharacter:character];
	}
}

- (NSColor *)colourWithIntensity:(CGFloat)intensity
{
	return [NSColor
		colorWithCalibratedRed:0.996f * intensity
		green:0.859f * intensity
		blue:0.055f * intensity
		alpha:1.0f];
}

- (NSColor *)fullIntensityColour
{
	return [self colourWithIntensity:1.0f];
}

- (NSColor *)halfIntensityColour
{
	return [self colourWithIntensity:0.66f];
}

- (NSColor *)zeroIntensityColour
{
	return [self colourWithIntensity:0.0f];
}

- (NSColor *)cursorColour
{
	return [self colourWithIntensity:0.5f];
}

- (void)viewWillDraw
{
	// create a string of the ASCII characters first
	NSString *asciiText = @((const char *)_controlSet.characterBuffer);
	_attributedString = [[NSMutableAttributedString alloc] initWithString:asciiText];

	// establish the whole range as Monaco 12
	CTFontRef monaco = CTFontCreateWithName((CFStringRef)@"Monaco", 12.0f, NULL);
	[_attributedString
		setAttributes:
		@{
			(id)kCTFontAttributeName : (__bridge id)monaco,
			(id)kCTForegroundColorAttributeName: (id)[[self fullIntensityColour] CGColor]
		}
		range:NSMakeRange(0, _attributedString.length)];
	CFRelease(monaco);

	uint16_t lastAttribute = 0;
	for(NSUInteger y = 0; y < _controlSet.height; y++)
	{
		uint16_t *attributes = [_controlSet attributeBufferForY:y];
		for(NSUInteger x = 0; x < _controlSet.width; x++)
		{
			uint16_t attribute = attributes[x];

			if(attribute != lastAttribute)
			{
				NSMutableDictionary *newAttributes = [NSMutableDictionary dictionary];
				uint16_t attributeChanges = attribute^lastAttribute;
				lastAttribute = attribute;

				if(
					attributeChanges & (CPMTerminalAttributeReducedIntensity | CPMTerminalAttributeInverseVideo)
				)
				{
					NSColor *textColour = nil;
					switch(attribute & (CPMTerminalAttributeReducedIntensity | CPMTerminalAttributeInverseVideo))
					{
						default:
							textColour = [self fullIntensityColour];
						break;
						case CPMTerminalAttributeReducedIntensity:
							textColour = [self halfIntensityColour];
						break;
						case CPMTerminalAttributeInverseVideo:
							textColour = [self zeroIntensityColour];
						break;
						case CPMTerminalAttributeInverseVideo | CPMTerminalAttributeReducedIntensity:
							textColour = [self zeroIntensityColour];
						break;
					}
					[newAttributes setValue:(id)[textColour CGColor] forKey:(id)kCTForegroundColorAttributeName];
				}

				if(attributeChanges & CPMTerminalAttributeUnderlined)
				{
					if(attribute & CPMTerminalAttributeUnderlined)
						[newAttributes setValue:@(kCTUnderlineStyleSingle) forKey:(id)kCTUnderlineStyleAttributeName];
					else
						[newAttributes setValue:@(kCTUnderlineStyleNone) forKey:(id)kCTUnderlineStyleAttributeName];
				}

				NSRange rangeFromHereToEnd;
				rangeFromHereToEnd.location = y*(_controlSet.width+1) + x;
				rangeFromHereToEnd.length = _attributedString.length - rangeFromHereToEnd.location;
				[_attributedString
					addAttributes:newAttributes
					range:rangeFromHereToEnd];
			}
		}
	}
}

- (BOOL)canBecomeKeyView		{	return YES;	}
- (BOOL)acceptsFirstResponder	{	return YES;	}
- (BOOL)isOpaque				{	return YES;	}

//- (void)updateFlash:(NSTimer *)timer
//{
//	_flashCount++;
//	[self setNeedsDisplay:YES];
//}

- (CGFloat)textScale
{
	NSRect bounds = [self bounds];
	CGFloat scalerX = bounds.size.width / _idealSize.width;
	CGFloat scalerY = bounds.size.height / _idealSize.height;
	return (scalerX > scalerY) ? scalerY : scalerX;
}

- (void)getSelectionStart:(IntegerPoint *)startPoint end:(IntegerPoint *)endPoint
{
	if(_selectionStartPoint.y < _selectionCurrentPoint.y || (_selectionStartPoint.y == _selectionCurrentPoint.y && _selectionStartPoint.x < _selectionCurrentPoint.x))
	{
		*startPoint = _selectionStartPoint;
		*endPoint = _selectionCurrentPoint;
	}
	else
	{
		*endPoint = _selectionStartPoint;
		*startPoint = _selectionCurrentPoint;
	}
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

	// work out scaler; get x and y scales separately then pick the smallest —
	// in effect this is an aspect fit
	const CGFloat scale = [self textScale];
	CGContextScaleCTM(context, scale, scale);

	// create a rect describing our entire frame in idealised coordinates
	CGRect idealRect;
	idealRect.origin = CGPointMake(0.0f, 0.0f);
	idealRect.size = _idealSize;

	// make sure the text matrix is the identity
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);

	// prepare Core Text
	CGContextSetShouldSmoothFonts(context, true);
	CGPathRef path = CGPathCreateWithRect(idealRect, NULL);
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)_attributedString);
	CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, (CFIndex)_attributedString.length), path, NULL);

	// disable antialiasing in order to draw inverse video and highlighting boxes
	CGContextSetAllowsAntialiasing(context, false);
	CGFloat yPosition = (_lineHeight * _controlSet.height) - _lineHeight;

	// get selection area
	IntegerPoint startPoint;
	IntegerPoint endPoint;
	[self getSelectionStart:&startPoint end:&endPoint];

	for(NSUInteger y = 0; y < _controlSet.height; y++)
	{
		uint8_t lastAttribute = 0;
		NSUInteger startingColumn = 0;
		NSColor *colour = nil;
		uint16_t *attributes = [_controlSet attributeBufferForY:y];

		for(NSUInteger x = 0; x < _controlSet.width; x++)
		{
			uint8_t attribute = attributes[x]&(CPMTerminalAttributeReducedIntensity | CPMTerminalAttributeInverseVideo);

			if(_hasSelection)
			{
				if(
					((y == startPoint.y) && (y < endPoint.y) && (x >= startPoint.x)) ||
					((y == endPoint.y) && (y > startPoint.y) && (x <= endPoint.x)) ||
					((y == startPoint.y) && (y == endPoint.y) && (x >= startPoint.x) && (x <= endPoint.x)) ||
					((y > startPoint.y) && (y < endPoint.y))
				)
				{
					attribute = CPMTerminalAttributeSelected;
				}
			}

			if(attribute != lastAttribute)
			{
				lastAttribute = attribute;
				if(colour)
				{
					[colour set];
					NSRectFill(NSMakeRect((CGFloat)startingColumn * _characterWidth, yPosition, (CGFloat)(x - startingColumn) * _characterWidth, _lineHeight));
				}
				startingColumn = x;

				switch(attribute)
				{
					default:
					case CPMTerminalAttributeReducedIntensity:
						colour = nil;
					break;
					case CPMTerminalAttributeInverseVideo:
						colour = [self fullIntensityColour];
					break;
					case CPMTerminalAttributeInverseVideo | CPMTerminalAttributeReducedIntensity:
						colour = [self halfIntensityColour];
					break;
					case CPMTerminalAttributeSelected:
						colour = [NSColor selectedTextBackgroundColor];
					break;
				}
			}
		}

		if(colour)
		{
			[colour set];
			NSRectFill(NSMakeRect((CGFloat)startingColumn * _characterWidth, yPosition, (CGFloat)(_controlSet.width - startingColumn) * _characterWidth, _lineHeight));
		}
		yPosition -= _lineHeight;
	}
	CGContextSetAllowsAntialiasing(context, true);

	// TODO: draw any graphics characters here

	// draw cursor?
	if(!_controlSet.cursorIsDisabled)	// _flashCount&1 && 
	{
		[[self cursorColour] set];
		NSRectFill(NSMakeRect(_controlSet.cursorX * _characterWidth, (_controlSet.height - 1 - _controlSet.cursorY) * _lineHeight, _characterWidth, _lineHeight));
	}

	// render the text
	CTFrameDraw(frame, context);

	// clean up
	CGPathRelease(path);
	CFRelease(framesetter);
	CFRelease(frame);
}

#pragma mark -
#pragma mark Copy/Paste Responder Actions
/*

	This view implements copy and paste so as to work with the pasteboard

*/
- (void)copy:(id)sender
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:self];

	if(_hasSelection)
	{
		IntegerPoint startPoint;
		IntegerPoint endPoint;
		size_t length;

		[self getSelectionStart:&startPoint end:&endPoint];
		const char *bytes = [_controlSet charactersBetweenStart:startPoint end:endPoint length:&length];

		NSString *const output = [[NSString alloc] initWithBytes:bytes length:length encoding:NSASCIIStringEncoding];

		[pasteboard setString:output forType:NSPasteboardTypeString];
	}
	else
	{
		[pasteboard setString:_attributedString.string forType:NSPasteboardTypeString];
	}
}

- (void)paste:(id)sender
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

	[self addStringToInputQueue:[pasteboard stringForType:NSPasteboardTypeString] filterToASCII:YES];
}

#pragma mark -
#pragma mark NSResponder

- (void)mouseDown:(NSEvent *)theEvent
{
	_selectionCurrentPoint = _selectionStartPoint = [self textLocationForEvent:theEvent];
	_hasSelection = YES;
	_selectionStartTimeSinceReferenceDate = [NSDate timeIntervalSinceReferenceDate];
	[self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	_selectionCurrentPoint = [self textLocationForEvent:theEvent];
	[self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)theEvent
{
	if([NSDate timeIntervalSinceReferenceDate] - _selectionStartTimeSinceReferenceDate < 0.5 && _selectionCurrentPoint.x == _selectionStartPoint.x && _selectionCurrentPoint.y == _selectionStartPoint.y)
	{
		_hasSelection = NO;
		[self setNeedsDisplay:YES];
	}
}

- (IntegerPoint)textLocationForEvent:(NSEvent *)event
{
	const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
	const CGFloat scale = [self textScale];
	const CGFloat boundsHeight = self.bounds.size.height;
	return integerPointMake((NSUInteger)(floor(location.x / (_characterWidth * scale))), (NSUInteger)(floor((boundsHeight - location.y) / (_lineHeight * scale))));
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

#pragma mark -
#pragma mark The Input Queue

- (BOOL)hasCharacterToDequeue
{
	return !!_incomingString.length;
}

- (unichar)dequeueBufferedCharacter
{
	if(!_incomingString.length) return 0;
	unichar character = [_incomingString characterAtIndex:0];
	[_incomingString deleteCharactersInRange:NSMakeRange(0, 1)];
	return character;
}

- (void)addStringToInputQueue:(NSString *)string filterToASCII:(BOOL)filterToASCII
{
	__weak typeof(self) weakSelf = self;

	dispatch_async(self.callingDispatchQueue,
	^{
		typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		NSString *filteredString = string;

		if(filterToASCII)
		{
			const char *asciiString = [string cStringUsingEncoding:NSASCIIStringEncoding];

			if(!asciiString) return;

			filteredString =
				[[NSString alloc] initWithBytesNoCopy:(void *)asciiString length:strlen(asciiString) encoding:NSASCIIStringEncoding freeWhenDone:NO];
		}

		if(![filteredString length]) return;
		[strongSelf->_incomingString appendString:filteredString];

		dispatch_async(dispatch_get_main_queue(),
		^{
			[weakSelf.delegate terminalViewDidAddCharactersToBuffer:self];
		});
	});
}

#pragma mark -
#pragma mark CPMTerminalControlSetDelegate

- (void)terminalViewControlSetDidChangeOutput:(CPMTerminalControlSet *)controlSet
{
	[self setNeedsDisplay:YES];
}

- (void)terminalViewControlSet:(CPMTerminalControlSet *)controlSet addStringToInput:(NSString *)string
{
	[self addStringToInputQueue:string filterToASCII:NO];
}

#pragma mark -
#pragma mark NSDraggingDestination

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	for(NSPasteboardItem *item in [[sender draggingPasteboard] pasteboardItems])
	{
		NSURL *URL = [NSURL URLWithString:[item stringForType:@"public.file-url"]];
		
		if([self.delegate respondsToSelector:@selector(terminalView:didReceiveFileAtURL:)])
			[self.delegate terminalView:self didReceiveFileAtURL:URL];
	}
	return YES;
}

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender
{
	// we'll drag and drop, yeah?
	return NSDragOperationLink;
}

@end
