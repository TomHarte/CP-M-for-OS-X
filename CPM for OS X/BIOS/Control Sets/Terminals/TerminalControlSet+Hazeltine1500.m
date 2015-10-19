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
																[NSString stringWithFormat:@"%c%c",
																		(uint8_t)controlSet.cursorX,
																		(uint8_t)controlSet.cursorY]];
													});
												)),
			TCSMake(@"~\13",	CPMTerminalAction(	[controlSet downCursor];		)),
			TCSMake(@"~\14",	CPMTerminalAction(	[controlSet upCursor];			)),
			TCSMake(@"~\17",	CPMTerminalAction(	[controlSet clearToEndOfLine];	)),
			TCSMake(@"~\21??",	CPMTerminalAction(
													[controlSet
														setCursorX:(NSUInteger)inputQueue[2]%controlSet.width
														y:(NSUInteger)inputQueue[3]%controlSet.height];
												)),
			TCSMake(@"~\22",	CPMTerminalAction(	[controlSet homeCursor];			)),
			TCSMake(@"~\23",	CPMTerminalAction(	[controlSet deleteLine];			)),
			TCSMake(@"~\30",	CPMTerminalAction(	[controlSet clearToEndOfScreen];	)),
			TCSMake(@"~\31",	CPMTerminalAction(	controlSet.currentAttribute |= kCPMTerminalAttributeBackground;		)),
			TCSMake(@"~\32",	CPMTerminalAction(	[controlSet insertLine];			)),
			TCSMake(@"~\34",	CPMTerminalAction(
													[controlSet homeCursor];
													[controlSet clearToEndOfScreen];
												)),
			TCSMake(@"~\37",	CPMTerminalAction(	controlSet.currentAttribute &= ~kCPMTerminalAttributeBackground;	)),
		]
		width:80
		height:24];

	/*
		Unimplemented:

			right cursor		dec 16
			clear foreground	~ dec 29
			clear to end-of-screen - background spaces	~ dec 23
			keyboard lock		~ dec 21
			keyboard unlock		~ dec 6
			(...and tab)

	*/
}

@end
