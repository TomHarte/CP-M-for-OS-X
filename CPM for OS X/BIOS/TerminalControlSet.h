//
//  CPMTerminaViewControlSet.h
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TerminalControlSequence.h"
@class CPMTerminalControlSet;

/*

	These delegate methods are guaranteed to be called on the main queue

*/
@protocol CPMTerminalControlSetDelegate <NSObject>

// did change output is triggered upon any new characters being written to the screen or the cursor moving
// (if enabled), i.e. anything that would be visible to a user
- (void)terminalViewControlSetDidChangeOutput:(CPMTerminalControlSet *)controlSet;

// some terminals have call and return sequences where printing a certain sequence results in a response
// as input; this delegate call will be used to post any such responses
- (void)terminalViewControlSet:(CPMTerminalControlSet *)controlSet addStringToInput:(NSString *)string;

@end


typedef struct IntegerPoint {
    NSUInteger x;
    NSUInteger y;
} IntegerPoint;

CG_INLINE IntegerPoint integerPointMake(NSUInteger x, NSUInteger y)
{
	IntegerPoint point = {.x = x, .y = y};
	return point;
}

/*

	A control set encapsulates the logic for converting a sequence of incoming
	characters to formatted output. So this is where the emulation of VT52, ADM3A
	or whatever control codes occurs.

*/
@interface CPMTerminalControlSet : NSObject

// The following three are accounting; every time the control set recognises a control
// code it'll add the index at which it was recognised to recognisedControlPoints. Every time
// it spots that there was one but that it doesn't know what it was, it'll add that to
// unrecognisedControlPoints. So if this is the incorrect terminal for the program being run then
// the former may include some false positives and the latter may not include some things
// that were control codes but looked nothing like the sort this terminal understands.
// They should provide some rough metrics for deciding which terminal emulation to proceed with though.
@property (nonatomic, assign) BOOL isTrackingCodePoints;
@property (nonatomic, assign) NSUInteger numberOfCharactersSoFar;
@property (nonatomic, readonly) NSSet *recognisedControlPoints, *unrecognisedControlPoints;

// the width and height are the dimensions of this terminal in characters
@property (nonatomic, readonly) NSUInteger width, height;

@property (atomic, weak) id <CPMTerminalControlSetDelegate> delegate;

// write character is the single entry point for updating state; post all output characters here
- (void)writeCharacter:(char)character;

// character buffer will in effect return a C string of the current character output, with
// newlines and a terminating NULL
- (const char *)characterBuffer;

// the NSString covering any range of the screen is available
- (const char *)charactersBetweenStart:(IntegerPoint)start end:(IntegerPoint)end length:(size_t *)length;

// attributeBufferForY: returns the C array of attributes for the given scanline; each scanline
// is linear but they're not necessarily tightly packed
- (uint16_t *)attributeBufferForY:(NSUInteger)y;

// the current cursor position, in character coordinates; (0, 0) is the top left
@property (nonatomic, readonly) NSUInteger cursorX, cursorY;
@property (nonatomic, readonly) BOOL cursorIsDisabled;

/*
	STRICTLY FOR CATEGORIES. Leave alone.
*/
- (id)initWithControlSequences:(NSArray<CPMTerminalControlSequence *> *)sequences width:(NSUInteger)width height:(NSUInteger)height;
- (void)setCursorIsDisabled:(BOOL)cursorIsDisabled;

@property (nonatomic, assign) uint16_t currentAttribute;
@property (nonatomic, assign) char *inputQueue;

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

#import "TerminalControlSet+ADM3A.h"
#import "TerminalControlSet+Hazeltine1500.h"
#import "TerminalControlSet+VT52.h"
#import "TerminalControlSet+Osborne.h"
#import "TerminalControlSet+ANSI.h"
