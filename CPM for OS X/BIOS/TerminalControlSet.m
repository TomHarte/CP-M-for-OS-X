//
//  CPMTerminaViewControlSet.m
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSequence.h"

@interface CPMTerminalControlSet ()
@property (nonatomic, assign) uint16_t currentAttribute;
@property (nonatomic, assign) uint8_t *inputQueue;
@property (nonatomic, assign) BOOL cursorIsDisabled;
@property (nonatomic, assign) int backupCursorX, backupCursorY;
@end

@implementation CPMTerminalControlSet
{
	uint8_t *characters;
	uint16_t *attributes;
	int cursorX, cursorY;

	NSUInteger inputQueueWritePointer;
	NSUInteger longestSequence;

	NSMutableDictionary *sequencesToActions;
	NSMutableSet *allSequenceStartCharacters;
}

#define address(x, y) (((y)*(self.width+1))+(x))
@synthesize cursorX, cursorY;

- (void)setIsTrackingCodePoints:(BOOL)isTrackingCodePoints
{
	[_recognisedControlPoints release], _recognisedControlPoints = nil;
	[_unrecognisedControlPoints release], _unrecognisedControlPoints = nil;

	if(isTrackingCodePoints)
	{
		_recognisedControlPoints = [[NSMutableSet alloc] init];
		_unrecognisedControlPoints = [[NSMutableSet alloc] init];
	}
}

- (BOOL)isTrackingCodePoints
{
	return _recognisedControlPoints ? YES : NO;
}

- (void)writeCharacter:(uint8_t)character
{
	// this enqueuing process has a quick safeguard against overflow
	self.inputQueue[inputQueueWritePointer++] = character;
	_numberOfCharactersSoFar++;

	// if we've gone beyond the length of things we can match without
	// matching anything then just pop the first character
	if(inputQueueWritePointer > longestSequence)
	{
		// this means we missed a code, probably
		[(NSMutableSet *)_unrecognisedControlPoints addObject:[NSNumber numberWithInteger:_numberOfCharactersSoFar]];

		// we'll attempt to output the first thing; some terminals (such as the Hazeltine 1500)
		// use a printable character as the first thing in an escape code...
		[self writeNormalCharacter:self.inputQueue[0]];
		inputQueueWritePointer--;
		memmove(self.inputQueue, &self.inputQueue[1], inputQueueWritePointer);
	}

	// output anything that's not possibly part of a control sequence
	while(inputQueueWritePointer && ![allSequenceStartCharacters containsObject:[NSNumber numberWithChar:self.inputQueue[0]]])
	{
		[self writeNormalCharacter:self.inputQueue[0]];
		inputQueueWritePointer--;
		memmove(self.inputQueue, &self.inputQueue[1], inputQueueWritePointer);
	}

	// have a go at matching what's left, if there is anything
	if(inputQueueWritePointer)
	{
		while(1)
		{
			NSString *attemptedString = [[[NSString alloc] initWithBytes:self.inputQueue length:inputQueueWritePointer encoding:NSASCIIStringEncoding] autorelease];
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
			[(NSMutableSet *)_recognisedControlPoints addObject:[NSNumber numberWithInteger:_numberOfCharactersSoFar]];

			// perform the sequence and remove the matched characters from the queue
			foundMatch.action();
			inputQueueWritePointer -= foundMatch.requiredLength;
			memmove(self.inputQueue, &self.inputQueue[foundMatch.requiredLength], inputQueueWritePointer);
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
	attributes[address(cursorX, cursorY)] = self.currentAttribute;

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

+ (id)ADM3AControlSet			{	return [[[self alloc] initWithControlSet:@selector(installADM3AControlCodes) width:80 height:24] autorelease];			}
+ (id)hazeltine1500ControlSet	{	return [[[self alloc] initWithControlSet:@selector(installHazeltine1500ControlCodes) width:80 height:24] autorelease];	}
+ (id)osborneControlSet			{	return [[[self alloc] initWithControlSet:@selector(installOsborneControlCodes) width:80 height:24] autorelease];		}
+ (id)VT52ControlSet			{	return [[[self alloc] initWithControlSet:@selector(installVT52ControlCodes) width:80 height:25] autorelease];			}

- (id)initWithControlSet:(SEL)selectorForControlSet width:(int)width height:(int)height
{
	self = [super init];

	if(self)
	{
		[self setupForWidth:width height:height];

		[self beginControlCodes];

			[self installASCIIControlCharacters];
			[self performSelector:selectorForControlSet];

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
	if(_inputQueue)
	{
		free(_inputQueue);
		_inputQueue = NULL;
	}
	[_recognisedControlPoints release], _recognisedControlPoints = nil;
	[_unrecognisedControlPoints release], _unrecognisedControlPoints = nil;
	[sequencesToActions release], sequencesToActions = nil;
	[allSequenceStartCharacters release], allSequenceStartCharacters = nil;

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

- (void)decrementY
{
	cursorY--;

	if(cursorY < 0)
	{
		// scroll all contents down a line
		memmove(&characters[self.width+1], characters, (self.height-1)*(self.width+1));
		memmove(&attributes[self.width+1], attributes, (self.height-1)*(self.width+1));

		// move the cursor back onto the screen
		cursorY ++;

		// blank out the new top line
		memset(&characters[address(0, 0)], 32, sizeof(uint8_t)*self.width);
		memset(&attributes[address(0, 0)], 0, sizeof(uint16_t)*self.width);

		// add a terminating NULL at the end
		characters[address(self.width, self.height-2)] = '\n';
	}
}

- (void)deleteLine
{
	if(cursorY < self.height-1)
	{
		// scroll all contents up a line
		memmove(&characters[address(0, cursorY)], &characters[address(0, cursorY+1)], (self.height-1-cursorY)*(self.width+1));
		memmove(&attributes[address(0, cursorY)], &attributes[address(0, cursorY+1)], (self.height-1-cursorY)*(self.width+1));

		// fix the terminating NULL that just ascended a position
		characters[address(self.width, self.height-2)] = '\n';
	}

	// blank out the new bottom line
	memset(&characters[address(0, self.height-1)], 32, sizeof(uint8_t)*self.width);
	memset(&attributes[address(0, self.height-1)], 0, sizeof(uint16_t)*self.width);
}

- (void)insertLine
{
	if(cursorY < self.height-1)
	{
		// scroll all contents down a line
		memmove(&characters[address(0, cursorY+1)], &characters[address(0, cursorY)], (self.height-1-cursorY)*(self.width+1));
		memmove(&attributes[address(0, cursorY+1)], &attributes[address(0, cursorY)], (self.height-1-cursorY)*(self.width+1));

		// fix the newline just descended a position
		characters[address(self.width, self.height-1)] = '\0';
	}

	// blank out this line
	memset(&characters[address(0, cursorY)], 32, sizeof(uint8_t)*self.width);
	memset(&attributes[address(0, cursorY)], 0, sizeof(uint16_t)*self.width);
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
	_inputQueue = (uint8_t *)malloc(sizeof(uint8_t) * longestSequence);
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
	if(cursorY < self.height-1)	[self setCursorX:cursorX y:cursorY+1];
}

- (void)leftCursor
{
	if(cursorX > 0)	[self setCursorX:cursorX-1 y:cursorY];
}

- (void)rightCursor
{
	if(cursorX < self.width-1)	[self setCursorX:cursorX+1 y:cursorY];
}

- (void)clearToEndOfScreen
{
	[self clearFrom:address(self.cursorX, self.cursorY) to:address(self.width, self.height-1)];
}

- (void)clearFromStartOfScreen
{
	[self clearFrom:address(0, 0) to:address(self.cursorX, self.cursorY)];
}

- (void)clearToEndOfLine
{
	[self clearFrom:address(self.cursorX, self.cursorY) to:address(self.width, self.cursorY)];
}

- (void)clearFromStartOfLine
{
	[self clearFrom:address(0, self.cursorY) to:address(self.cursorX, self.cursorY)];
}

- (void)saveCursorPosition
{
	_backupCursorX = cursorX;
	_backupCursorY = cursorY;
}

- (void)restoreCursorPosition
{
	cursorX = _backupCursorX;
	cursorY = _backupCursorY;

	// notify the delgate that we've visibly changed
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (void)setCursorIsDisabled:(BOOL)cursorIsDisabled
{
	if(_cursorIsDisabled == cursorIsDisabled) return;
	_cursorIsDisabled = cursorIsDisabled;

	// notify the delgate that we've visibly changed
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

typedef struct
{
	__unsafe_unretained NSString *start;
	NSUInteger requiredLength;
	dispatch_block_t action;
} CPMTerminalControlSequenceStruct;

- (void)installControlSequencesFromStructs:(CPMTerminalControlSequenceStruct *)structs
{
	while(structs->start)
	{
		if(structs->requiredLength)
		{
			[self addControlSequence:
				[CPMTerminalControlSequence
					terminalControlSequenceWithStart:structs->start
					requiredLength:structs->requiredLength
					action:structs->action]];
		}
		else
		{
			[self addControlSequence:
				[CPMTerminalControlSequence
					terminalControlSequenceWithStart:structs->start
					action:structs->action]];
		}

		structs++;
	}
}

- (void)installASCIIControlCharacters
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\n",	0,	^{	[weakSelf incrementY];						}},
		{@"\r",	0,	^{	[weakSelf setCursorX:0 y:weakSelf.cursorY];	}},
		{nil}
	};

	[self installControlSequencesFromStructs:sequences];
}

- (void)installADM3AControlCodes
{
	/*
		This is actually the pure ADM3A with some Kaypro extensions thrown
		in, I believe...
		
		Update! This may well just be the Kaypro. I'll need to look into this.
	*/
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\x0b",	0,	^{	[weakSelf upCursor];					}},
		{@"\x17",	0,	^{	[weakSelf clearToEndOfScreen];			}},
		{@"\x18",	0,	^{	[weakSelf clearToEndOfLine];			}},
		{@"\x1a",	0,	^{
							[weakSelf homeCursor];
							[weakSelf clearToEndOfScreen];
						}},
		{@"\x1e",	0,	^{	[weakSelf homeCursor];					}},
		{@"\x08",	0,	^{	[weakSelf leftCursor];					}},
		{@"\x0c",	0,	^{	[weakSelf rightCursor];					}},
		{@"\33=",	4,	^{
							[weakSelf
									setCursorX:(weakSelf.inputQueue[3] - 32)%weakSelf.width
									y:(weakSelf.inputQueue[2] - 32)%weakSelf.height];
						}},

		{@"\33B0",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeInverseVideoOn;		}},
		{@"\33C0",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;		}},
		{@"\33B1",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33C1",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33B2",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeBlinkingOn;			}},
		{@"\33C2",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeBlinkingOn;			}},
		{@"\33B3",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeUnderlinedOn;			}},
		{@"\33C3",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeUnderlinedOn;		}},

		{@"\33B4",	0,	^{	weakSelf.cursorIsDisabled = NO;			}},
		{@"\33C4",	0,	^{	weakSelf.cursorIsDisabled = YES;		}},

		{@"\33B6",	0,	^{	[weakSelf saveCursorPosition];			}},
		{@"\33C6",	0,	^{	[weakSelf restoreCursorPosition];		}},

		{@"\33R",	0,	^{	[weakSelf deleteLine];	}},
		{@"\33E",	0,	^{	[weakSelf insertLine];	}},
		{nil}
	};

	/*
		Unimplemented at present:

			(the graphics characters, 128–255)

			Video mode on/off                  B5/C5
			Status line preservation on/off    B7/C7

			Print pixel            *, row + 31, col + 31
			Erase pixel            #32 (space), row + 31, col + 31
			Print line             L, row1 + 31, col1 + 31, row2 + 31, col2 + 31
			Erase line             D, row1 + 31, col1 + 31, row2 + 31, col2 + 31

			Stop cursor blinking     OUT 28, 10: OUT 29, 0
			Turn cursor to underline OUT 28, 10: OUT 29, 15* 
	*/


	[self installControlSequencesFromStructs:sequences];
}

- (void)installHazeltine1500ControlCodes
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"~\5",	0,	^{
							dispatch_sync(dispatch_get_main_queue(),
							^{
								[weakSelf.delegate
									terminalViewControlSet:weakSelf
									addStringToInput:
										[NSString stringWithFormat:@"%c%c",
												weakSelf.cursorX,
												weakSelf.cursorY]];
							});
						}},
		{@"~\13",	0,	^{	[weakSelf downCursor];	}},
		{@"~\14",	0,	^{	[weakSelf upCursor];	}},
		{@"~\17",	0,	^{	[weakSelf clearToEndOfLine];	}},
		{@"~\21",	4,	^{
							[weakSelf
								setCursorX:weakSelf.inputQueue[2]%weakSelf.width
								y:weakSelf.inputQueue[3]%weakSelf.height];
						}},
		{@"~\22",	0,	^{	[weakSelf homeCursor];	}},
		{@"~\23",	0,	^{	[weakSelf deleteLine];			}},
		{@"~\30",	0,	^{	[weakSelf clearToEndOfScreen];	}},
		{@"~\31",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeBackground;	}},
		{@"~\32",	0,	^{	[weakSelf insertLine];			}},
		{@"~\34",	0,	^{
							[weakSelf homeCursor];
							[weakSelf clearToEndOfScreen];
						}},
		{@"~\37",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeBackground;	}},
		{nil}
	};

	/*
		Unimplemented:

			right cursor		dec 16
			clear foreground	~ dec 29
			clear to end-of-screen - background spaces	~ dec 23
			keyboard lock		~ dec 21
			keyboard unlock		~ dec 6
			(alarm and tab)

	*/

	[self installControlSequencesFromStructs:sequences];
}

- (void)installOsborneControlCodes
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\x08",	0,	^{	[weakSelf leftCursor];	}},	// i.e. ^H
		{@"\x0c",	0,	^{	[weakSelf rightCursor];	}},	// i.e. ^L
		{@"\x0b",	0,	^{	[weakSelf upCursor];	}},	// i.e. ^K
		{@"\x1a",	0,	^{
							[weakSelf homeCursor];
							[weakSelf clearToEndOfScreen];
						}},								// i.e. ^Z
		{@"\x1e",	0,	^{	[weakSelf homeCursor];	}},
		{@"\33=",	4,	^{
							[weakSelf
									setCursorX:(weakSelf.inputQueue[3] - 32)%weakSelf.width
									y:(weakSelf.inputQueue[2] - 32)%weakSelf.height];
						}},
		{@"\33T",	0,	^{	[weakSelf clearToEndOfLine];	}},

		{@"\33)",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33(",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33L",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeUnderlinedOn;			}},
		{@"\33M",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeUnderlinedOn;		}},

		{@"\33E",	0,	^{	[weakSelf insertLine];			}},
		{@"\33R",	0,	^{	[weakSelf deleteLine];			}},
		{nil}
	};

	/*
		Unimplemented at present:
		
			07		^G		rings the bell
			1b 23	ESC #	locks keyboard
			1b 22	ESC "	unlocks keyboard
			1b 53	ESC S	screen XY positioning
			1b 51	ESC Q	insert character
			1b 57	ESC W	delete character
			1b 67	ESC g	start graphics display
			1b 47	ESC G	end graphics display
			1b 5b	ESC [	homes screen
	*/

	[self installControlSequencesFromStructs:sequences];
}

- (void)installVT52ControlCodes
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\33A",	0,	^{	[weakSelf upCursor];	}},
		{@"\33B",	0,	^{	[weakSelf downCursor];	}},
		{@"\33C",	0,	^{	[weakSelf rightCursor];	}},
		{@"\33D",	0,	^{	[weakSelf leftCursor];	}},
		{@"\33E",	0,	^{
							[weakSelf homeCursor];
							[weakSelf clearToEndOfScreen];
						}},
		{@"\33H",	0,	^{	[weakSelf homeCursor];	}},
		{@"\33I",	0,	^{	[weakSelf decrementY];	}},
		{@"\33J",	0,	^{	[weakSelf clearToEndOfScreen];	}},
		{@"\33K",	0,	^{	[weakSelf clearToEndOfLine];	}},
		{@"\33L",	0,	^{	[weakSelf insertLine];	}},
		{@"\33M",	0,	^{	[weakSelf deleteLine];	}},
		{@"\33Y",	4,	^{
							[weakSelf
									setCursorX:(weakSelf.inputQueue[3] - 32)%weakSelf.width
									y:(weakSelf.inputQueue[2] - 32)%weakSelf.height];
						}},
		// ESC b — select font colour
		// ESC c — select background colour
		{@"\33d",	0,	^{	[weakSelf clearFromStartOfScreen];	}},
		{@"\33e",	0,	^{	weakSelf.cursorIsDisabled = NO;		}},
		{@"\33f",	0,	^{	weakSelf.cursorIsDisabled = YES;	}},
		{@"\33j",	0,	^{	[weakSelf saveCursorPosition];		}},
		{@"\33k",	0,	^{	[weakSelf restoreCursorPosition];	}},
		{@"\33l",	0,	^{
							[weakSelf setCursorX:0 y:weakSelf.cursorY];
							[weakSelf clearToEndOfLine];
						}},
		{@"\33o",	0,	^{	[weakSelf clearFromStartOfLine];	}},
		{@"\33p",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeInverseVideoOn;	}},
		{@"\33q",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;	}},
		// ESC v - automatic overflow on
		// ESC w - automatic overflow off
		{nil}
	};

	[self installControlSequencesFromStructs:sequences];
}

@end
