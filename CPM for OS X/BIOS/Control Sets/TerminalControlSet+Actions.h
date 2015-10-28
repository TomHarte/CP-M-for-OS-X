//
//  TerminalControlSet+Actions.h
//  CPM for OS X
//
//  Created by Thomas Harte on 18/10/2015.
//  Copyright © 2015 Thomas Harte. All rights reserved.
//

#import "TerminalControlSequenceTree.h"

typedef void (^ CPMTerminalControlCharacterMapper)(unichar *input, CPMTerminalAttribute *attribute);

@interface CPMTerminalControlSet (Actions)

- (id)initWithWidth:(NSUInteger)width height:(NSUInteger)height isColour:(BOOL)isColour;
- (void)setCursorIsDisabled:(BOOL)cursorIsDisabled;

- (void)homeCursor;

- (void)upCursor;
- (void)downCursor;
- (void)leftCursor;
- (void)rightCursor;

- (void)clearToEndOfScreen;
- (void)clearFromStartOfScreen;
- (void)clearToEndOfLine;
- (void)clearFromStartOfLine;

- (void)saveCursorPosition;
- (void)restoreCursorPosition;
- (void)setCursorX:(NSUInteger)newCursorX y:(NSUInteger)newCursorY;

- (void)deleteLine;
- (void)insertLine;

- (void)decrementY;
- (void)incrementY;

- (void)setAttribute:(CPMTerminalAttribute)attribute;
- (void)resetAttribute:(CPMTerminalAttribute)attribute;
- (void)toggleAttribute:(CPMTerminalAttribute)attribute;
- (void)setAttributes:(CPMTerminalAttribute)attribute;

- (void)mapCharactersFromCursorUsingMapper:(CPMTerminalControlCharacterMapper)mapper;

- (void)outputCharacter:(unichar)character;
- (void)outputInlineAttribute:(CPMTerminalAttribute)attribute;
- (void)recordRecognisedControlCodeOfLength:(NSUInteger)length;

- (void)registerActionsByPrefix:(NSDictionary *)actionsByPrefix;
- (CPMTerminalControlSequenceTree *)sequenceTree;

@end


