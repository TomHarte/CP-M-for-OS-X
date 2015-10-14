//
//  CPMTerminalControlSequence.h
//  CPM for OS X
//
//  Created by Thomas Harte on 20/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CPMTerminalControlSequence : NSObject <NSCopying>

- (id)initWithPattern:(NSString *)start action:(dispatch_block_t)action;

@property (nonatomic, readonly) NSString *pattern;
@property (nonatomic, readonly) dispatch_block_t action;

@end
