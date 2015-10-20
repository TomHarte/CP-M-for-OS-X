//
//  CPMTerminalControlSequenceTree.h
//  CPM for OS X
//
//  Created by Thomas Harte on 13/10/2015.
//  Copyright © 2015 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TerminalControlSequence.h"

@interface CPMTerminalControlSequenceTree : NSObject

- (instancetype)initWithAction:(CPMTerminalControlSequenceAction)action;

- (void)insertSubtree:(CPMTerminalControlSequenceTree *)subtree forBytes:(const uint8_t *)bytes;

- (NSInteger)matchBytes:(const uint8_t *)bytes length:(NSInteger)length controlSet:(CPMTerminalControlSet *)controlSet;

@end
