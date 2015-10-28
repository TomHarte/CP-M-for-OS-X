//
//  CPMTerminalControlSet+Hazeltine1500.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSet+Actions.h"

@interface CPMTerminalControlSet (Hazeltine1500)
@end

@implementation CPMTerminalControlSet (Hazeltine1500)

+ (instancetype)hazeltine1500ControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];

	NSDictionary *const actions = @{
		@"~\5":		CPMTerminalAction(
										dispatch_sync(dispatch_get_main_queue(),
										^{
											[controlSet.delegate
												terminalViewControlSet:controlSet
												addStringToInput:
													[NSString stringWithFormat:@"%c%c\r",
															(uint8_t)(controlSet.cursorX + ((controlSet.cursorX < 32) ? 96 : 0)),
															96 + (uint8_t)controlSet.cursorY]];
										});
									),
		@"~\13":	CPMTerminalAction(	[controlSet downCursor];		),
		@"~\14":	CPMTerminalAction(	[controlSet upCursor];			),
		@"~\17":	CPMTerminalAction(	[controlSet clearToEndOfLine];	),
		@"~\21??":	CPMTerminalAction(
										NSUInteger cursorX = MIN(inputQueue[2] % 96, 79);
										NSUInteger cursorY = MIN(inputQueue[3] % 32, 23);
										[controlSet
											setCursorX:cursorX
											y:cursorY];
									),
		@"~\22":	CPMTerminalAction(	[controlSet homeCursor];			),
		@"~\23":	CPMTerminalAction(	[controlSet deleteLine];			),
		@"~\30":	CPMTerminalAction(	[controlSet clearToEndOfScreen];	),
		@"~\31":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeReducedIntensity];		),
		@"~\32":	CPMTerminalAction(	[controlSet insertLine];			),
		@"~\34":	CPMTerminalAction(
										[controlSet homeCursor];
										[controlSet clearToEndOfScreen];
									),
		@"~\37":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeReducedIntensity];	),

		@"\10":		CPMTerminalAction(	[controlSet leftCursor];	),
		@"\20":		CPMTerminalAction(	[controlSet rightCursor];	),

		@"~\35":	CPMTerminalAction(
										[controlSet homeCursor];
										[controlSet mapCharactersFromCursorUsingMapper:^(unichar *input, CPMTerminalAttribute *attribute) {
											if(!(*attribute & CPMTerminalAttributeReducedIntensity))
											{
												*input = ' ';
											}
										}];
									),

		@"~\27":	CPMTerminalAction(
										[controlSet mapCharactersFromCursorUsingMapper:^(unichar *input, CPMTerminalAttribute *attribute) {
											*input = ' ';
											*attribute = CPMTerminalAttributeReducedIntensity;
										}];
									),
	};
	[set registerActionsByPrefix:actions];
	return set;

	/*
		Unimplemented:

			keyboard lock		~ dec 21
			keyboard unlock		~ dec 6
			(...and tab)

	*/
}

@end
