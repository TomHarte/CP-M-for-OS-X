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
	return [[self alloc] initWithStart:start requiredLength:requiredLength action:action];
}

+ (id)terminalControlSequenceWithStart:(NSString *)start action:(dispatch_block_t)action
{
	return [[self alloc] initWithStart:start requiredLength:[start length] action:action];
}

- (id)initWithStart:(NSString *)start requiredLength:(NSUInteger)requiredLength action:(dispatch_block_t)action
{
	self = [super init];

	if(self)
	{
		_start = start;
		_requiredLength = requiredLength;
		_action = [action copy];
	}

	return self;
}

- (NSUInteger)hash
{
	return [self.start hash];
}

- (id)copyWithZone:(NSZone *)zone
{
	CPMTerminalControlSequence *copy = [[CPMTerminalControlSequence allocWithZone:zone] init];
	copy->_start = self.start;
	copy->_requiredLength = self.requiredLength;
	copy->_action = self.action;
	
	return copy;
}

- (BOOL)isEqual:(CPMTerminalControlSequence *)otherSequence
{
	if(![otherSequence isKindOfClass:[self class]]) return NO;
	return [self.start isEqualToString:otherSequence.start];
}

@end
