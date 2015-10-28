//
//  CPMTerminalControlSet+ADM3A.m
//  CPM for OS X
//
//  Created by Thomas Harte on 31/05/2014.
//  Copyright (c) 2014 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet.h"
#import "TerminalControlSet+Actions.h"

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

@interface CPMTerminalControlSet (ADM3A)
@end

@implementation CPMTerminalControlSet (ADM3A)

+ (NSDictionary *)adm3aActions
{
	return
	@{
		@"\x0b":	CPMTerminalAction(	[controlSet upCursor];					),
		@"\x17":	CPMTerminalAction(	[controlSet clearToEndOfScreen];		),
		@"\x18":	CPMTerminalAction(	[controlSet clearToEndOfLine];			),
		@"\x1a":	CPMTerminalAction(
										[controlSet homeCursor];
										[controlSet clearToEndOfScreen];
									),
		@"\x1e":	CPMTerminalAction(	[controlSet homeCursor];					),
		@"\x08":	CPMTerminalAction(	[controlSet leftCursor];					),
		@"\x0c":	CPMTerminalAction(	[controlSet rightCursor];					),
		@"\e=??":	CPMTerminalAction(
										[controlSet
												setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
												y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
									),

		// ADM-21
		// \eG8 = underline on
		// \eG4 = reverse video on
		// \eG0 = underline, reverse video off
		// \eT = clear to end of line
		// \eY = clear rows from current
		// \eQ = insert one character position at cursor
		// \eW = delete one character

		@"\eB4":	CPMTerminalAction(	controlSet.cursorIsDisabled = NO;		),
		@"\eC4":	CPMTerminalAction(	controlSet.cursorIsDisabled = YES;		),

		@"\eB6":	CPMTerminalAction(	[controlSet saveCursorPosition];		),
		@"\eC6":	CPMTerminalAction(	[controlSet restoreCursorPosition];		),

		@"\eE":		CPMTerminalAction(	[controlSet deleteLine];	),
		@"\eR":		CPMTerminalAction(	[controlSet insertLine];	),
	};
}

+ (NSDictionary *)adm5Additions
{
	return @{
		// this is an ADM-5 addition; attributes are inline
		@"\eG":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeToggle | CPMTerminalAttributeInverseVideo];	),
	};
}

+ (NSDictionary *)adm21Additions
{
	return @{
		@"\eG0":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | 0];	),
		@"\eG1":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | CPMTerminalAttributeUnderlined];		),
		@"\eG2":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | CPMTerminalAttributeBlinking];		),
		@"\eG3":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | CPMTerminalAttributeUnderlined];		),
		@"\eG4":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | CPMTerminalAttributeInverseVideo];	),
		@"\eG5":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | CPMTerminalAttributeInverseVideo | CPMTerminalAttributeUnderlined];	),
		@"\eG6":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | CPMTerminalAttributeInverseVideo | CPMTerminalAttributeBlinking];		),
		@"\eG7":		CPMTerminalAction(	[controlSet outputInlineAttribute:CPMTerminalAttributeLoadModal | CPMTerminalAttributeInverseVideo | CPMTerminalAttributeUnderlined];	),

		@"\e*":			CPMTerminalAction(	[controlSet setCursorX:0 y:0]; [controlSet clearToEndOfScreen];	),
	};
}

+ (NSDictionary *)adm42Additions
{
	return @{
		@"\e~1":			CPMTerminalAction(	[controlSet setCursorX:0 y:0]; [controlSet clearToEndOfScreen]; controlSet.cursorIsDisabled = YES;	),
	};
}

+ (NSDictionary *)televideoAdditions
{
	return @{
		@"\eB0":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeInverseVideo];		),
		@"\eC0":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeInverseVideo];	),
		@"\eB1":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeReducedIntensity];	),
		@"\eC1":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeReducedIntensity];),
		@"\eB2":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeBlinking];			),
		@"\eC2":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeBlinking];		),
		@"\eB3":	CPMTerminalAction(	[controlSet setAttribute:CPMTerminalAttributeUnderlined];		),
		@"\eC3":	CPMTerminalAction(	[controlSet resetAttribute:CPMTerminalAttributeUnderlined];		),
	};
}

+ (instancetype)ADM3AControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];
	[set registerActionsByPrefix:[self adm3aActions]];
	return set;
}

+ (instancetype)ADM5ControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];
	[set registerActionsByPrefix:[self adm3aActions]];
	[set registerActionsByPrefix:[self adm5Additions]];
	return set;
}

+ (instancetype)televideoControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];
	[set registerActionsByPrefix:[self adm3aActions]];
	[set registerActionsByPrefix:[self televideoAdditions]];
	return set;
}

+ (instancetype)ADM21ControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];
	[set registerActionsByPrefix:[self adm3aActions]];
	[set registerActionsByPrefix:[self adm21Additions]];
	return set;
}

+ (instancetype)ADM42ControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];
	[set registerActionsByPrefix:[self adm3aActions]];
	[set registerActionsByPrefix:[self adm21Additions]];
	[set registerActionsByPrefix:[self adm42Additions]];
	return set;
}

@end
