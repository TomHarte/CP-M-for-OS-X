//
//  CPMTerminalControlSequence.m
//  CPM for OS X
//
//  Created by Thomas Harte on 20/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "TerminalControlSequence.h"

@implementation CPMTerminalControlSequence

- (id)initWithPattern:(NSString *)pattern action:(dispatch_block_t)action
{
	self = [super init];

	if(self)
	{
		_pattern = [pattern copy];
		_action = [action copy];
	}

	return self;
}

- (NSUInteger)hash
{
	return [self.pattern hash];
}

- (id)copyWithZone:(NSZone *)zone
{
	return self;
}

- (BOOL)isEqual:(CPMTerminalControlSequence *)otherSequence
{
	if(![otherSequence isKindOfClass:[self class]]) return NO;
	return [self.pattern isEqualToString:otherSequence.pattern];
}

@end
