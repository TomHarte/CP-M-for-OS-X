//
//  CPMTerminaViewControlSet.m
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSequence.h"
#import "TerminalControlSequenceTree.h"

@implementation CPMTerminalControlSet
{
	char *_characters;
	uint16_t *_attributes;

	NSUInteger _inputQueueWritePointer;
	NSUInteger _longestSequence;
	CPMTerminalControlSequenceTree *_sequenceTree;
	NSMutableArray *_allControlSequences;

	NSUInteger _backupCursorX, _backupCursorY;
}

#define address(x, y) (size_t)(((y)*(self.width+1))+(x))

- (void)setIsTrackingCodePoints:(BOOL)isTrackingCodePoints
{
	_recognisedControlPoints = nil;
	_unrecognisedControlPoints = nil;

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

- (void)writeCharacter:(char)character
{
	// this enqueuing process has a quick safeguard against overflow
	self.inputQueue[_inputQueueWritePointer++] = character;
	_numberOfCharactersSoFar++;

	// if we've gone beyond the length of things we can match without
	// matching anything then just pop the first character
	if(_inputQueueWritePointer > _longestSequence)
	{
		// this means we missed a code, probably
		[(NSMutableSet *)_unrecognisedControlPoints addObject:@(_numberOfCharactersSoFar)];

		// we'll attempt to output the first thing; some terminals (such as the Hazeltine 1500)
		// use a printable character as the first thing in an escape code...
		[self writeNormalCharacter:self.inputQueue[0]];
		_inputQueueWritePointer--;
		memmove(self.inputQueue, &self.inputQueue[1], _inputQueueWritePointer);
	}

	while(_inputQueueWritePointer)
	{
		NSString *attemptedString = [[NSString alloc] initWithBytes:self.inputQueue length:_inputQueueWritePointer encoding:NSASCIIStringEncoding];

		CPMTerminalControlSequence *foundMatch = [_sequenceTree sequenceMatchingString:attemptedString];

		if(foundMatch == [CPMTerminalControlSequenceTree mightFindSentinel])
			break;

		if(foundMatch == [CPMTerminalControlSequenceTree cantFindSentinel])
		{
			[self writeNormalCharacter:self.inputQueue[0]];
			_inputQueueWritePointer--;
			memmove(self.inputQueue, &self.inputQueue[1], _inputQueueWritePointer);
		}
		else
		{
			// record that we recognised a control sequence
			[(NSMutableSet *)_recognisedControlPoints addObject:@(_numberOfCharactersSoFar)];

			// perform the sequence and remove the matched characters from the queue
			foundMatch.action();
			_inputQueueWritePointer -= foundMatch.pattern.length;
			memmove(self.inputQueue, &self.inputQueue[foundMatch.pattern.length], _inputQueueWritePointer);
		}
	}
}

- (void)writeNormalCharacter:(char)character
{
	// if it's not one of the ASCII printables then, for now, render it as a space
	// (TODO: put these somewhere else so that we can do graphics output)
	if(character < 0x20 || character > 0x7e) character = ' ';

	// write the character, with the current attribute
	_characters[address(_cursorX, _cursorY)] = character;
	_attributes[address(_cursorX, _cursorY)] = self.currentAttribute;

	// increment x and increment y if necessary
	_cursorX++;
	if(_cursorX == self.width)
	{
		_cursorX = 0;
		[self incrementY];
	}

	// tell the delegate that the output has changed
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (void)setCursorX:(NSUInteger)newCursorX y:(NSUInteger)newCursorY
{
	_cursorX = newCursorX;
	_cursorY = newCursorY;

	// tell the delegate that the output has changed; TODO: check
	// that the cursor is currently enabled before doing this
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (const char *)characterBuffer				{	return _characters;	}
- (uint16_t *)attributeBufferForY:(NSUInteger)y
{
	return &_attributes[address(0, y)];
}

- (const char *)charactersBetweenStart:(IntegerPoint)start end:(IntegerPoint)end length:(size_t *)length
{
	const char *charactersStart = &_characters[address(start.x, start.y)];
	const char *charactersEnd = &_characters[address(end.x, end.y)];

	*length = (size_t)(charactersEnd - charactersStart + 1);
	return charactersStart;
}

- (void)setupForWidth:(NSUInteger)width height:(NSUInteger)height
{
	// store width and height
	_width = width;
	_height = height;

	// allocate storage area for the display
	_characters = (char *)calloc((width+1)*height, sizeof(char));
	_attributes = (uint16_t *)calloc((width+1)*height, sizeof(uint16_t));

	// set everything to spaces, initially
	memset(_characters, ' ', (width+1)*height);

	// write in new lines
	for(NSUInteger y = 0; y < height; y++)
	{
		_characters[address(self.width, y)] = '\n';
	}

	// write in NULL terminator
	_characters[address(self.width, self.height-1)] = '\0';
}


- (id)initWithControlSet:(SEL)selectorForControlSet width:(NSUInteger)width height:(NSUInteger)height
{
	self = [super init];

	if(self)
	{
		[self setupForWidth:width height:height];

		[self beginControlCodes];

			[self installASCIIControlCharacters];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			[self performSelector:selectorForControlSet];
#pragma clang diagnostic pop

		[self finishControlCodes];
	}

	return self;
}

- (void)dealloc
{
	if(_characters)
	{
		free(_characters);
		_characters = NULL;
	}
	if(_attributes)
	{
		free(_attributes);
		_attributes = NULL;
	}
	if(_inputQueue)
	{
		free(_inputQueue);
		_inputQueue = NULL;
	}
}

- (void)incrementY
{
	_cursorY++;

	if(_cursorY == self.height)
	{
		// scroll all contents up a line
		memmove(_characters, &_characters[self.width+1], (self.height-1)*(self.width+1));
		memmove(_attributes, &_attributes[self.width+1], (self.height-1)*(self.width+1));

		// move the cursor back onto the screen
		_cursorY --;

		// blank out the new bottom line
		memset(&_characters[address(0, _cursorY)], 32, sizeof(uint8_t)*self.width);
		memset(&_attributes[address(0, _cursorY)], 0, sizeof(uint16_t)*self.width);

		// remove the terminating NULL that just ascended a position
		_characters[address(self.width, self.height-2)] = '\n';
	}
}

- (void)decrementY
{
	if(_cursorY)
		_cursorY--;
	else
	{
		// scroll all contents down a line
		memmove(&_characters[self.width+1], _characters, (self.height-1)*(self.width+1));
		memmove(&_attributes[self.width+1], _attributes, (self.height-1)*(self.width+1));

		// blank out the new top line
		memset(&_characters[address(0, 0)], 32, sizeof(uint8_t)*self.width);
		memset(&_attributes[address(0, 0)], 0, sizeof(uint16_t)*self.width);

		// add a terminating NULL at the end
		_characters[address(self.width, self.height-2)] = '\n';
	}
}

- (void)deleteLine
{
	if(_cursorY < self.height-1)
	{
		// scroll all contents up a line
		memmove(&_characters[address(0, _cursorY)], &_characters[address(0, _cursorY+1)], (self.height-1-_cursorY)*(self.width+1));
		memmove(&_attributes[address(0, _cursorY)], &_attributes[address(0, _cursorY+1)], (self.height-1-_cursorY)*(self.width+1));

		// fix the terminating NULL that just ascended a position
		_characters[address(self.width, self.height-2)] = '\n';
	}

	// blank out the new bottom line
	memset(&_characters[address(0, self.height-1)], 32, sizeof(uint8_t)*self.width);
	memset(&_attributes[address(0, self.height-1)], 0, sizeof(uint16_t)*self.width);
}

- (void)insertLine
{
	if(_cursorY < self.height-1)
	{
		// scroll all contents down a line
		memmove(&_characters[address(0, _cursorY+1)], &_characters[address(0, _cursorY)], (self.height-1-_cursorY)*(self.width+1));
		memmove(&_attributes[address(0, _cursorY+1)], &_attributes[address(0, _cursorY)], (self.height-1-_cursorY)*(self.width+1));

		// fix the newline just descended a position
		_characters[address(self.width, self.height-1)] = '\0';
	}

	// blank out this line
	memset(&_characters[address(0, _cursorY)], 32, sizeof(uint8_t)*self.width);
	memset(&_attributes[address(0, _cursorY)], 0, sizeof(uint16_t)*self.width);
}

- (void)clearFrom:(size_t)start to:(size_t)end
{
	// write out spaces and zero attributes
	memset(&_characters[start], 32, sizeof(uint8_t)*(end-start));
	memset(&_attributes[start], 0, sizeof(uint16_t)*(end-start));

	// put end-of-line markers back in
	size_t startLine = start / (self.width+1);
	size_t endLine = end / (self.width+1);
	for(size_t line = startLine; line < endLine; line++)
		_characters[address(self.width, line)] = '\n';

	// make sure we're still ending on a NULL
	_characters[address(self.width, self.height-1)] = '\0';

	// notify the delgate that we've visibly changed
	dispatch_async(dispatch_get_main_queue(),
	^{
		[self.delegate terminalViewControlSetDidChangeOutput:self];
	});
}

- (void)addControlSequence:(CPMTerminalControlSequence *)controlSequence
{
	[_allControlSequences addObject:controlSequence];
}

- (void)beginControlCodes
{
	_allControlSequences = [NSMutableArray new];
}

- (void)finishControlCodes
{
	// determine the longest sequence we have, and build the tree
	// of all control sequence start characters
	_sequenceTree = [[CPMTerminalControlSequenceTree alloc] initWithControlSequences:_allControlSequences];
	_longestSequence = [[_allControlSequences valueForKeyPath:@"@max.pattern.length"] unsignedIntegerValue];

	// release temporary storage
	_allControlSequences = nil;

	// hence allocate the input queue
	_inputQueue = (char *)malloc(sizeof(char) * _longestSequence);
}

- (void)homeCursor
{
	[self setCursorX:0 y:0];
}

- (void)upCursor
{
	if(_cursorY > 0) [self setCursorX:_cursorX y:_cursorY-1];
}

- (void)downCursor
{
	if(_cursorY < self.height-1)	[self setCursorX:_cursorX y:_cursorY+1];
}

- (void)leftCursor
{
	if(_cursorX > 0)	[self setCursorX:_cursorX-1 y:_cursorY];
}

- (void)rightCursor
{
	if(_cursorX < self.width-1)	[self setCursorX:_cursorX+1 y:_cursorY];
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
	_backupCursorX = _cursorX;
	_backupCursorY = _cursorY;
}

- (void)restoreCursorPosition
{
	_cursorX = _backupCursorX;
	_cursorY = _backupCursorY;

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

- (void)installControlSequencesFromStructs:(CPMTerminalControlSequenceStruct *)structs
{
	while(structs->pattern)
	{
		[self addControlSequence:
			[[CPMTerminalControlSequence alloc]
				initWithPattern:structs->pattern
				action:structs->action]];

		structs++;
	}
}

- (void)installASCIIControlCharacters
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\n",	^{	[weakSelf incrementY];						}},
		{@"\r",	^{	[weakSelf setCursorX:0 y:weakSelf.cursorY];	}},
		{@"\a",	^{	NSBeep();									}},
		{nil}
	};

	[self installControlSequencesFromStructs:sequences];
}

@end
