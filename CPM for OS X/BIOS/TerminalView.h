//
//  CPMTerminalView.h
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CPMTerminalView;

@protocol CPMTerminaViewDelegate <NSObject>

- (void)terminalViewDidAddCharactersToBuffer:(CPMTerminalView *)terminalView;

@end

@interface CPMTerminalView : NSView <NSDraggingDestination>

- (void)writeCharacter:(char)character;

- (BOOL)hasCharacterToDequeue;
- (unichar)dequeueBufferedCharacter;

@property (nonatomic, assign) id <CPMTerminaViewDelegate> delegate;
@property (nonatomic, readonly) CGSize idealSize;

@end
