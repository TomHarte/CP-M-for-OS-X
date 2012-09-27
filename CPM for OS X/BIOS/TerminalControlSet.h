//
//  CPMTerminaViewControlSet.h
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

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

/*

	A control set encapsulates the logic for converting a sequence of incoming
	characters to formatted output. So this is where the emulation of VT52, ADM3A
	or whatever control codes occurs.

*/
@interface CPMTerminalControlSet : NSObject

+ (id)ADM3AControlSet;
+ (id)hazeltine1500ControlSet;
+ (id)osborneControlSet;
+ (id)VT52ControlSet;

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

@property (atomic, assign) id <CPMTerminalControlSetDelegate> delegate;

// write character is the single entry point for updating state; post all output characters here
- (void)writeCharacter:(uint8_t)character;

// character buffer will in effect return a C string of the current character output, with
// newlines and a terminating NULL
- (uint8_t *)characterBuffer;

// attributeBufferForY: returns the C array of attributes for the given scanline; each scanline
// is linear but they're not necessarily tightly packed
- (uint16_t *)attributeBufferForY:(int)y;

// the current cursor position, in character coordinates; (0, 0) is the top left
@property (nonatomic, readonly) int cursorX, cursorY;
@property (nonatomic, readonly) BOOL cursorIsDisabled;

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
