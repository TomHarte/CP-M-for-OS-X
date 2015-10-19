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
	return [[self alloc] initWithControlSequences:@[
			TCSMake(@"\33A",	CPMTerminalAction(	[controlSet upCursor];		)),
			TCSMake(@"\33B",	CPMTerminalAction(	[controlSet downCursor];	)),
			TCSMake(@"\33C",	CPMTerminalAction(	[controlSet rightCursor];	)),
			TCSMake(@"\33D",	CPMTerminalAction(	[controlSet leftCursor];	)),
			TCSMake(@"\33E",	CPMTerminalAction(
													[controlSet homeCursor];
													[controlSet clearToEndOfScreen];
												)),
			TCSMake(@"\33H",	CPMTerminalAction(	[controlSet homeCursor];			)),
			TCSMake(@"\33I",	CPMTerminalAction(	[controlSet decrementY];			)),
			TCSMake(@"\33J",	CPMTerminalAction(	[controlSet clearToEndOfScreen];	)),
			TCSMake(@"\33K",	CPMTerminalAction(	[controlSet clearToEndOfLine];		)),
			TCSMake(@"\33L",	CPMTerminalAction(	[controlSet insertLine];			)),
			TCSMake(@"\33M",	CPMTerminalAction(	[controlSet deleteLine];			)),
			TCSMake(@"\33Y??",	CPMTerminalAction(
													[controlSet
															setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
															y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
												)),
			// ESC b — select font colour
			// ESC c — select background colour
			TCSMake(@"\33d",	CPMTerminalAction(	[controlSet clearFromStartOfScreen];	)),
			TCSMake(@"\33e",	CPMTerminalAction(	controlSet.cursorIsDisabled = NO;		)),
			TCSMake(@"\33f",	CPMTerminalAction(	controlSet.cursorIsDisabled = YES;		)),
			TCSMake(@"\33j",	CPMTerminalAction(	[controlSet saveCursorPosition];		)),
			TCSMake(@"\33k",	CPMTerminalAction(	[controlSet restoreCursorPosition];		)),
			TCSMake(@"\33l",	CPMTerminalAction(
								[controlSet setCursorX:0 y:controlSet.cursorY];
								[controlSet clearToEndOfLine];
							)),
			TCSMake(@"\33o",	CPMTerminalAction(	[controlSet clearFromStartOfLine];		)),

			TCSMake(@"\33p",	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		)),
			TCSMake(@"\33q",	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	)),

			TCSMake(@"\0334",	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		)),
			TCSMake(@"\0333",	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	)),
			// ESC v - automatic overflow on
			// ESC w - automatic overflow off
		]
		width:80
		height:25];
}

@end
