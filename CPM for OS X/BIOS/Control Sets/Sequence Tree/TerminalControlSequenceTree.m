//
//  CPMTerminalControlSequenceTree.m
//  CPM for OS X
//
//  Created by Thomas Harte on 13/10/2015.
//  Copyright © 2015 Thomas Harte. All rights reserved.
//

#import "TerminalControlSequenceTree.h"
#import "TerminalControlSet.h"
#import "TerminalControlSet+Actions.h"

@implementation CPMTerminalControlSequenceTree
{
	CPMTerminalControlSequenceTree *_treesByFirstCharacter[256];
	CPMTerminalControlSequenceAction _action;
}

- (instancetype)initWithAction:(CPMTerminalControlSequenceAction)action
{
	self = [super init];

	if(self)
	{
		_action = action;
	}

	return self;
}

- (void)insertSubtree:(CPMTerminalControlSequenceTree *)subtree forBytes:(const uint8_t *)bytes
{
	if(!bytes[1])
	{
		_treesByFirstCharacter[bytes[0]] = subtree;
		return;
	}

	if(!_treesByFirstCharacter[bytes[0]])
	{
		_treesByFirstCharacter[bytes[0]] = [[CPMTerminalControlSequenceTree alloc] init];
	}
	[_treesByFirstCharacter[bytes[0]] insertSubtree:subtree forBytes:bytes+1];
}

- (NSUInteger)matchBytes:(const uint8_t *)bytes length:(NSUInteger)length controlSet:(CPMTerminalControlSet *)controlSet
{
	return [self sequenceMatchingBytes:bytes length:length depth:0 controlSet:controlSet];
}

- (NSUInteger)sequenceMatchingBytes:(const uint8_t *)bytes length:(NSUInteger)length depth:(NSUInteger)depth controlSet:(CPMTerminalControlSet *)controlSet
{
	// if there's something at this node, a leaf has been reached so that's the answer;
	// if we're still looking but the input string isn't long enough to find any more then
	// indicate that something might be found but isn't yet
	if(_action)
	{
		[controlSet recordRecognisedControlCode];
		_action(controlSet, bytes);
		return depth;
	}

	if(!length)
		return 0;

	CPMTerminalControlSequenceTree *nextSequence = _treesByFirstCharacter[bytes[depth]];
	if(!nextSequence) nextSequence = _treesByFirstCharacter['?'];

	if(!nextSequence)
	{
		[controlSet outputCharacter:bytes[0] > 31  && bytes[0] < 128? bytes[0] : ' '];
		return 1;
	}

	return [nextSequence sequenceMatchingBytes:bytes length:length-1 depth:depth+1 controlSet:controlSet];
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
