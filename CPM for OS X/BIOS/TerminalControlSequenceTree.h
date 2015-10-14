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

+ (CPMTerminalControlSequence *)cantFindSentinel;
+ (CPMTerminalControlSequence *)mightFindSentinel;

- (instancetype)initWithControlSequences:(NSArray<CPMTerminalControlSequence *>*)sequences;
- (CPMTerminalControlSequence *)sequenceMatchingString:(NSString *)string;

@end
