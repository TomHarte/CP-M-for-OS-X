//
//  CPMTerminaViewControlSet.m
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSequenceTree.h"
#import "TerminalControlSet+Actions.h"

@implementation CPMTerminalControlSet
{
	uint8_t *_inputQueue;
	CPMTerminalAttribute _currentAttribute;

	unichar *_characters;
	CPMTerminalAttribute *_attributes;

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

- (void)writeByte:(uint8_t)character
{
	// this enqueuing process has a quick safeguard against overflow
	_inputQueue[_inputQueueWritePointer++] = character;
	_numberOfCharactersSoFar++;

	// pull recognised sequences as they're found
	while(_inputQueueWritePointer)
	{
		NSUInteger foundMatch = [_sequenceTree matchBytes:_inputQueue length:_inputQueueWritePointer controlSet:self];

		// might find => more input needed. So wait.
		if(!foundMatch)
			break;

		_inputQueueWritePointer -= foundMatch;
		memmove(_inputQueue, &_inputQueue[foundMatch], _inputQueueWritePointer * sizeof(unichar));
	}
}

- (void)recordRecognisedControlCode
{
	[(NSMutableSet *)_recognisedControlPoints addObject:@(_numberOfCharactersSoFar)];
}

- (void)outputInlineAttribute:(CPMTerminalAttribute)attribute
{
	[self outputCharacter:' ' attribute:attribute];
}

- (void)outputCharacter:(unichar)character
{
	[self outputCharacter:character attribute:_currentAttribute];
}

- (void)outputCharacter:(unichar)character attribute:(CPMTerminalAttribute)attribute
{
	// if it's not one of the ASCII printables then, for now, render it as a space
	// (TODO: put these somewhere else so that we can do graphics output)
//	if(character < 0x20 || character > 0x7e) character = ' ';

	// write the character, with the current attribute
	_characters[address(_cursorX, _cursorY)] = character;
	_attributes[address(_cursorX, _cursorY)] = attribute;

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

	if(!self.cursorIsDisabled)
	{
		dispatch_async(dispatch_get_main_queue(),
		^{
			[self.delegate terminalViewControlSetDidChangeOutput:self];
		});
	}
}

- (const unichar *)characterBuffer				{	return _characters;						}
- (NSUInteger)characterBufferLength				{	return (self.width+1)*self.height - 1;	}
- (const CPMTerminalAttribute *)attributeBufferForY:(NSUInteger)y
{
	return &_attributes[address(0, y)];
}
- (unichar *)characterBufferForY:(NSUInteger)y
{
	return &_characters[address(0, y)];
}

- (const unichar *)charactersBetweenStart:(IntegerPoint)start end:(IntegerPoint)end length:(size_t *)length
{
	const unichar *charactersStart = &_characters[address(start.x, start.y)];
	const unichar *charactersEnd = &_characters[address(end.x, end.y)];

	*length = (size_t)(charactersEnd - charactersStart + 1);
	return charactersStart;
}

- (void)registerActionsByPrefix:(NSDictionary *)actionsByPrefix
{
	for(NSString *prefix in [actionsByPrefix allKeys])
	{
		CPMTerminalControlSequenceAction action = actionsByPrefix[prefix];
		[_sequenceTree insertAction:action forPrefix:(uint8_t *)[prefix UTF8String]];
	}
}

- (CPMTerminalControlSequenceTree *)sequenceTree
{
	return _sequenceTree;
}

- (id)initWithWidth:(NSUInteger)width height:(NSUInteger)height isColour:(BOOL)isColour
{
	self = [super init];

	if(self)
	{
		// store width and height
		_width = width;
		_height = height;

		// allocate storage area for the display
		_characters = (unichar *)malloc((width+1)*height*sizeof(unichar));
		_attributes = (CPMTerminalAttribute *)malloc((width+1)*height*sizeof(CPMTerminalAttribute));
		[self clearFrom:0 to:(width+1)*height];

		// build a search tree of control sequences
		_sequenceTree = [[CPMTerminalControlSequenceTree alloc] init];

		[self registerActionsByPrefix:
			@{
				@"\n":	CPMTerminalAction(	[controlSet incrementY];						),
				@"\r":	CPMTerminalAction(	[controlSet setCursorX:0 y:controlSet.cursorY];	),
				@"\a":	CPMTerminalAction(	NSBeep();										),
			}];

		// allocate the input queue
		_inputQueue = (uint8_t *)malloc(sizeof(uint8_t) * 256);
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

- (void)moveFrom:(NSUInteger)source to:(NSUInteger)destination length:(NSUInteger)length
{
	memmove(&_characters[destination], &_characters[source], length*sizeof(unichar));
	memmove(&_attributes[destination], &_attributes[source], length*sizeof(CPMTerminalAttribute));
}

- (void)clearFrom:(NSUInteger)destination length:(NSUInteger)length
{
	[self clearFrom:destination to:destination+length];
}

- (void)clearFrom:(NSUInteger)start to:(NSUInteger)end
{
	// write out spaces and zero attributes
	for(NSUInteger position = start; position < end; position++)
	{
		_characters[position] = ' ';
	}
	memset(&_attributes[start], 0, sizeof(CPMTerminalAttribute)*(end-start));

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

- (void)incrementY
{
	_cursorY++;

	if(_cursorY == self.height)
	{
		// scroll all contents up a line
		[self moveFrom:self.width+1 to:0 length:(self.height-1)*(self.width+1)];

		// move the cursor back onto the screen
		_cursorY--;

		// blank out the new bottom line
		[self clearFrom:address(0, _cursorY) length:self.width];

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
		[self moveFrom:0 to:self.width+1 length:(self.height-1)*(self.width+1)];

		// blank out the new top line
		[self clearFrom:0 length:self.width];

		// add a terminating NULL at the end
		_characters[address(self.width, self.height-2)] = '\n';
	}
}

- (void)deleteLine
{
	if(_cursorY < self.height-1)
	{
		// scroll all contents up a line
		[self moveFrom:address(0, _cursorY+1) to:address(0, _cursorY) length:(self.height-1-_cursorY)*(self.width+1)];

		// fix the terminating NULL that just ascended a position
		_characters[address(self.width, self.height-2)] = '\n';
	}

	// blank out the new bottom line
	[self clearFrom:address(0, self.height-1) length:self.width];
}

- (void)insertLine
{
	if(_cursorY < self.height-1)
	{
		// scroll all contents down a line
		[self moveFrom:address(0, _cursorY) to:address(0, _cursorY+1) length:(self.height-1-_cursorY)*(self.width+1)];

		// fix the newline just descended a position
		_characters[address(self.width, self.height-1)] = '\0';
	}

	// blank out this line
	[self clearFrom:address(0, _cursorY) length:self.width];
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

- (void)setAttributes:(CPMTerminalAttribute)attribute
{
	_currentAttribute = attribute;
}

- (void)setAttribute:(CPMTerminalAttribute)attribute
{
	_currentAttribute |= attribute;
}

- (void)resetAttribute:(CPMTerminalAttribute)attribute
{
	_currentAttribute &= ~attribute;
}

- (void)toggleAttribute:(CPMTerminalAttribute)attribute
{
	_currentAttribute ^= attribute;
}

- (void)mapCharactersFromCursorUsingMapper:(CPMTerminalControlCharacterMapper)mapper
{
	for(NSUInteger y = self.cursorY; y < self.height; y++)
	{
		for(NSUInteger x = (y == self.cursorY) ? self.cursorX : 0; x < self.width; x++)
		{
			mapper(&_characters[address(x, y)], &_attributes[address(x, y)]);
		}
	}
}

@end
