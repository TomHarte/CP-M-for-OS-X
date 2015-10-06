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

- (id)initWithAddress:(uint16_t)address inMemory:(CPMRAMModule *)memory defaultDrive:(uint8_t)defaultDrive;

@property (nonatomic, readonly) uint8_t drive;
@property (nonatomic, readonly, strong) NSString *filename;
@property (nonatomic, readonly, strong) NSString *fileType;

@property (nonatomic, assign) size_t linearFileOffset;
@property (nonatomic, assign) size_t randomFileOffset;

- (NSString *)nameWithExtension;
- (NSString *)renameTargetWithExtension;
- (void)setNameWithExtension:(NSString *)nameWithExtension;

- (NSPredicate *)matchesPredicate;

@end

