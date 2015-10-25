//
//  CPMTerminalControlSequenceTree.h
//  CPM for OS X
//
//  Created by Thomas Harte on 13/10/2015.
//  Copyright © 2015 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CPMTerminalControlSet;
typedef void (^ CPMTerminalControlSequenceAction)(CPMTerminalControlSet *controlSet, const uint8_t *const inputQueue);
#define CPMTerminalAction(...) ^(CPMTerminalControlSet *controlSet, const uint8_t *const inputQueue) { __VA_ARGS__ }

@interface CPMTerminalControlSequenceTree : NSObject

// also supports regular init
- (instancetype)initWithAction:(CPMTerminalControlSequenceAction)action;

- (void)insertSubtree:(CPMTerminalControlSequenceTree *)subtree forPrefix:(const uint8_t *)bytes;
- (void)insertAction:(CPMTerminalControlSequenceAction)action forPrefix:(const uint8_t *)bytes;

- (NSUInteger)matchBytes:(const uint8_t *)bytes length:(NSUInteger)length controlSet:(CPMTerminalControlSet *)controlSet;

@end
