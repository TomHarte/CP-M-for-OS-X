//
//  CPMFileControlBlock.h
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CPMRAMModule;

@interface CPMFileControlBlock : NSObject <NSCopying>

+ (id)fileControlBlockWithAddress:(uint16_t)address inMemory:(CPMRAMModule *)memory;

@property (nonatomic, readonly) uint8_t drive;
@property (nonatomic, readonly, retain) NSString *fileName;
@property (nonatomic, readonly, retain) NSString *fileType;

@property (nonatomic, assign) size_t linearFileOffset;
@property (nonatomic, readonly) size_t randomFileOffset;

- (NSString *)nameWithExtension;
- (void)setNameWithExtension:(NSString *)nameWithExtension;

- (NSPredicate *)matchesPredicate;

@end

