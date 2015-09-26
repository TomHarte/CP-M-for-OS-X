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

@interface CPMFileControlBlock ()

@property (nonatomic, strong) NSString *fileName;
@property (nonatomic, strong) NSString *fileType;

@end

@implementation CPMFileControlBlock
{
	CPMRAMModule *memory;
	uint16_t baseAddress;
	NSData *_sourceData;
}

- (void)trimTailSpacesIn:(char *)buffer
{
	size_t c = strlen(buffer);
	while(c--)
	{
		if(buffer[c] == ' ')
			buffer[c] = '\0';
		else
			return;
	}
}

- (void)nameAndTypeFomData:(NSData *)data offset:(size_t)offset name:(NSString *__strong *)name type:(NSString *__strong *)type
{
	uint8_t *bytes = (uint8_t *)[data bytes];
	char fileName[9], fileType[4];
	for(size_t c = 0; c < 8; c++)	fileName[c] = bytes[offset+c]&0x7f;
	for(size_t c = 0; c < 3; c++)	fileType[c] = bytes[offset+c+8]&0x7f;

	// add final terminators
	fileName[8] = fileType[3] = '\0';

	[self trimTailSpacesIn:fileName];
	[self trimTailSpacesIn:fileType];

	*name = [NSString stringWithFormat:@"%s", fileName];
	*type = [NSString stringWithFormat:@"%s", fileType];
}

- (id)initWithAddress:(uint16_t)address inMemory:(CPMRAMModule *)someMemory
{
	self = [super init];

	if(self)
	{
		memory = someMemory;
		baseAddress = address;

		_sourceData = [memory dataAtAddress:address length:36];
		uint8_t *bytes = (uint8_t *)[_sourceData bytes];

		_drive = bytes[0];
		[self nameAndTypeFomData:_sourceData offset:1 name:&_fileName type:&_fileType];

		uint8_t record = bytes[0x20]&127;
		uint8_t extent = bytes[0x0c]&31;
		uint8_t moduleNumber = bytes[0x0e];

		_linearFileOffset = (size_t)((record | (extent << 7) | (moduleNumber << 12)) << 7);

		_randomFileOffset = (size_t)((bytes[0x21] | (bytes[0x22] << 8) | ((bytes[0x23]&3) << 16)) << 7);
	}

	return self;
}

- (void)setLinearFileOffset:(size_t)newLinearFileOffset
{
	_linearFileOffset = newLinearFileOffset;

	[memory setValue:(uint8_t)((self.linearFileOffset >> 7)&127)	atAddress:baseAddress+0x20];
	[memory setValue:(uint8_t)((self.linearFileOffset >> 14)&31)	atAddress:baseAddress+0x0c];
	[memory setValue:(uint8_t)(self.linearFileOffset >> 19)			atAddress:baseAddress+0x0e];
}

- (void)setRandomFileOffset:(size_t)randomFileOffset
{
	_randomFileOffset = randomFileOffset;

	[memory setValue:(uint8_t)(randomFileOffset&0xff)			atAddress:baseAddress+0x21];
	[memory setValue:(uint8_t)((randomFileOffset >> 8)&0xff)	atAddress:baseAddress+0x22];
	[memory setValue:(uint8_t)((randomFileOffset >> 16)&0x03)	atAddress:baseAddress+0x23];
}

- (id)copyWithZone:(NSZone *)zone
{
	CPMFileControlBlock *newBlock = [[CPMFileControlBlock alloc] init];

	newBlock->_fileName = self.fileName;
	newBlock->_fileType = self.fileType;
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
	return [NSString stringWithFormat:@"[%c:] %@ [.] %@, drive %d", 'A' + self.drive - 1, self.fileName, self.fileType, self.drive];
}

- (NSString *)fullNameWithName:(NSString *)name type:(NSString *)type
{
	if([type length])
		return [NSString stringWithFormat:@"%@.%@", name, type];
	else
		return name;
}

- (NSString *)renameTargetWithExtension
{
	NSString *name, *type;
	[self nameAndTypeFomData:_sourceData offset:17 name:&name type:&type];
	return [self fullNameWithName:name type:type];
}

- (NSString *)nameWithExtension
{
	return [self fullNameWithName:self.fileName type:self.fileType];
}

- (void)unpackNameWithExtension:(NSString *)evaluatedObject toName:(NSString **)comparisonName extension:(NSString **)comparisonType
{
	*comparisonType = nil;

	// find the name and type from the incoming file name
	if([evaluatedObject rangeOfString:@"."].location == NSNotFound)
	{
		// if there's no dot in this file name then
		// just trim it if necessary
		*comparisonName = evaluatedObject;
	}
	else
	{
		// there's a dot in it, so at least two components
		NSArray *components = [evaluatedObject componentsSeparatedByString:@"."];
		*comparisonName = components[0];
		*comparisonType = components[1];
	}

	// trim appropriately (TODO: maybe some Win95-style mangling?)
	if([*comparisonName length] > 8)
		*comparisonName = [*comparisonName substringToIndex:8];

	if([*comparisonType length] > 3)
		*comparisonType = [*comparisonType substringToIndex:3];
}

- (NSPredicate *)matchesPredicate
{
	return [NSPredicate predicateWithBlock:^BOOL(NSString *evaluatedObject, NSDictionary *bindings)
	{
		NSString *comparisonName = nil, *comparisonType = nil;
		[self unpackNameWithExtension:evaluatedObject toName:&comparisonName extension:&comparisonType];

		// now compare
		BOOL areEqual = [self wildcardComparePattern:self.fileName string:comparisonName];
		areEqual &= [self wildcardComparePattern:self.fileType string:comparisonType];

		return areEqual;
	}];
}

- (BOOL)wildcardComparePattern:(NSString *)pattern string:(NSString *)string
{
	// we'll remove case from the equation
	pattern = [pattern lowercaseString];
	string = [string lowercaseString];

	for(NSUInteger index = 0; index < [pattern length]; index++)
	{
		unichar patternCharacter = [pattern characterAtIndex:index];

		if(index < string.length)
		{
			unichar stringCharacter = [string characterAtIndex:index];
			
			if(patternCharacter != '?' && stringCharacter != patternCharacter)
				return NO;
		}
		else
		{
			if(patternCharacter != '?')
				return NO;
		}
	}

	return YES;
}

- (void)setNameWithExtension:(NSString *)nameWithExtension
{
	// split up the input string
	NSString *name, *type;
	[self unpackNameWithExtension:nameWithExtension toName:&name extension:&type];

	// store to our local properties
	self.fileName = name;
	self.fileType = type;

	// write out to memory
	for(uint16_t index = 0; index < 8; index++)
	{
		unichar character = (index < name.length) ? [name characterAtIndex:index] : ' ';
		[memory setValue:character&0xff atAddress:baseAddress+1+index];
	}
	for(uint16_t index = 0; index < 3; index++)
	{
		unichar character = (index < type.length) ? [type characterAtIndex:index] : ' ';
		[memory setValue:character&0xff atAddress:baseAddress+9+index];
	}
}

@end
