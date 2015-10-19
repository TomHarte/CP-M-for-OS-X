//
//  CPMTerminalControlSequenceTree.m
//  CPM for OS X
//
//  Created by Thomas Harte on 13/10/2015.
//  Copyright © 2015 Thomas Harte. All rights reserved.
//

#import "TerminalControlSequenceTree.h"

@implementation CPMTerminalControlSequenceTree
{
	CPMTerminalControlSequenceTree *_treesByFirstCharacter[256];
	CPMTerminalControlSequence *_sequence;
}

+ (CPMTerminalControlSequence *)cantFindSentinel
{
	return nil;
}

+ (CPMTerminalControlSequence *)mightFindSentinel
{
	return (CPMTerminalControlSequence *)@NO;
}

- (instancetype)initWithControlSequences:(NSArray<CPMTerminalControlSequence *>*)sequences
{
	return [self initWithControlSequences:sequences depth:0];
}

- (instancetype)initWithControlSequences:(NSArray<CPMTerminalControlSequence *>*)sequences depth:(NSUInteger)depth
{
	self = [super init];

	if(self)
	{
		NSMutableDictionary *sequencesByCharacter = [NSMutableDictionary new];

		for(CPMTerminalControlSequence *sequence in sequences)
		{
			NSString *const pattern = sequence.pattern;

			if(pattern.length == depth)
			{
				_sequence = sequence;
				break;
			}

			NSNumber *const character = @([pattern characterAtIndex:depth]);

			NSMutableArray *childSequences = sequencesByCharacter[character];
			if(!childSequences)
			{
				childSequences = [NSMutableArray new];
				sequencesByCharacter[character] = childSequences;
			}
			[childSequences addObject:sequence];
		}

		if(!_sequence)
		{
			for(NSNumber *character in [sequencesByCharacter allKeys])
			{
				NSArray *const childSequences = sequencesByCharacter[character];
				_treesByFirstCharacter[[character unsignedIntegerValue]] = [[[self class] alloc] initWithControlSequences:childSequences depth:depth+1];
			}
		}
	}

	return self;
}

- (CPMTerminalControlSequence *)sequenceMatchingBytes:(const uint8_t *)bytes length:(NSUInteger)length
{
	return [self sequenceMatchingBytes:bytes length:length depth:0];
}

- (CPMTerminalControlSequence *)sequenceMatchingBytes:(const uint8_t *)bytes length:(NSUInteger)length depth:(NSUInteger)depth
{
	// if there's something at this node, a leaf has been reached so that's the answer;
	// if we're still looking but the input string isn't long enough to find any more then
	// indicate that something might be found but isn't yet
	if(_sequence)				return _sequence;
	if(!length)					return [[self class] mightFindSentinel];

	// otherwise consider both a potential wildcard match and an exact match
	CPMTerminalControlSequence *wildcardFind	= [_treesByFirstCharacter['?']		sequenceMatchingBytes:bytes+1 length:length-1 depth:depth+1];
	CPMTerminalControlSequence *directFind		= [_treesByFirstCharacter[*bytes]	sequenceMatchingBytes:bytes+1 length:length-1 depth:depth+1];

	// if no match was found then that's no match in total
	if(!wildcardFind && !directFind) return nil;

	// if two matches were found, prefer the shorter
	if([wildcardFind isKindOfClass:[CPMTerminalControlSequence class]] && [directFind isKindOfClass:[CPMTerminalControlSequence class]])
	{
		return wildcardFind.pattern.length < directFind.pattern.length ? wildcardFind : directFind;
	}

	// if one match was found return it directly
	if([wildcardFind isKindOfClass:[CPMTerminalControlSequence class]]) return wildcardFind;
	if([directFind isKindOfClass:[CPMTerminalControlSequence class]]) return directFind;

	// if we got to here then a might find sentinel was returned for one of the searches,
	// and no actual find improved upon it. So pass the might find upwards.
	return [[self class] mightFindSentinel];
}

- (NSString *)description
{
	NSMutableDictionary *treesByFirstCharacter = [NSMutableDictionary new];
	for(int c = 0; c < 256; c++)
	{
		CPMTerminalControlSequenceTree *const sequence = _treesByFirstCharacter[c];
		if(sequence)
		{
			treesByFirstCharacter[@(c)] = sequence;
		}
	}
	return [[super description] stringByAppendingFormat:@"; subtrees: %@", treesByFirstCharacter];
}

@end
