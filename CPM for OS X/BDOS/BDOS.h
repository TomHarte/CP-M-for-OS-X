//
//  BDOS.h
//  CPM for OS X
//
//  Created by Thomas Harte on 12/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Processor.h"
#import "TerminalView.h"

@class CPMTerminalView;
@class CPMBDOS;

@protocol CPMBDOSDelegate <NSObject>

- (void)bdosWillUnblock:(CPMBDOS *)bdos;

@end

@interface CPMBDOS : NSObject <CPMProcessorDelegate, CPMTerminalViewDelegate>

- (id)initWithContentsOfURL:(NSURL *)URL terminalView:(CPMTerminalView *)terminalView;

- (void)runForTimeInterval:(NSTimeInterval)interval;
- (void)runForNumberOfInstructions:(NSUInteger)numberOfInstructions;

@property (nonatomic, readonly) BOOL didBlock;
@property (nonatomic, readonly) BOOL isBlocked;
@property (nonatomic, assign) dispatch_queue_t callingDispatchQueue;

- (void)addAccessToURL:(NSURL *)URL;

@property (nonatomic, weak) id <CPMBDOSDelegate> delegate;

@end
