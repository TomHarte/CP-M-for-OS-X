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
		{@"\x07",	^{	NSBeep();				}}, // i.e. ^G

		{@"\x08",	^{	[weakSelf leftCursor];	}},	// i.e. ^H
		{@"\x0c",	^{	[weakSelf rightCursor];	}},	// i.e. ^L
		{@"\x0b",	^{	[weakSelf upCursor];	}},	// i.e. ^K
		{@"\x1a",	^{
						[weakSelf homeCursor];
						[weakSelf clearToEndOfScreen];
					}},								// i.e. ^Z
		{@"\x1e",	^{	[weakSelf homeCursor];	}},
		{@"\33=??",	^{
						[weakSelf
								setCursorX:(NSUInteger)(weakSelf.inputQueue[3] - 32)%weakSelf.width
								y:(NSUInteger)(weakSelf.inputQueue[2] - 32)%weakSelf.height];
					}},
		{@"\33T",	^{	[weakSelf clearToEndOfLine];	}},

		{@"\33)",	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33(",	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeReducedIntensityOn;	}},
		{@"\33L",	^{	weakSelf.currentAttribute |= kCPMTerminalAttributeUnderlinedOn;			}},
		{@"\33M",	^{	weakSelf.currentAttribute &= ~kCPMTerminalAttributeUnderlinedOn;		}},

		{@"\33E",	^{	[weakSelf insertLine];			}},
		{@"\33R",	^{	[weakSelf deleteLine];			}},

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
