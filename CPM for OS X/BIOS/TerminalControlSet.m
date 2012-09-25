//
//  CPMTerminaViewControlSet.m
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSequence.h"

@implementation CPMTerminalControlSet
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
@synthesize cursorX, cursorY;

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
	_numberOfCharactersSoFar++;

	// if we've gone beyond the length of things we can match without
	// matching anything then just pop the first character
	if(inputQueueWritePointer > longestSequence)
	{
		// this means we missed a code, probably
		[_unrecognisedCodePoints addObject:[NSNumber numberWithInteger:_numberOfCharactersSoFar]];
		
		inputQueueWritePointer--;
		memmove(inputQueue, &inputQueue[1], inputQueueWritePointer);
	}

	// output anything that's not possibly part of a control sequence
	while(inputQueueWritePointer && ![allSequenceStartCharacters containsObject:[NSNumber numberWithChar:inputQueue[0]]])
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

			// record that we recognised a control sequence
			[_recognisedCodePoints addObject:[NSNumber numberWithInteger:_numberOfCharactersSoFar]];

			// perform the sequence and remove the matched characters from the queue
			foundMatch.action();
			inputQueueWritePointer -= foundMatch.requiredLength;
			memmove(inputQueue, &inputQueue[foundMatch.requiredLength], inputQueueWritePointer);
		}
	}
}

- (void)writeNormalCharacter:(char)character
{
	// if it's not one of the ASCII printables then, for now, render it as a space
	// (TODO: put these somewhere else so that we can do graphics output)
	if(character < 0x20 || character > 0x7e) character = ' ';

	// write the character, with the current attribute
	characters[address(cursorX, cursorY)] = character;
	attributes[address(cursorX, cursorY)] = currentAttribute;

	// increment x and increment y if necessary
	cursorX++;
	if(cursorX == self.width)
	{
		cursorX = 0;
		[self incrementY];
	}

	// tell the delegate that the output has changed
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (void)setCursorX:(int)newCursorX y:(int)newCursorY
{
	cursorX = newCursorX;
	cursorY = newCursorY;

	// tell the delegate that the output has changed; TODO: check
	// that the cursor is currently enabled before doing this
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (uint8_t *)characterBuffer				{	return characters;	}
- (uint16_t *)attributeBufferForY:(int)y
{
	return &attributes[address(0, y)];
}

- (void)setupForWidth:(int)width height:(int)height
{
	// store width and height
	_width = width;
	_height = height;

	// allocate storage area for the display
	characters = (uint8_t *)calloc((width+1)*height, sizeof(uint8_t));
	attributes = (uint16_t *)calloc((width+1)*height, sizeof(uint16_t));

	// set everything to spaces, initially
	memset(characters, ' ', (width+1)*height);

	// write in new lines
	for(int y = 0; y < height; y++)
	{
		characters[address(self.width, y)] = '\n';
	}

	// write in NULL terminator
	characters[address(self.width, self.height-1)] = '\0';
}

+ (id)ADM3AControlSet			{	return [[[self alloc] initWithADM3AControlSet] autorelease];			}
+ (id)hazeltine1500ControlSet	{	return [[[self alloc] initWithHazeltine1500ControlSet] autorelease];	}

- (id)initWithADM3AControlSet
{
	self = [super init];

	if(self)
	{
		[self setupForWidth:80 height:24];

		[self beginControlCodes];

			[self installASCIIControlCharacters];
			[self installADM3AControlCodes];

		[self finishControlCodes];
	}

	return self;
}

- (id)initWithHazeltine1500ControlSet
{
	self = [super init];

	if(self)
	{
		[self setupForWidth:80 height:24];

		[self beginControlCodes];

			[self installHazeltine1500ControlCodes];

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

		// remove the terminating NULL that just ascended a position
		characters[address(self.width, self.height-2)] = '\n';
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

	// make sure we're still ending on a NULL
	characters[address(self.width, self.height-1)] = '\0';

	// notify the delgate that we've visibly changed
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (void)addControlSequence:(CPMTerminalControlSequence *)controlSequence
{
	[sequencesToActions setObject:controlSequence forKey:controlSequence.start];
}

- (void)beginControlCodes
{
	sequencesToActions = [[NSMutableDictionary alloc] init];
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

- (void)homeCursor
{
	[self setCursorX:0 y:0];
}

- (void)upCursor
{
	if(cursorY > 0) [self setCursorX:cursorX y:cursorY-1];
}

- (void)downCursor
{
	if(cursorX < self.height-1)	[self setCursorX:cursorX y:cursorY+1];
}

- (void)leftCursor
{
	if(cursorX > 0)	[self setCursorX:cursorX-1 y:cursorY];
}

- (void)rightCursor
{
	if(cursorX < self.width-1)	[self setCursorX:cursorX+1 y:cursorY];
}

- (void)installASCIIControlCharacters
{
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x08"
			action:^{	[self leftCursor];				}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x0c"
			action:^{	[self rightCursor];	}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\n"
			action:^{	[self incrementY];													}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\r"
			action:^{	[self setCursorX:0 y:cursorY];										}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x0b"
			action:^{	[self upCursor];				}]];

	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x17"
			action:^{	[self clearFrom:address(cursorX, cursorY) to:address(self.width, self.height-1)];		}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x18"
			action:^{	[self clearFrom:address(cursorX, cursorY) to:address(0, cursorY+1)];				}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x1a"
			action:
			^{
				[self setCursorX:0 y:0];
				[self clearFrom:address(0, 0) to:address(self.width, self.height-1)];
			}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\x1e"
			action:^{	[self setCursorX:0 y:0];			}]];
}

- (void)installADM3AControlCodes
{
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"\33="
			requiredLength:4
			action:
			^{
				[self setCursorX:(inputQueue[3] - 32)%self.width y:(inputQueue[2] - 32)%self.height];
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

- (void)installHazeltine1500ControlCodes
{
	// position cursor
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\21"
			requiredLength:4
			action:
			^{
				[self setCursorX:inputQueue[2]%self.width y:inputQueue[3]%self.height];
			}]];

	// read cursor address
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\5"
			action:
			^{
				dispatch_sync(dispatch_get_main_queue(),
				^{
					[self.delegate terminalViewControlSet:self addStringToInput:[NSString stringWithFormat:@"%c%c", cursorX, cursorY]];
				});
			}]];

	// home cursor
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\22"
			action:^{	[self homeCursor];			}]];

	// cursor up and down
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\14"
			action:^{	[self upCursor];			}]];
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\13"
			action:^{	[self downCursor];			}]];

	// clear screen
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\34"
			action:^{	[self clearFrom:address(0, 0) to:address(self.width, self.height-1)];		}]];

	// clear to end of line
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\17"
			action:^{	[self clearFrom:address(cursorX, cursorY) to:address(self.width-1, cursorY)];		}]];

	// clear to end of screen
	[self addControlSequence:
		[CPMTerminalControlSequence
			terminalControlSequenceWithStart:@"~\30"
			action:^{	[self clearFrom:address(cursorX, cursorY) to:address(self.width-1, self.height-1)];		}]];
}

@end
