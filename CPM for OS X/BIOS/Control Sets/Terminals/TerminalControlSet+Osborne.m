//
//  CPMTerminalControlSet+Osborne.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSet+Actions.h"

@interface CPMTerminalControlSet (Osborne)
@end

@implementation CPMTerminalControlSet (Osborne)

+ (instancetype)osborneControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];

	NSDictionary *const actions = @{
		@"\x07":	CPMTerminalAction(	NSBeep();					), // i.e. ^G

		@"\x08":	CPMTerminalAction(	[controlSet leftCursor];	),	// i.e. ^H
		@"\x0c":	CPMTerminalAction(	[controlSet rightCursor];	),	// i.e. ^L
		@"\x0b":	CPMTerminalAction(	[controlSet upCursor];		),	// i.e. ^K
		@"\x1a":	CPMTerminalAction(
										[controlSet homeCursor];
										[controlSet clearToEndOfScreen];
									),								// i.e. ^Z
		@"\x1e":	CPMTerminalAction(	[controlSet homeCursor];	),
		@"\e=??":	CPMTerminalAction(
										[controlSet
												setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
												y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
									),
		@"\eT":		CPMTerminalAction(	[controlSet clearToEndOfLine];	),

		@"\e)":		CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeReducedIntensity];		),
		@"\e(":		CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeReducedIntensity];	),
		@"\eL":		CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeUnderlined];			),
		@"\eM":		CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeUnderlined];			),

		@"\eE":		CPMTerminalAction(	[controlSet insertLine];	),
		@"\eR":		CPMTerminalAction(	[controlSet deleteLine];	),
	};

	[set registerActionsByPrefix:actions];
	return set;

	/*
		Unimplemented at present:
		
			1b 23	ESC #	locks keyboard
			1b 22	ESC "	unlocks keyboard
			1b 53	ESC S	screen XY positioning
			1b 51	ESC Q	insert character
			1b 57	ESC W	delete character
			1b 67	ESC g	start graphics display
			1b 47	ESC G	end graphics display
			1b 5b	ESC [	homes screen
	*/
}

@end
