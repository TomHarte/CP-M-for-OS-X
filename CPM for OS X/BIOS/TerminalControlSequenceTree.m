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
	NSDictionary *_treesByFirstCharacter;
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
			NSMutableDictionary *treesByFirstCharacter = [NSMutableDictionary dictionaryWithCapacity:sequencesByCharacter.count];
			for(NSNumber *character in [sequencesByCharacter allKeys])
			{
				NSArray *const childSequences = sequencesByCharacter[character];
				treesByFirstCharacter[character] = [[[self class] alloc] initWithControlSequences:childSequences depth:depth+1];
			}

			_treesByFirstCharacter = [treesByFirstCharacter copy];
		}
	}

	return self;
}

- (CPMTerminalControlSequence *)sequenceMatchingString:(NSString *)string
{
	return [self sequenceMatchingString:string depth:0];
}

- (CPMTerminalControlSequence *)sequenceMatchingString:(NSString *)string depth:(NSUInteger)depth
{
	// if there's something at this node, a leaf has been reached so that's the answer;
	// if we're still looking but the input string isn't long enough to find any more then
	// indicate that something might be found but isn't yet
	if(_sequence)				return _sequence;
	if(depth >= string.length)	return [[self class] mightFindSentinel];

	// otherwise consider both a potential wildcard match and an exact match
	CPMTerminalControlSequence *wildcardFind = [_treesByFirstCharacter[@('?')] sequenceMatchingString:string depth:depth+1];
	CPMTerminalControlSequence *directFind = [_treesByFirstCharacter[@([string characterAtIndex:depth])] sequenceMatchingString:string depth:depth+1];

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
	return [[super description] stringByAppendingFormat:@"; subtrees: %@", _treesByFirstCharacter];
}

@end
