//
//  CPMTerminalControlSet+VT52.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+VT52.h"

@implementation CPMTerminalControlSet (VT52)

+ (instancetype)VT52ControlSet			{	return [[self alloc] initWithControlSet:@selector(installVT52ControlCodes) width:80 height:25];			}

- (void)installVT52ControlCodes
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\33A",	^{	[weakSelf upCursor];	}},
		{@"\33B",	^{	[weakSelf downCursor];	}},
		{@"\33C",	^{	[weakSelf rightCursor];	}},
		{@"\33D",	^{	[weakSelf leftCursor];	}},
		{@"\33E",	^{
						[weakSelf homeCursor];
						[weakSelf clearToEndOfScreen];
					}},
		{@"\33H",	^{	[weakSelf homeCursor];	}},
		{@"\33I",	^{	[weakSelf decrementY];	}},
		{@"\33J",	^{	[weakSelf clearToEndOfScreen];	}},
		{@"\33K",	^{	[weakSelf clearToEndOfLine];	}},
		{@"\33L",	^{	[weakSelf insertLine];	}},
		{@"\33M",	^{	[weakSelf deleteLine];	}},
		{@"\33Y??",	^{
						[weakSelf
								setCursorX:(NSUInteger)(weakSelf.inputQueue[3] - 32)%weakSelf.width
								y:(NSUInteger)(weakSelf.inputQueue[2] - 32)%weakSelf.height];
					}},
		// ESC b — select font colour
		// ESC c — select background colour
		{@"\33d",	^{	[weakSelf clearFromStartOfScreen];	}},
		{@"\33e",	^{	weakSelf.cursorIsDisabled = NO;		}},
		{@"\33f",	^{	weakSelf.cursorIsDisabled = YES;	}},
		{@"\33j",	^{	[weakSelf saveCursorPosition];		}},
		{@"\33k",	^{	[weakSelf restoreCursorPosition];	}},
		{@"\33l",	^{
							[weakSelf setCursorX:0 y:weakSelf.cursorY];
							[weakSelf clearToEndOfLine];
						}},
		{@"\33o",	^{	[weakSelf clearFromStartOfLine];	}},

		{@"\33p",	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeInverseVideoOn;	}},
		{@"\33q",	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;	}},

		{@"\0334",	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeInverseVideoOn;	}},
		{@"\0333",	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;	}},
		// ESC v - automatic overflow on
		// ESC w - automatic overflow off
		{nil}
	};

	[self installControlSequencesFromStructs:sequences];
}

@end
