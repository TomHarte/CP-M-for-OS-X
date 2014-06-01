//
//  CPMTerminalControlSet+ADM3A.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+ADM3A.h"

@implementation CPMTerminalControlSet (ADM3A)

+ (instancetype)ADM3AControlSet			{	return [[self alloc] initWithControlSet:@selector(installADM3AControlCodes) width:80 height:24];			}

- (void)installADM3AControlCodes
{
	/*
		This is actually the pure ADM3A with some Kaypro extensions thrown
		in, I believe...
		
		Update! This may well just be the Kaypro. I'll need to look into this.
	*/
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\x0b",	0,	^{	[weakSelf upCursor];					}},
		{@"\x17",	0,	^{	[weakSelf clearToEndOfScreen];			}},
		{@"\x18",	0,	^{	[weakSelf clearToEndOfLine];			}},
		{@"\x1a",	0,	^{
							[weakSelf homeCursor];
							[weakSelf clearToEndOfScreen];
						}},
		{@"\x1e",	0,	^{	[weakSelf homeCursor];					}},
		{@"\x08",	0,	^{	[weakSelf leftCursor];					}},
		{@"\x0c",	0,	^{	[weakSelf rightCursor];					}},
		{@"\33=",	4,	^{
							[weakSelf
									setCursorX:(NSUInteger)(weakSelf.inputQueue[3] - 32)%weakSelf.width
									y:(NSUInteger)(weakSelf.inputQueue[2] - 32)%weakSelf.height];
						}},

		{@"\33B0",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeInverseVideoOn;		}},
		{@"\33C0",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeInverseVideoOn;		}},
		{@"\33B1",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33C1",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33B2",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeBlinkingOn;			}},
		{@"\33C2",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeBlinkingOn;			}},
		{@"\33B3",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeUnderlinedOn;			}},
		{@"\33C3",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeUnderlinedOn;		}},

		{@"\33B4",	0,	^{	weakSelf.cursorIsDisabled = NO;			}},
		{@"\33C4",	0,	^{	weakSelf.cursorIsDisabled = YES;		}},

		{@"\33B6",	0,	^{	[weakSelf saveCursorPosition];			}},
		{@"\33C6",	0,	^{	[weakSelf restoreCursorPosition];		}},

		{@"\33R",	0,	^{	[weakSelf deleteLine];	}},
		{@"\33E",	0,	^{	[weakSelf insertLine];	}},
		{nil}
	};

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

	[self installControlSequencesFromStructs:sequences];
}

@end
