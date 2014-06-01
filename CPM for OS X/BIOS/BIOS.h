//
//  CPMBIOS.h
//  CPM for OS X
//
//  Created by Thomas Harte on 12/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Processor.h"
#import "TerminalView.h"

@class CPMBIOS;

@protocol CPMBIOSDelegate <NSObject>
- (void)BIOSProgramDidExit:(CPMBIOS *)bios;
@end

@interface CPMBIOS : NSObject <CPMTerminalViewDelegate>

- (id)initWithTerminalView:(CPMTerminalView *)terminalView processor:(CPMProcessor *)processor;

- (CPMProcessorShouldBlock)makeCall:(int)callNumber;

// call-ins for the BDOS
- (uint8_t)consoleStatus;						// i.e. CONST, function 2
- (void)writeConsoleOutput:(uint8_t)characer;	// i.e. CONOUT, function 4
- (CPMProcessorShouldBlock)readCharacterAndEcho;

- (uint8_t)dequeueCharacterIfAvailable;			// BDOS call 6, e = 0xff

@property (nonatomic, weak) id <CPMBIOSDelegate> delegate;

@end
