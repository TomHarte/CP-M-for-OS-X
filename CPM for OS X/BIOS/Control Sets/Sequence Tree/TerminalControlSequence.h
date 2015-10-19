//
//  CPMTerminalControlSequence.h
//  CPM for OS X
//
//  Created by Thomas Harte on 20/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CPMTerminalControlSet;
typedef void (^ CPMTerminalControlSequenceAction)(CPMTerminalControlSet *controlSet, const char *const inputQueue);

@interface CPMTerminalControlSequence : NSObject <NSCopying>

- (id)initWithPattern:(NSString *)start action:(CPMTerminalControlSequenceAction)action;

@property (nonatomic, readonly) NSString *pattern;
@property (nonatomic, readonly) CPMTerminalControlSequenceAction action;

@end

extern CPMTerminalControlSequence *TCSMake(NSString *pattern, CPMTerminalControlSequenceAction action);

#define CPMTerminalAction(...) ^(CPMTerminalControlSet *controlSet, const char *const inputQueue) { __VA_ARGS__ }
