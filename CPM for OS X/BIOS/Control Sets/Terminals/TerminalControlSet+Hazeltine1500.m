//
//  CPMTerminalControlSet+Hazeltine1500.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+Hazeltine1500.h"
#import "TerminalControlSet+Actions.h"

@implementation CPMTerminalControlSet (Hazeltine1500)

+ (instancetype)hazeltine1500ControlSet
{
	return [[self alloc] initWithControlSequences:@[
			TCSMake(@"~\5",		CPMTerminalAction(
													dispatch_sync(dispatch_get_main_queue(),
													^{
														[controlSet.delegate
															terminalViewControlSet:controlSet
															addStringToInput:
																[NSString stringWithFormat:@"%c%c\r",
																		(uint8_t)(controlSet.cursorX + ((controlSet.cursorX < 32) ? 96 : 0)),
																		96 + (uint8_t)controlSet.cursorY]];
													});
												)),
			TCSMake(@"~\13",	CPMTerminalAction(	[controlSet downCursor];		)),
			TCSMake(@"~\14",	CPMTerminalAction(	[controlSet upCursor];			)),
			TCSMake(@"~\17",	CPMTerminalAction(	[controlSet clearToEndOfLine];	)),
			TCSMake(@"~\21??",	CPMTerminalAction(
													NSUInteger cursorX = MIN(inputQueue[2] % 96, 79);
													NSUInteger cursorY = MIN(inputQueue[3] % 32, 23);
													[controlSet
														setCursorX:cursorX
														y:cursorY];
												)),
			TCSMake(@"~\22",	CPMTerminalAction(	[controlSet homeCursor];			)),
			TCSMake(@"~\23",	CPMTerminalAction(	[controlSet deleteLine];			)),
			TCSMake(@"~\30",	CPMTerminalAction(	[controlSet clearToEndOfScreen];	)),
			TCSMake(@"~\31",	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeReducedIntensity];		)),
			TCSMake(@"~\32",	CPMTerminalAction(	[controlSet insertLine];			)),
			TCSMake(@"~\34",	CPMTerminalAction(
													[controlSet homeCursor];
													[controlSet clearToEndOfScreen];
												)),
			TCSMake(@"~\37",	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeReducedIntensity];	)),

			TCSMake(@"\10",		CPMTerminalAction(	[controlSet leftCursor];	)),
			TCSMake(@"\20",		CPMTerminalAction(	[controlSet rightCursor];	)),

			TCSMake(@"~\35",	CPMTerminalAction(
													[controlSet homeCursor];
													[controlSet mapCharactersFromCursorUsingMapper:^(char *input, CPMTerminalAttribute *attribute) {
														if(!(*attribute & CPMTerminalAttributeReducedIntensity))
														{
															*input = ' ';
														}
													}];
												)),

			TCSMake(@"~\27",	CPMTerminalAction(
													[controlSet mapCharactersFromCursorUsingMapper:^(char *input, CPMTerminalAttribute *attribute) {
														*input = ' ';
														*attribute = CPMTerminalAttributeReducedIntensity;
													}];
												)),
		]
		width:80
		height:24];

	/*
		Unimplemented:

			keyboard lock		~ dec 21
			keyboard unlock		~ dec 6
			(...and tab)

	*/
}

@end
