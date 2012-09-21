//
//  CPMTerminalControlSequence.m
//  CPM for OS X
//
//  Created by Thomas Harte on 20/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalControlSequence.h"

@implementation CPMTerminalControlSequence

+ (id)terminalControlSequenceWithStart:(NSString *)start requiredLength:(NSUInteger)requiredLength action:(dispatch_block_t)action
{
	return [[[self alloc] initWithStart:start requiredLength:requiredLength action:action] autorelease];
}

+ (id)terminalControlSequenceWithStart:(NSString *)start action:(dispatch_block_t)action
{
	return [[[self alloc] initWithStart:start requiredLength:[start length] action:action] autorelease];
}

- (id)initWithStart:(NSString *)start requiredLength:(NSUInteger)requiredLength action:(dispatch_block_t)action
{
	self = [super init];

	if(self)
	{
		_start = [start retain];
		_requiredLength = requiredLength;
		_action = [action copy];
	}

	return self;
}

- (void)dealloc
{
	[_start release], _start = nil;
	[_action release], _action = nil;
	[super dealloc];
}

- (NSUInteger)hash
{
	return [self.start hash];
}

- (id)copyWithZone:(NSZone *)zone
{
	CPMTerminalControlSequence *copy = [[CPMTerminalControlSequence allocWithZone:zone] init];
	copy->_start = [self.start retain];
	copy->_requiredLength = self.requiredLength;
	copy->_action = [self.action retain];
	
	return copy;
}

- (BOOL)isEqual:(CPMTerminalControlSequence *)otherSequence
{
	if(![otherSequence isKindOfClass:[self class]]) return NO;
	return [self.start isEqualToString:otherSequence.start];
}

@end
