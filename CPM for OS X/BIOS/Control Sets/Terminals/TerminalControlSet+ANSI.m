//
//  CPMTerminalControlSet+ANSI.m
//  CPM for OS X
//
//  Created by Thomas Harte on 13/10/2015.
//  Copyright (c) 2015 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+ANSI.h"
#import "TerminalControlSet+Actions.h"

@implementation CPMTerminalControlSet (ANSI)

+ (instancetype)ANSIControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];

	NSDictionary *const actions = @{
		@"\33[K":	CPMTerminalAction(	[controlSet clearToEndOfLine];			),
		@"\33[1K":	CPMTerminalAction(	[controlSet clearFromStartOfLine];		),
		@"\33[2K":	CPMTerminalAction(
										[controlSet clearToEndOfLine];
										[controlSet clearFromStartOfLine];
									),
		@"\33[??;??H":	CPMTerminalAction(
										NSUInteger row = (NSUInteger)(((inputQueue[2] - '0') * 10) + (inputQueue[3] - '0'));
										NSUInteger column = (NSUInteger)(((inputQueue[5] - '0') * 10) + (inputQueue[6] - '0'));
										[controlSet
											setCursorX:column%controlSet.width
											y:row%controlSet.height];
									),
		@"\33[H":	CPMTerminalAction(
										[controlSet setCursorX:0 y:0];
									),
		@"\33[s":	CPMTerminalAction(	[controlSet saveCursorPosition];		),
		@"\33[u":	CPMTerminalAction(	[controlSet restoreCursorPosition];		),
	};

	[set registerActionsByPrefix:actions];
	return set;
}

@end
