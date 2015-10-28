//
//  CPMTerminalControlSet+VT52.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSet+Actions.h"

@interface CPMTerminalControlSet (VT52)
@end

@implementation CPMTerminalControlSet (VT52)

+ (instancetype)VT52ControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:25 isColour:NO];

	NSDictionary *const actions = @{
		@"\eA":		CPMTerminalAction(	[controlSet upCursor];		),
		@"\eB":		CPMTerminalAction(	[controlSet downCursor];	),
		@"\eC":		CPMTerminalAction(	[controlSet rightCursor];	),
		@"\eD":		CPMTerminalAction(	[controlSet leftCursor];	),
		@"\eE":		CPMTerminalAction(
										[controlSet homeCursor];
										[controlSet clearToEndOfScreen];
									),
		@"\eH":		CPMTerminalAction(	[controlSet homeCursor];			),
		@"\eI":		CPMTerminalAction(	[controlSet decrementY];			),
		@"\eJ":		CPMTerminalAction(	[controlSet clearToEndOfScreen];	),
		@"\eK":		CPMTerminalAction(	[controlSet clearToEndOfLine];		),
		@"\eL":		CPMTerminalAction(	[controlSet insertLine];			),
		@"\eM":		CPMTerminalAction(	[controlSet deleteLine];			),
		@"\eY??":	CPMTerminalAction(
										[controlSet
												setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
												y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
									),
		// ESC b — select font colour
		// ESC c — select background colour
		@"\ed":		CPMTerminalAction(	[controlSet clearFromStartOfScreen];	),
		@"\ee":		CPMTerminalAction(	controlSet.cursorIsDisabled = NO;		),
		@"\ef":		CPMTerminalAction(	controlSet.cursorIsDisabled = YES;		),
		@"\ej":		CPMTerminalAction(	[controlSet saveCursorPosition];		),
		@"\ek":		CPMTerminalAction(	[controlSet restoreCursorPosition];		),
		@"\el":		CPMTerminalAction(
										[controlSet setCursorX:0 y:controlSet.cursorY];
										[controlSet clearToEndOfLine];
									),
		@"\eo":		CPMTerminalAction(	[controlSet clearFromStartOfLine];		),

		@"\ep":		CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		),
		@"\eq":		CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	),

//		@"\0334":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		),
//		@"\0333":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	),
		// ESC v - automatic overflow on
		// ESC w - automatic overflow off
	};

	[set registerActionsByPrefix:actions];
	return set;
}

@end
