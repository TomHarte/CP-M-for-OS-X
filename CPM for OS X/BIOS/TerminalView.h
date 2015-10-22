//
//  CPMTerminalView.h
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TerminalControlSet.h"

@class CPMTerminalView;

/*
	This delegate protocol is guaranteed to be called on the main queue
*/
@protocol CPMTerminalViewDelegate <NSObject>

- (void)terminalViewDidAddCharactersToBuffer:(CPMTerminalView *)terminalView;

@optional
- (void)terminalViewDidChangeIdealRect:(CPMTerminalView *)terminalView;
- (void)terminalView:(CPMTerminalView *)terminalView didReceiveFileAtURL:(NSURL *)URL;

@end

@interface CPMTerminalView : NSView <NSDraggingDestination, CPMTerminalControlSetDelegate>

/*
	These three are thread safe.
*/
- (void)writeByte:(uint8_t)character;

- (BOOL)hasCharacterToDequeue;
- (unichar)dequeueBufferedCharacter;

- (void)addStringToInputQueue:(NSString *)string filterToASCII:(BOOL)filterToASCII;

@property (nonatomic, assign) dispatch_queue_t callingDispatchQueue;

/*
	The following two are intended for use on the main queue only.
*/
@property (nonatomic, weak) id <CPMTerminalViewDelegate> delegate;
@property (nonatomic, readonly) CGSize idealSize;

- (void)invalidate;

@end
