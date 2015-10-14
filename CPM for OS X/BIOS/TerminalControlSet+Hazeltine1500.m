//
//  CPMTerminalControlSet+Hazeltine1500.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+Hazeltine1500.h"

@implementation CPMTerminalControlSet (Hazeltine1500)

+ (instancetype)hazeltine1500ControlSet	{	return [[self alloc] initWithControlSet:@selector(installHazeltine1500ControlCodes) width:80 height:24];	}

- (void)installHazeltine1500ControlCodes
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"~\5",	^{
						dispatch_sync(dispatch_get_main_queue(),
						^{
							[weakSelf.delegate
								terminalViewControlSet:weakSelf
								addStringToInput:
									[NSString stringWithFormat:@"%c%c",
											(uint8_t)weakSelf.cursorX,
											(uint8_t)weakSelf.cursorY]];
						});
					}},
		{@"~\13",	^{	[weakSelf downCursor];	}},
		{@"~\14",	^{	[weakSelf upCursor];	}},
		{@"~\17",	^{	[weakSelf clearToEndOfLine];	}},
		{@"~\21??",	^{
						[weakSelf
							setCursorX:(NSUInteger)weakSelf.inputQueue[2]%weakSelf.width
							y:(NSUInteger)weakSelf.inputQueue[3]%weakSelf.height];
					}},
		{@"~\22",	^{	[weakSelf homeCursor];	}},
		{@"~\23",	^{	[weakSelf deleteLine];			}},
		{@"~\30",	^{	[weakSelf clearToEndOfScreen];	}},
		{@"~\31",	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeBackground;	}},
		{@"~\32",	^{	[weakSelf insertLine];			}},
		{@"~\34",	^{
						[weakSelf homeCursor];
						[weakSelf clearToEndOfScreen];
					}},
		{@"~\37",	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeBackground;	}},
		{nil}
	};

	/*
		Unimplemented:

			right cursor		dec 16
			clear foreground	~ dec 29
			clear to end-of-screen - background spaces	~ dec 23
			keyboard lock		~ dec 21
			keyboard unlock		~ dec 6
			(...and tab)

	*/

	[self installControlSequencesFromStructs:sequences];
}

@end
