//
//  CPMTerminalControlSet+ADM3A.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+ADM3A.h"
#import "TerminalControlSet+Actions.h"

@implementation CPMTerminalControlSet (ADM3A)

+ (instancetype)ADM3AControlSet
{
	/*
		This is actually the pure ADM3A with some Kaypro extensions thrown
		in, I believe...
		
		Update! This may well just be the Kaypro. I'll need to look into this.
	*/
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];

	NSDictionary *const actions = @{
		@"\x0b":	CPMTerminalAction(	[controlSet upCursor];					),
		@"\x17":	CPMTerminalAction(	[controlSet clearToEndOfScreen];		),
		@"\x18":	CPMTerminalAction(	[controlSet clearToEndOfLine];			),
		@"\x1a":	CPMTerminalAction(
										[controlSet homeCursor];
										[controlSet clearToEndOfScreen];
									),
		@"\x1e":	CPMTerminalAction(	[controlSet homeCursor];					),
		@"\x08":	CPMTerminalAction(	[controlSet leftCursor];					),
		@"\x0c":	CPMTerminalAction(	[controlSet rightCursor];					),
		@"\33=??":	CPMTerminalAction(
										[controlSet
												setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
												y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
									),

		@"\33B0":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		),
		@"\33C0":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	),
		@"\33B1":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeReducedIntensity];	),
		@"\33C1":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeReducedIntensity];),
		@"\33B2":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeBlinking];			),
		@"\33C2":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeBlinking];		),
		@"\33B3":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeUnderlined];		),
		@"\33C3":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeUnderlined];		),

		@"\33B4":	CPMTerminalAction(	controlSet.cursorIsDisabled = NO;		),
		@"\33C4":	CPMTerminalAction(	controlSet.cursorIsDisabled = YES;		),

		@"\33B6":	CPMTerminalAction(	[controlSet saveCursorPosition];		),
		@"\33C6":	CPMTerminalAction(	[controlSet restoreCursorPosition];		),

		@"\33E":	CPMTerminalAction(	[controlSet deleteLine];	),
		@"\33R":	CPMTerminalAction(	[controlSet insertLine];	),
	};

	[set registerActionsByPrefix:actions];
	return set;

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
}

@end
