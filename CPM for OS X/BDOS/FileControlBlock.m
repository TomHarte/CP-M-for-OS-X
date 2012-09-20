//
//  CPMFileControlBlock.m
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "FileControlBlock.h"
#import "RAMModule.h"
#include <string.h>

@implementation CPMFileControlBlock
{
	CPMRAMModule *memory;
	uint16_t baseAddress;
}

+ (id)fileControlBlockWithAddress:(uint16_t)address inMemory:(CPMRAMModule *)memory
{
	return [[[self alloc] initWithAddress:address inMemory:memory] autorelease];
}

- (void)trimTailSpacesIn:(char *)buffer
{
	size_t c = strlen(buffer)-1;
	while(c > 0)
	{
		if(buffer[c] == ' ')
			buffer[c] = '\0';
		else
			return;
		c--;
	}
}

- (id)initWithAddress:(uint16_t)address inMemory:(CPMRAMModule *)someMemory
{
	self = [super init];

	if(self)
	{
		memory = [someMemory retain];
		baseAddress = address;

		NSData *data = [memory dataAtAddress:address length:36];
		uint8_t *bytes = (uint8_t *)[data bytes];

		_drive = bytes[0];

		char fileName[9], fileType[4];
		for(int c = 0; c < 8; c++)	fileName[c] = bytes[c+0x01]&0x7f;
		for(int c = 0; c < 3; c++)	fileType[c] = bytes[c+0x09]&0x7f;

		// add final terminators
		fileName[8] = fileType[3] = '\0';
		
		[self trimTailSpacesIn:fileName];
		[self trimTailSpacesIn:fileType];

		_fileName = [[NSString stringWithFormat:@"%s", fileName] retain];
		_fileType = [[NSString stringWithFormat:@"%s", fileType] retain];

		uint8_t record = bytes[0x20]&127;
		uint8_t extent = bytes[0x0c]&31;
		uint8_t moduleNumber = bytes[0x0e];

		_linearFileOffset = (record | (extent << 7) | (moduleNumber << 12)) << 7;

		_randomFileOffset = (bytes[0x21] | (bytes[0x22] << 8) | ((bytes[0x23]&3) << 16)) << 7;
	}

	return self;
}

- (void)setLinearFileOffset:(size_t)newLinearFileOffset
{
	_linearFileOffset = newLinearFileOffset;

	[memory setValue:(self.linearFileOffset >> 7)&127 atAddress:baseAddress+0x20];
	[memory setValue:(self.linearFileOffset >> 14)&31 atAddress:baseAddress+0x0c];
	[memory setValue:self.linearFileOffset >> 19 atAddress:baseAddress+0x0e];
}

- (void)dealloc
{
	[_fileName release], _fileName = nil;
	[_fileType release], _fileType = nil;
	[memory release], memory = nil;
	[super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	CPMFileControlBlock *newBlock = [[CPMFileControlBlock alloc] init];

	newBlock->_fileName = [self.fileName retain];
	newBlock->_fileType = [self.fileType retain];
	newBlock->_drive = self.drive;

	return newBlock;
}

- (BOOL)isEqual:(CPMFileControlBlock *)object
{
	if(![object isKindOfClass:[CPMFileControlBlock class]]) return NO;

	if(object.drive != self.drive) return NO;
	if(![object.fileName isEqual:self.fileName]) return NO;
	if(![object.fileType isEqual:self.fileType]) return NO;

	return YES;
}

- (NSUInteger)hash
{
	return [self.fileType hash] + [self.fileName hash] + self.drive;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ [.] %@, drive %d", self.fileName, self.fileType, self.drive];
}

@end
