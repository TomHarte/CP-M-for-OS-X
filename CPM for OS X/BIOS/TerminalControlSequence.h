//
//  CPMTerminalControlSequence.h
//  CPM for OS X
//
//  Created by Thomas Harte on 20/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CPMTerminalControlSequence : NSObject <NSCopying>

+ (id)terminalControlSequenceWithStart:(NSString *)start requiredLength:(NSUInteger)requiredLength action:(dispatch_block_t)action;
+ (id)terminalControlSequenceWithStart:(NSString *)start action:(dispatch_block_t)action;

@property (nonatomic, readonly) NSString *start;
@property (nonatomic, readonly) NSUInteger requiredLength;
@property (nonatomic, readonly) dispatch_block_t action;

@end
