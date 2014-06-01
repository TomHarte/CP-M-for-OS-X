//
//  CPMTerminalControlSet+Osborne.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+Osborne.h"

@implementation CPMTerminalControlSet (Osborne)

+ (instancetype)osborneControlSet			{	return [[self alloc] initWithControlSet:@selector(installOsborneControlCodes) width:80 height:24];		}

- (void)installOsborneControlCodes
{
	__weak __block typeof(self) weakSelf = self;

	CPMTerminalControlSequenceStruct sequences[] =
	{
		{@"\x07",	0,	^{	NSBeep();				}}, // i.e. ^G

		{@"\x08",	0,	^{	[weakSelf leftCursor];	}},	// i.e. ^H
		{@"\x0c",	0,	^{	[weakSelf rightCursor];	}},	// i.e. ^L
		{@"\x0b",	0,	^{	[weakSelf upCursor];	}},	// i.e. ^K
		{@"\x1a",	0,	^{
							[weakSelf homeCursor];
							[weakSelf clearToEndOfScreen];
						}},								// i.e. ^Z
		{@"\x1e",	0,	^{	[weakSelf homeCursor];	}},
		{@"\33=",	4,	^{
							[weakSelf
									setCursorX:(weakSelf.inputQueue[3] - 32)%weakSelf.width
									y:(weakSelf.inputQueue[2] - 32)%weakSelf.height];
						}},
		{@"\33T",	0,	^{	[weakSelf clearToEndOfLine];	}},

		{@"\33)",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33(",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33L",	0,	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeUnderlinedOn;			}},
		{@"\33M",	0,	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeUnderlinedOn;		}},

		{@"\33E",	0,	^{	[weakSelf insertLine];			}},
		{@"\33R",	0,	^{	[weakSelf deleteLine];			}},

		{nil}
	};

	/*
		Unimplemented at present:
		
			1b 23	ESC #	locks keyboard
			1b 22	ESC "	unlocks keyboard
			1b 53	ESC S	screen XY positioning
			1b 51	ESC Q	insert character
			1b 57	ESC W	delete character
			1b 67	ESC g	start graphics display
			1b 47	ESC G	end graphics display
			1b 5b	ESC [	homes screen
	*/

	[self installControlSequencesFromStructs:sequences];
}

@end
