//
//  CPMTerminaViewControlSet.m
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminaViewControlSet.h"
#import "TerminalControlSequence.h"

@implementation CPMTerminaViewControlSet
{
	uint8_t *characters;
	uint16_t *attributes, currentAttribute;
	int cursorX, cursorY;

	NSMutableSet *_recognisedCodePoints, *_unrecognisedCodePoints;
	NSUInteger _numberOfCharactersSoFar;

	uint8_t *inputQueue;
	NSUInteger inputQueueWritePointer;
	NSUInteger longestSequence;

	NSMutableDictionary *sequencesToActions;
	NSMutableSet *allSequenceStartCharacters;
}

#define address(x, y) (((y)*(self.width+1))+(x))

- (void)setIsTrackingCodePoints:(BOOL)isTrackingCodePoints
{
	[_recognisedCodePoints release], _recognisedCodePoints = nil;
	[_unrecognisedCodePoints release], _unrecognisedCodePoints = nil;

	if(isTrackingCodePoints)
	{
		_recognisedCodePoints = [[NSMutableSet alloc] init];
		_unrecognisedCodePoints = [[NSMutableSet alloc] init];
	}
}

- (BOOL)isTrackingCodePoints
{
	return _recognisedCodePoints ? YES : NO;
}

- (void)writeCharacter:(uint8_t)character
{
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
}

- (void)writeNormalCharacter:(char)character
{
	characters[address(cursorX, cursorY)] = character;
	attributes[address(cursorX, cursorY)] = currentAttribute;

	cursorX++;
	if(cursorX == self.width)
	{
		cursorX = 0;
		[self incrementY];
	}

	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (uint8_t *)characterBuffer				{	return characters;	}
- (uint16_t *)attributeBuffer				{	return attributes;	}

- (void)setupForWidth:(int)width height:(int)height
{
	// allocate storage area for the display
	characters = (uint8_t *)calloc(width*(height+1), sizeof(uint8_t));
	attributes = (uint16_t *)calloc(width*(height+1), sizeof(uint16_t));
}

+ (id)ADM3AControlSet
{
	return [[[[self class] alloc] initWithADM3AControlSet] autorelease];
}

- (id)initWithADM3AControlSet
{
	self = [super init];

	if(self)
	{
		[self setupForWidth:80 height:24];

		[self installASCIIControlCharacters];
		[self installADM3AControlCodes];

		[self finishControlCodes];
	}

	return self;
}

- (void)dealloc
{
	if(characters)
	{
		free(characters);
		characters = NULL;
	}
	if(attributes)
	{
		free(attributes);
		attributes = NULL;
	}
	if(inputQueue)
	{
		free(inputQueue);
		inputQueue = NULL;
	}
	[_recognisedCodePoints release], _recognisedCodePoints = nil;
	[_unrecognisedCodePoints release], _unrecognisedCodePoints = nil;
	[sequencesToActions release], sequencesToActions = nil;

	[super dealloc];
}

- (void)incrementY
{
	cursorY++;

	if(cursorY == self.height)
	{
		// scroll all contents up a line
		memmove(characters, &characters[self.width+1], (self.height-1)*(self.width+1));
		memmove(attributes, &attributes[self.width+1], (self.height-1)*(self.width+1));

		// move the cursor back onto the screen
		cursorY --;

		// blank out the new bottom line
		memset(&characters[address(0, cursorY)], 32, sizeof(uint8_t)*self.width);
		memset(&attributes[address(0, cursorY)], 0, sizeof(uint16_t)*self.width);
	}
}

- (void)clearFrom:(size_t)start to:(size_t)end
{
	// write out spaces and zero attributes
	memset(&characters[start], 32, sizeof(uint8_t)*(end-start));
	memset(&attributes[start], 0, sizeof(uint16_t)*(end-start));

	// put end-of-line markers back in
	size_t startLine = start / (self.width+1);
	size_t endLine = end / (self.width+1);
	for(size_t line = startLine; line < endLine; line++)
		characters[address(self.width, line)] = '\n';

	// notify the delgate that we've visibly changed
	[self.delegate terminalViewControlSetDidChangeOutput:self];
}

- (void)addControlSequence:(CPMTerminalControlSequence *)controlSequence
{
	[sequencesToActions setObject:controlSequence forKey:controlSequence.start];
}

- (void)finishControlCodes
{
	allSequenceStartCharacters = [[NSMutableSet alloc] init];
	longestSequence = 1;

	// determine the longest sequence we have, and build the set
	// of all control sequence start characters
	for(CPMTerminalControlSequence *controlSequence in [sequencesToActions allValues])
	{
		[allSequenceStartCharacters addObject:[NSNumber numberWithChar:[controlSequence.start characterAtIndex:0]]];

		if(controlSequence.requiredLength > longestSequence)
			longestSequence = controlSequence.requiredLength;
	}

	// hence allocate the input queue
	inputQueue = (uint8_t *)malloc(sizeof(uint8_t) * longestSequence);
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
			action:^{	if(cursorX < self.width-1) cursorX++;				}]];
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
			action:^{	[self clearFrom:address(cursorX, cursorY) to:address(self.width, self.height)];		}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x18"
			action:^{	[self clearFrom:address(cursorX, cursorY) to:address(0, cursorY+1)];				}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x1a"
			action:
			^{
				cursorX = cursorY = 0;
				[self clearFrom:address(0, 0) to:address(self.width, self.height)];
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
				cursorY = (inputQueue[2] - 32)%self.height;
				cursorX = (inputQueue[3] - 32)%self.width;
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

@end
