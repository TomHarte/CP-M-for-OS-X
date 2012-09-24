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

@protocol CPMTerminaViewDelegate <NSObject>

- (void)terminalViewDidAddCharactersToBuffer:(CPMTerminalView *)terminalView;

@end

@interface CPMTerminalView : NSView <NSDraggingDestination, CPMTerminalControlSetDelegate>

/*
	These three are thread safe.
*/
- (void)writeCharacter:(char)character;

- (BOOL)hasCharacterToDequeue;
- (unichar)dequeueBufferedCharacter;

/*
	The following two are intended for use on the main queue only.
*/
@property (nonatomic, assign) id <CPMTerminaViewDelegate> delegate;
@property (nonatomic, readonly) CGSize idealSize;

- (void)invalidate;

@end
