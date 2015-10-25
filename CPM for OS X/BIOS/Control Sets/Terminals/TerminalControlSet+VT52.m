//
//  CPMTerminalControlSet+VT52.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+VT52.h"
#import "TerminalControlSet+Actions.h"

@implementation CPMTerminalControlSet (VT52)

+ (instancetype)VT52ControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:25 isColour:NO];

	NSDictionary *const actions = @{
		@"\33A":	CPMTerminalAction(	[controlSet upCursor];		),
		@"\33B":	CPMTerminalAction(	[controlSet downCursor];	),
		@"\33C":	CPMTerminalAction(	[controlSet rightCursor];	),
		@"\33D":	CPMTerminalAction(	[controlSet leftCursor];	),
		@"\33E":	CPMTerminalAction(
										[controlSet homeCursor];
										[controlSet clearToEndOfScreen];
									),
		@"\33H":	CPMTerminalAction(	[controlSet homeCursor];			),
		@"\33I":	CPMTerminalAction(	[controlSet decrementY];			),
		@"\33J":	CPMTerminalAction(	[controlSet clearToEndOfScreen];	),
		@"\33K":	CPMTerminalAction(	[controlSet clearToEndOfLine];		),
		@"\33L":	CPMTerminalAction(	[controlSet insertLine];			),
		@"\33M":	CPMTerminalAction(	[controlSet deleteLine];			),
		@"\33Y??":	CPMTerminalAction(
										[controlSet
												setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
												y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
									),
		// ESC b — select font colour
		// ESC c — select background colour
		@"\33d":	CPMTerminalAction(	[controlSet clearFromStartOfScreen];	),
		@"\33e":	CPMTerminalAction(	controlSet.cursorIsDisabled = NO;		),
		@"\33f":	CPMTerminalAction(	controlSet.cursorIsDisabled = YES;		),
		@"\33j":	CPMTerminalAction(	[controlSet saveCursorPosition];		),
		@"\33k":	CPMTerminalAction(	[controlSet restoreCursorPosition];		),
		@"\33l":	CPMTerminalAction(
										[controlSet setCursorX:0 y:controlSet.cursorY];
										[controlSet clearToEndOfLine];
									),
		@"\33o":	CPMTerminalAction(	[controlSet clearFromStartOfLine];		),

		@"\33p":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		),
		@"\33q":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	),

		@"\0334":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		),
		@"\0333":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	),
		// ESC v - automatic overflow on
		// ESC w - automatic overflow off
	};

	[set registerActionsByPrefix:actions];
	return set;
}

@end
