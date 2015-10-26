//
//  CPMTerminalControlSet+TerminalControlSet_WY50.m
//  CPM for OS X
//
//  Created by Thomas Harte on 25/10/2015.
//  Copyright © 2015 Thomas Harte. All rights reserved.
//

#import "TerminalControlSet+WY50.h"
#import "TerminalControlSet+Actions.h"

@interface CPMTerminalControlSequenceTreeWY50Attribute: CPMTerminalControlSequenceTree
@end

@implementation CPMTerminalControlSequenceTreeWY50Attribute

- (NSUInteger)sequenceMatchingBytes:(const uint8_t *)bytes length:(NSUInteger)length depth:(NSUInteger)depth controlSet:(CPMTerminalControlSet *)controlSet
{
	[controlSet recordRecognisedControlCode];
	[controlSet setCursorX:controlSet.cursorX+2 y:controlSet.cursorY];

	CPMTerminalAttribute attributes = 0;
	uint8_t inputAttributes = bytes[2] != '\e' ? bytes[2] : 0;

	// 0010 0000 -> space code (20h)
	// 0011 0000 -> normal

	// 0011 0001 -> blank (no display)
	// 0011 0100 -> reverse
	// 0011 1000 -> underscore
	// 0111 0000 -> dim

	if(inputAttributes)
	{
		NSLog(@"%02x %02x %02x: %c / %02x -> %02x", bytes[0], bytes[1], bytes[2], inputAttributes, inputAttributes, attributes);
//		if(inputQueue[2]&0x01) attributes |= CPMTerminalAttributeInverseVideo; // blank
		if(inputAttributes&0x04) attributes |= CPMTerminalAttributeInverseVideo;
		if(inputAttributes&0x08) attributes |= CPMTerminalAttributeUnderlined;
		if(inputAttributes&0x40) attributes |= CPMTerminalAttributeReducedIntensity;
		[controlSet setAttributes:attributes];
	}

	return bytes[2] != '\e' ? 3 : 2;
}

@end

@implementation CPMTerminalControlSet (WY50)

+ (instancetype)WY50ControlSet
{
	CPMTerminalControlSet *const set = [[self alloc] initWithWidth:80 height:24 isColour:NO];

	NSDictionary *const actions = @{
		@"\e=??":	CPMTerminalAction(
//										NSLog(@"%02x %02x", inputQueue[3], inputQueue[2]);
										[controlSet
												setCursorX:(NSUInteger)(inputQueue[3] - 32)%controlSet.width
												y:(NSUInteger)(inputQueue[2] - 32)%controlSet.height];
									),
		@"\x1a":	CPMTerminalAction(
										[controlSet mapCharactersFromCursorUsingMapper:^(unichar *input, CPMTerminalAttribute *attribute) {
											if(!((*attribute)&CPMTerminalAttributeProtected))
											{
												*input = ' ';
											}
										}];
									),
//		@"\eG?":	CPMTerminalAction(
//										[controlSet outputCharacter:' '];
//
//										CPMTerminalAttribute attributes = 0;
////										if(inputQueue[2]&0x01) attributes |= CPMTerminalAttributeInverseVideo; // blank
//										if(inputQueue[2]&0x20) attributes |= CPMTerminalAttributeInverseVideo;
//										if(inputQueue[2]&0x08) attributes |= CPMTerminalAttributeUnderlined;
//										if(inputQueue[2]&0x40) attributes |= CPMTerminalAttributeReducedIntensity;
//										[controlSet setAttributes:attributes];
//									),
//		@"\eH?":	CPMTerminalAction(
//									),
	};

	[[set sequenceTree] insertSubtree:[[CPMTerminalControlSequenceTreeWY50Attribute alloc] init] forPrefix:(uint8_t *)"\eG???"];
	[set registerActionsByPrefix:actions];
	return set;
}

@end
