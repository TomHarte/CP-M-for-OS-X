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
		{@"\33A",	0,	^{	[weakSelf upCursor];	}},
		{@"\33B",	0,	^{	[weakSelf downCursor];	}},
		{@"\33C",	0,	^{	[weakSelf rightCursor];	}},
		{@"\33D",	0,	^{	[weakSelf leftCursor];	}},
		{@"\33E",	0,	^{
							[weakSelf homeCursor];
							[weakSelf clearToEndOfScreen];
						}},
		{@"\33H",	0,	^{	[weakSelf homeCursor];	}},
		{@"\33I",	0,	^{	[weakSelf decrementY];	}},
		{@"\33J",	0,	^{	[weakSelf clearToEndOfScreen];	}},
		{@"\33K",	0,	^{	[weakSelf clearToEndOfLine];	}},
		{@"\33L",	0,	^{	[weakSelf insertLine];	}},
		{@"\33M",	0,	^{	[weakSelf deleteLine];	}},
		{@"\33Y",	4,	^{
							[weakSelf
									setCursorX:(NSUInteger)(weakSelf.inputQueue[3] - 32)%weakSelf.width
									y:(NSUInteger)(weakSelf.inputQueue[2] - 32)%weakSelf.height];
						}},
		// ESC b — select font colour
		// ESC c — select background colour
		{@"\33d",	0,	^{	[weakSelf clearFromStartOfScreen];	}},
		{@"\33e",	0,	^{	weakSelf.cursorIsDisabled = NO;		}},
		{@"\33f",	0,	^{	weakSelf.cursorIsDisabled = YES;	}},
		{@"\33j",	0,	^{	[weakSelf saveCursorPosition];		}},
		{@"\33k",	0,	^{	[weakSelf restoreCursorPosition];	}},
		{@"\33l",	0,	^{
							[weakSelf setCursorX:0 y:weakSelf.cursorY];
							[weakSelf clearToEndOfLine];
						}},
		{@"\33o",	0,	^{	[weakSelf clearFromStartOfLine];	}},

		{@"\33p",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeInverseVideoOn;	}},
		{@"\33q",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;	}},

		{@"\0334",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeInverseVideoOn;	}},
		{@"\0333",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;	}},
		// ESC v - automatic overflow on
		// ESC w - automatic overflow off
		{nil}
	};

	[self installControlSequencesFromStructs:sequences];
}

@end
