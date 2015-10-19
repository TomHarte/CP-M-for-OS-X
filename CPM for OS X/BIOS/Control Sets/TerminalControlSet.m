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
#import "TerminalControlSet+Actions.h"

@implementation CPMTerminalControlSet
{
	uint8_t *_inputQueue;
	char *_characters;
	uint16_t *_attributes;

	NSUInteger _inputQueueWritePointer;
	CPMTerminalControlSequenceTree *_sequenceTree;

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
	_inputQueue[_inputQueueWritePointer++] = (uint8_t)character;
	_numberOfCharactersSoFar++;

	// pull recognised sequences as they're found
	while(_inputQueueWritePointer)
	{
		CPMTerminalControlSequence *foundMatch = [_sequenceTree sequenceMatchingBytes:_inputQueue length:_inputQueueWritePointer];

		// might find => more input needed. So wait.
		if(foundMatch == [CPMTerminalControlSequenceTree mightFindSentinel])
			break;

		// can't find => will never match. So output a character
		if(foundMatch == [CPMTerminalControlSequenceTree cantFindSentinel])
		{
			[self writeNormalCharacter:(char)_inputQueue[0]];
			_inputQueueWritePointer--;
			memmove(_inputQueue, &_inputQueue[1], _inputQueueWritePointer);
		}
		else
		{
			// okay, found something. Record that we recognised a control sequence.
			[(NSMutableSet *)_recognisedControlPoints addObject:@(_numberOfCharactersSoFar)];

			// perform the sequence and remove the matched characters from the queue
			foundMatch.action(self, (char *)_inputQueue);
			_inputQueueWritePointer -= foundMatch.pattern.length;
			memmove(_inputQueue, &_inputQueue[foundMatch.pattern.length], _inputQueueWritePointer);
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


- (id)initWithControlSequences:(NSArray<CPMTerminalControlSequence *> *)sequences width:(NSUInteger)width height:(NSUInteger)height
{
	self = [super init];

	if(self)
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

		// augment sequences with newline, character return and beep
		sequences = [sequences arrayByAddingObjectsFromArray:@[
			TCSMake(@"\n",	CPMTerminalAction(	[controlSet incrementY];						)),
			TCSMake(@"\r",	CPMTerminalAction(	[controlSet setCursorX:0 y:controlSet.cursorY];	)),
			TCSMake(@"\a",	CPMTerminalAction(	NSBeep();										)),
		]];

		// build a search tree of control sequences
		_sequenceTree = [[CPMTerminalControlSequenceTree alloc] initWithControlSequences:sequences];

		// allocate the input queue
		_inputQueue = (uint8_t *)malloc(sizeof(uint8_t) * [[sequences valueForKeyPath:@"@max.pattern.length"] unsignedIntegerValue]);
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

@end
