//
//  BDOS.m
//  CPM for OS X
//
//  Created by Thomas Harte on 12/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "BDOS.h"

#import "RAMModule.h"
#import "Processor.h"
#import "BIOS.h"
#import "FileControlBlock.h"


@implementation CPMBDOS
{
	CPMRAMModule *_memory;
	CPMProcessor *_processor;
	CPMBIOS *_bios;

	uint16_t _dmaAddress;

	NSMutableDictionary *_fileHandlesByControlBlock;

	NSEnumerator *_searchEnumerator;
}

- (id)initWithContentsOfURL:(NSURL *)URL terminalView:(CPMTerminalView *)terminalView
{
	return [self initWithData:[NSData dataWithContentsOfURL:URL] terminalView:terminalView];
}

- (id)initWithData:(NSData *)data terminalView:(CPMTerminalView *)terminalView
{
	self = [super init];

	if(self)
	{
		// load the nominated executable
		if(!data || !terminalView)
		{
			return nil;
		}

		// create memory, a CPU and a BIOS
		_memory = [[CPMRAMModule alloc] init];
		_processor = [[CPMProcessor alloc] initWithRAM:_memory];
		_bios = [[CPMBIOS alloc] initWithTerminalView:terminalView processor:_processor];

		// copy the executable into memory, set the initial program counter
		[_memory setData:data atAddress:0x100];
		_processor.programCounter = 0x100;

		// configure the bios trapping to occur as late as it can while
		// still having room for a full BIOS jump table
		uint16_t biosAddress = 65536-99;
		_processor.biosAddress = biosAddress;

		// we'll be the delegate, in order to trap all that stuff
		_processor.delegate = self;

		// setup the standard BIOS call
		[_memory setValue:0xc3 atAddress:0];
		[_memory setValue:(biosAddress+3)&0xff atAddress:1];
		[_memory setValue:(biosAddress+3) >> 8 atAddress:2];

		// set the call to perform BDOS functions to go to where the
		// BIOS theoretically starts — this is where the cold start
		// routine would go on a real CP/M machine and we're trying
		// to use the absolute minimal amount of memory possible
		[_memory setValue:0xc3 atAddress:5];
		[_memory setValue:biosAddress&0xff atAddress:6];
		[_memory setValue:biosAddress >> 8 atAddress:7];

		// set the top of the stack to be the address 0000 so that programs
		// that use return to exit function appropriately; also give SP a
		// sensible corresponding value
		[_memory setValue:0x00 atAddress:biosAddress-1];
		[_memory setValue:0x00 atAddress:biosAddress-2];
		_processor.spRegister = biosAddress-2;

		// the things pointed to beyond the BIOS address should all be jumps
		// to actual program code; some CP/M programs read the addresses and
		// use other means to get into the BIOS. So we need to set up appropriate
		// jump statments
		for(int c = biosAddress; c < 65536; c+= 3)
		{
			[_memory setValue:0xc3 atAddress:c];
			[_memory setValue:c&0xff atAddress:c+1];
			[_memory setValue:(c >> 8) atAddress:c+2];
		}

		// also set the default DMA address
		_dmaAddress = 0x80;

		// allocate a dictionary to keep track of our open files
		_fileHandlesByControlBlock = [[NSMutableDictionary alloc] init];
	}

	return self;
}

- (void)runForTimeInterval:(NSTimeInterval)interval;
{
	[_processor runForTimeInterval:interval];
	
	// didBlock should return whether the processor called anything
	// that could block at any time, but for now we'll just report
	// whether it's blocked now
	_didBlock = _processor.isBlocked;
}

- (void)runForNumberOfInstructions:(NSUInteger)numberOfInstructions
{
	[_processor runForNumberOfInstructions:numberOfInstructions];

	// <comment as above>
	_didBlock = _processor.isBlocked;
}

- (CPMProcessorShouldBlock)processor:(CPMProcessor *)processor isMakingBDOSCall:(uint8_t)call parameter:(uint16_t)parameter
{
//		case 10:	/* buffered console input */					break;

	CPMProcessorShouldBlock shouldBlock = NO;

//	NSLog(@"BDOS %d", call);

	switch(call)
	{
		case 0:		shouldBlock = [self exitProgram];								break;
		case 1:		shouldBlock = [_bios readCharacterAndEcho];						break;
		case 2:		shouldBlock = [self writeConsoleOutput:parameter];				break;
		case 6:		shouldBlock = [self directConsoleIOWithParameter:parameter];	break;
		case 9:		shouldBlock = [self outputStringWithParameter:parameter];		break;
		case 11:	shouldBlock = [self getConsoleStatus];							break;
		case 12:	shouldBlock = [self getVersionNumber];							break;
		case 13:	shouldBlock = [self resetAllDisks];								break;
		case 15:	shouldBlock = [self openFileWithParameter:parameter];			break;
		case 16:	shouldBlock = [self closeFileWithParameter:parameter];			break;
		case 17:	shouldBlock	= [self searchForFirstWithParameter:parameter];		break;
		case 18:	shouldBlock	= [self searchForNextWithParameter:parameter];		break;
		case 19:	shouldBlock = [self deleteFileWithParameter:parameter];			break;
		case 20:	shouldBlock = [self readNextRecordWithParameter:parameter];		break;
		case 21:	shouldBlock = [self writeNextRecordWithParameter:parameter];	break;
		case 25:	shouldBlock = [self getCurrentDrive];							break;
		case 26:	shouldBlock = [self setDMAAddressWithParameter:parameter];		break;
		case 33:	shouldBlock = [self readRandomRecordWithParameter:parameter];	break;

		case 14:	// select disk
			[_processor set8bitCPMResult:0];
		break;

		default:
			NSLog(@"!!UNIMPLEMENTED!! BDOS call %d with parameter %04x", call, parameter);
		break;
	}

	return shouldBlock;
}

- (CPMProcessorShouldBlock)processor:(CPMProcessor *)processor isMakingBIOSCall:(uint8_t)call
{
	// we've cheekily set up BIOS call 0 to be our BDOS entry point,
	// so we'll redirect BIOS call 0 manually
	if(!call)
	{
		return [self processor:processor isMakingBDOSCall:processor.bcRegister&0xff parameter:processor.deRegister];
	}

	return [_bios makeCall:call];
}

- (void)processorDidHalt:(CPMProcessor *)processor
{
	NSLog(@"!!Processor did halt!!");
}

- (BOOL)getVersionNumber
{
	// the high part is OS type (CP/M) and the low part is the BCD version number (2.2)
	[_processor set16bitCPMResult:0x0022];

	return NO;
}

- (BOOL)writeConsoleOutput:(uint16_t)character
{
	[_bios writeConsoleOutput:character&0xff];
	return NO;
}

- (BOOL)exitProgram
{
	NSLog(@"Program did exit");
	return YES;
}

- (BOOL)resetAllDisks
{
	_dmaAddress = 0x80;
	return NO;
}

- (BOOL)getCurrentDrive
{
	// return current drive in a; a = 0, b = 1, etc
	NSLog(@"Returned current drive as 0");
	[_processor set8bitCPMResult:0];

	return NO;
}

- (CPMFileControlBlock *)fileControlBlockWithParameter:(uint16_t)parameter
{
	return [[CPMFileControlBlock alloc] initWithAddress:parameter inMemory:_memory];
}

- (BOOL)searchForFirstWithParameter:(uint16_t)parameter
{
	_searchEnumerator = nil;

	if(!self.basePath)
	{
		[_processor set8bitCPMResult:0xff];
	}
	else
	{
		CPMFileControlBlock *fileControlBlock = [self fileControlBlockWithParameter:parameter];

		NSError *error = nil;
		NSArray *allFilesInPath = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:&error];

		NSArray *matchingFiles = [allFilesInPath filteredArrayUsingPredicate:fileControlBlock.matchesPredicate];
		NSLog(@"%@ versus %@ begat %@", allFilesInPath, fileControlBlock, matchingFiles);

		_searchEnumerator = [matchingFiles objectEnumerator];
		return [self searchForNextWithParameter:parameter];
	}

	return NO;
}

- (BOOL)searchForNextWithParameter:(uint16_t)parameter
{
	NSString *nextFileName = [_searchEnumerator nextObject];
	if(!nextFileName)
	{
		[_processor set8bitCPMResult:0xff];
		_searchEnumerator = nil;
		return NO;
	}

	CPMFileControlBlock *fileControlBlock = [self fileControlBlockWithParameter:_dmaAddress];
	fileControlBlock.nameWithExtension = nextFileName;
	[_processor set8bitCPMResult:0];
	return NO;
}

- (BOOL)openFileWithParameter:(uint16_t)parameter
{
	CPMFileControlBlock *fileControlBlock = [self fileControlBlockWithParameter:parameter];

	NSError *error = nil;

	NSString *fullPath = [fileControlBlock nameWithExtension];
	if(self.basePath)
	{
		fullPath = [self.basePath stringByAppendingPathComponent:fullPath];
	}
	NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:fullPath];

	if(handle && !error)
	{
		NSLog(@"Opened %@ for record %04x", fileControlBlock, parameter);

		[_processor set8bitCPMResult:0];
		[_fileHandlesByControlBlock setObject:handle forKey:fileControlBlock];
	}
	else
	{
		NSLog(@"Failed to open %@", fileControlBlock);
		[_processor set8bitCPMResult:0xff];
	}

	return NO;
}

- (BOOL)closeFileWithParameter:(uint16_t)parameter
{
	CPMFileControlBlock *fileControlBlock = [self fileControlBlockWithParameter:parameter];

	NSLog(@"Closing %@", fileControlBlock);
	[_fileHandlesByControlBlock removeObjectForKey:fileControlBlock];
	[_processor set8bitCPMResult:0];

	return NO;
}

- (BOOL)setDMAAddressWithParameter:(uint16_t)parameter
{
	_dmaAddress = parameter;

	return NO;
}

- (BOOL)deleteFileWithParameter:(uint16_t)parameter
{
	NSLog(@"!!UNIMPLEMENTED!! should delete %@", [self fileControlBlockWithParameter:parameter]);

	// pretend we succeeded
	[_processor set8bitCPMResult:0];

	return NO;
}

- (BOOL)writeNextRecordWithParameter:(uint16_t)parameter
{
	NSLog(@"!!UNIMPLEMENTED!! should write next record to %@", [self fileControlBlockWithParameter:parameter]);

	// pretend we succeeded
	[_processor set8bitCPMResult:0];

	return NO;
}

- (BOOL)readNextRecordWithParameter:(uint16_t)parameter
{
	CPMFileControlBlock *fileControlBlock = [self fileControlBlockWithParameter:parameter];
	NSFileHandle *fileHandle = [_fileHandlesByControlBlock objectForKey:fileControlBlock];

	[fileHandle seekToFileOffset:fileControlBlock.linearFileOffset];
	NSData *nextRecord = [fileHandle readDataOfLength:128];
	if([nextRecord length])
	{
		[_memory setData:nextRecord atAddress:_dmaAddress];

		// sequential reads update the FCB
		fileControlBlock.linearFileOffset += 128;

		// report success
		[_processor set8bitCPMResult:0];
	}
	else
	{
		// set 0xff - end of file
		[_processor set8bitCPMResult:0xff];
	}

//	NSLog(@"did read sequential record for %@, offset %zd, DMA address %04x", fileControlBlock, fileControlBlock.linearFileOffset, _dmaAddress);

	return NO;
}

- (BOOL)readRandomRecordWithParameter:(uint16_t)parameter
{
	CPMFileControlBlock *fileControlBlock = [self fileControlBlockWithParameter:parameter];
	NSFileHandle *fileHandle = [_fileHandlesByControlBlock objectForKey:fileControlBlock];
	
	[fileHandle seekToFileOffset:fileControlBlock.randomFileOffset];
	NSData *nextRecord = [fileHandle readDataOfLength:128];

	if([nextRecord length])
	{
		[_memory setData:nextRecord atAddress:_dmaAddress];

		// report success
		[_processor set8bitCPMResult:0];
	}
	else
	{
		// set error 6 - record number out of range
		[_processor set8bitCPMResult:0x06];
	}

//	NSLog(@"did read random record for %@, offset %zd, DMA address %04x", fileControlBlock, fileControlBlock.randomFileOffset, _dmaAddress);

	return NO;
}

- (BOOL)directConsoleIOWithParameter:(uint16_t)parameter
{
	switch(parameter&0xff)
	{
		case 0xff:
			[_processor set8bitCPMResult:[_bios dequeueCharacterIfAvailable]];
		break;
		case 0xfe: return [self getConsoleStatus];
		default:
			[_bios writeConsoleOutput:parameter&0xff];
		break;
	}

	return NO;
}

- (BOOL)getConsoleStatus
{
	[_processor set8bitCPMResult:[_bios consoleStatus]];
	return NO;
}

- (BOOL)outputStringWithParameter:(uint16_t)parameter
{
	while(1)
	{
		uint8_t nextCharacter = [_memory valueAtAddress:parameter];
		if(nextCharacter == '$') break;
		[_bios writeConsoleOutput:nextCharacter];
		parameter++;
	}
	return NO;
}

- (void)terminalViewDidAddCharactersToBuffer:(CPMTerminalView *)terminalView
{
	[_bios terminalViewDidAddCharactersToBuffer:terminalView];
}

@end
