//
//  CPMTerminaViewControlSet.h
//  CPM for OS X
//
//  Created by Thomas Harte on 22/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kCPMTerminalAttributeInverseVideoOn			0x01
#define kCPMTerminalAttributeReducedIntensityOn		0x02
#define kCPMTerminalAttributeBlinkingOn				0x04
#define kCPMTerminalAttributeUnderlinedOn			0x08

@class CPMTerminaViewControlSet;

@protocol CPMTerminaViewControlSetDelegate <NSObject>

- (void)terminalViewControlSetDidChangeOutput:(CPMTerminaViewControlSet *)controlSet;

@end

@interface CPMTerminaViewControlSet : NSObject

+ (id)ADM3AControlSet;

@property (nonatomic, assign) BOOL isTrackingCodePoints;
@property (nonatomic, readonly) NSUInteger width, height;
@property (nonatomic, assign) id <CPMTerminaViewControlSetDelegate> delegate;

- (void)writeCharacter:(uint8_t)character;

- (uint8_t *)characterBuffer;
- (uint16_t *)attributeBuffer;

@end
