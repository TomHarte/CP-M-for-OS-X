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
	return [[self alloc] initWithControlSequences:@[
			TCSMake(@"\x0b",	CPMTerminalAction(	[controlSet upCursor];					)),
			TCSMake(@"\x17",	CPMTerminalAction(	[controlSet clearToEndOfScreen];		)),
			TCSMake(@"\x18",	CPMTerminalAction(	[controlSet clearToEndOfLine];			)),
			TCSMake(@"\x1a",	CPMTerminalAction(
													[controlSet homeCursor];
													[controlSet clearToEndOfScreen];
												)),
			TCSMake(@"\x1e",	CPMTerminalAction(	[controlSet homeCursor];					)),
			TCSMake(@"\x08",	CPMTerminalAction(	[controlSet leftCursor];					)),
			TCSMake(@"\x0c",	CPMTerminalAction(	[controlSet rightCursor];					)),
			TCSMake(@"\33=??",	CPMTerminalAction(
													[controlSet
															setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
															y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
												)),

			TCSMake(@"\33B0",	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		)),
			TCSMake(@"\33C0",	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];		)),
			TCSMake(@"\33B1",	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeReducedIntensity];	)),
			TCSMake(@"\33C1",	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeReducedIntensity];	)),
			TCSMake(@"\33B2",	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeBlinking];			)),
			TCSMake(@"\33C2",	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeBlinking];			)),
			TCSMake(@"\33B3",	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeUnderlined];			)),
			TCSMake(@"\33C3",	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeUnderlined];		)),

			TCSMake(@"\33B4",	CPMTerminalAction(	controlSet.cursorIsDisabled = NO;		)),
			TCSMake(@"\33C4",	CPMTerminalAction(	controlSet.cursorIsDisabled = YES;		)),

			TCSMake(@"\33B6",	CPMTerminalAction(	[controlSet saveCursorPosition];		)),
			TCSMake(@"\33C6",	CPMTerminalAction(	[controlSet restoreCursorPosition];		)),

			TCSMake(@"\33R",	CPMTerminalAction(	[controlSet deleteLine];	)),
			TCSMake(@"\33E",	CPMTerminalAction(	[controlSet insertLine];	)),
		]
		width:80
		height:24];

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
