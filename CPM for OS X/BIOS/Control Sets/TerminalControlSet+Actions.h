//
//  TerminalControlSet+Actions.h
//  CPM for OS X
//
//  Created by Thomas Harte on 18/10/2015.
//  Copyright © 2015 Thomas Harte. All rights reserved.
//

@interface CPMTerminalControlSet (Actions)

- (id)initWithControlSequences:(NSArray<CPMTerminalControlSequence *> *)sequences width:(NSUInteger)width height:(NSUInteger)height;
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

@end

/*

	These are the currently defined attributes. The attribute values you'll get back per
	character are 16-bit quantities since it'll likely become necessary to store 4-bit colours
	in there too for some terminal emulations; effectively I'm asserting that 16 bits is
	enough to store the union of all character attributes for all terminals — the internal
	attribute layout is fixed, it's not per terminal.

*/
#define kCPMTerminalAttributeInverseVideoOn			0x01
#define kCPMTerminalAttributeReducedIntensityOn		0x02
#define kCPMTerminalAttributeBlinkingOn				0x04
#define kCPMTerminalAttributeUnderlinedOn			0x08

#define kCPMTerminalAttributeBackground				0x10

#define kCPMTerminalAttributeSelected				0x80
