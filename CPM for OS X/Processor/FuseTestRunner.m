//
//  CPMFuseTestRunner.m
//  CP-Em
//
//  Created by Thomas Harte on 11/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "FuseTestRunner.h"
#import "Processor.h"
#import "RAMModule.h"

@interface NSString (hexValue)

- (uint16_t)hexValue;

@end

@implementation NSString (hexValue)

- (uint16_t)hexValue
{
	unsigned int result;
	NSScanner *scanner = [[NSScanner alloc] initWithString:self];
	[scanner scanHexInt:&result];

	return (uint16_t)result;
}

@end

@implementation CPMFuseTestRunner

- (void)go
{
	NSURL *inputURL = [[NSBundle mainBundle] URLForResource:@"tests" withExtension:@"in"];
	NSURL *expectedOutputURL = [[NSBundle mainBundle] URLForResource:@"tests" withExtension:@"expected"];

	if(!inputURL || !expectedOutputURL) return;

	NSCharacterSet *newlineSet = [NSCharacterSet newlineCharacterSet];
	NSArray *input = [[NSString stringWithContentsOfURL:inputURL encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:newlineSet];
	NSArray *expectedOutput = [[NSString stringWithContentsOfURL:expectedOutputURL encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:newlineSet];

	if(!input || !expectedOutput) return;

	CPMRAMModule *memory = [[CPMRAMModule alloc] init];
	CPMProcessor *testProcessor = [[CPMProcessor alloc] initWithRAM:memory];

	if(!memory || !testProcessor) return;

	NSEnumerator *inputEnumerator = [input objectEnumerator];
	NSEnumerator *expectedOutputEnumerator = [expectedOutput objectEnumerator];
	NSCharacterSet *whitespaceCharacterset = [NSCharacterSet whitespaceCharacterSet];
	NSPredicate *noEmptyStringPredicate = [NSPredicate predicateWithFormat:@"length != 0"];
	
	NSUInteger totalTests = 0, failedTests = 0;

	NSSet *testsToIgnore5And3 =
		[NSSet setWithArray:
			@[
				/*
					summary of these exclusions: the FUSE tests and Sean Young's document disagree on what
					happens to bits 3 and 5 in a 'bit' operations
				*/
				@"ddcb40",	@"ddcb41",	@"ddcb42",	@"ddcb43",	@"ddcb44",	@"ddcb45",	@"ddcb46",	@"ddcb47",
				@"ddcb48",	@"ddcb49",	@"ddcb4a",	@"ddcb4b",	@"ddcb4c",	@"ddcb4d",	@"ddcb4e",	@"ddcb4f",
				@"ddcb50",	@"ddcb51",	@"ddcb52",	@"ddcb53",	@"ddcb54",	@"ddcb55",	@"ddcb56",	@"ddcb57",
				@"ddcb58",	@"ddcb59",	@"ddcb5a",	@"ddcb5b",	@"ddcb5c",	@"ddcb5d",	@"ddcb5e",	@"ddcb5f",
				@"ddcb60",	@"ddcb61",	@"ddcb62",	@"ddcb63",	@"ddcb64",	@"ddcb65",	@"ddcb66",	@"ddcb67",
				@"ddcb68",	@"ddcb69",	@"ddcb6a",	@"ddcb6b",	@"ddcb6c",	@"ddcb6d",	@"ddcb6e",	@"ddcb6f",
				@"ddcb70",	@"ddcb71",	@"ddcb72",	@"ddcb73",	@"ddcb74",	@"ddcb75",	@"ddcb76",	@"ddcb77",
				@"ddcb78",	@"ddcb79",	@"ddcb7a",	@"ddcb7b",	@"ddcb7c",	@"ddcb7d",	@"ddcb7e",	@"ddcb7f",

				@"fdcb40",	@"fdcb41",	@"fdcb42",	@"fdcb43",	@"fdcb44",	@"fdcb45",	@"fdcb46",	@"fdcb47",
				@"fdcb48",	@"fdcb49",	@"fdcb4a",	@"fdcb4b",	@"fdcb4c",	@"fdcb4d",	@"fdcb4e",	@"fdcb4f",
				@"fdcb50",	@"fdcb51",	@"fdcb52",	@"fdcb53",	@"fdcb54",	@"fdcb55",	@"fdcb56",	@"fdcb57",
				@"fdcb58",	@"fdcb59",	@"fdcb5a",	@"fdcb5b",	@"fdcb5c",	@"fdcb5d",	@"fdcb5e",	@"fdcb5f",
				@"fdcb60",	@"fdcb61",	@"fdcb62",	@"fdcb63",	@"fdcb64",	@"fdcb65",	@"fdcb66",	@"fdcb67",
				@"fdcb68",	@"fdcb69",	@"fdcb6a",	@"fdcb6b",	@"fdcb6c",	@"fdcb6d",	@"fdcb6e",	@"fdcb6f",
				@"fdcb70",	@"fdcb71",	@"fdcb72",	@"fdcb73",	@"fdcb74",	@"fdcb75",	@"fdcb76",	@"fdcb77",
				@"fdcb78",	@"fdcb79",	@"fdcb7a",	@"fdcb7b",	@"fdcb7c",	@"fdcb7d",	@"fdcb7e",	@"fdcb7f",
			]];

	NSSet *testsToIgnore =
		[NSSet setWithArray:
			@[

				// these are the 'in' operations; we're not emulating the Spectrum's ports
				@"ed40",	@"ed48",	@"ed50",	@"ed58",	@"ed60",	@"ed68",	@"ed70",	@"ed78",
				
				// ini
				@"eda2",	@"eda2_01",	@"eda2_02",	@"eda2_03",
				
				// inir, otir, indr, otdr
				@"edb2",	@"edb3",	@"edba",	@"edbb",

				// ind
				@"edaa",	@"edaa_01",	@"edaa_02",	@"edaa_03",

				// outi
				@"eda3",	@"eda3_01",	@"eda3_02",	@"eda3_03",	@"eda3_04",	@"eda3_05",	@"eda3_06",	@"eda3_07",
				@"eda3_08",	@"eda3_09",	@"eda3_10",	@"eda3_11",

				// outd
				@"edab",	@"edab_01",	@"edab_02",

				// the code below doesn't currently bother to parse i or r
				@"ed57",	@"ed5f"
			]];

	while(1)
	@autoreleasepool
	{
		totalTests++;

		// read name of test
		NSString *nameOfTest = [inputEnumerator nextObject];
		NSString *mainRegisters = [inputEnumerator nextObject];
//		NSString *subsidiaryRegisters =
			[inputEnumerator nextObject];

		// set registers
		NSArray *registers = [[mainRegisters componentsSeparatedByCharactersInSet:whitespaceCharacterset] filteredArrayUsingPredicate:noEmptyStringPredicate];

		testProcessor.afRegister =		[registers[0] hexValue];
		testProcessor.bcRegister =		[registers[1] hexValue];
		testProcessor.deRegister =		[registers[2] hexValue];
		testProcessor.hlRegister =		[registers[3] hexValue];
		testProcessor.afDashRegister =	[registers[4] hexValue];
		testProcessor.bcDashRegister =	[registers[5] hexValue];
		testProcessor.deDashRegister =	[registers[6] hexValue];
		testProcessor.hlDashRegister =	[registers[7] hexValue];
		testProcessor.ixRegister =		[registers[8] hexValue];
		testProcessor.iyRegister =		[registers[9] hexValue];
		testProcessor.spRegister =		[registers[10] hexValue];
		testProcessor.programCounter =	[registers[11] hexValue];

		// ignore the other registers for now, because I don't care

		// read memory
		while(1)
		{
			NSString *nextMemoryChunk = [inputEnumerator nextObject];
			if([nextMemoryChunk isEqualToString:@"-1"]) break;

			NSArray *values = [nextMemoryChunk componentsSeparatedByCharactersInSet:whitespaceCharacterset];
			NSEnumerator *valueEnumerator = [values objectEnumerator];
			uint16_t address = [[valueEnumerator nextObject] hexValue];
			while(1)
			{
				NSString *nextByte = [valueEnumerator nextObject];
				if(!nextByte || [nextByte isEqualToString:@"-1"]) break;
				[memory setValue:(uint8_t)[nextByte hexValue] atAddress:address];
				address++;
			}
		}

		// find the next set of result registers
		uint16_t expectedAF, expectedBC, expectedDE, expectedHL;
		uint16_t expectedAFDash, expectedBCDash, expectedDEDash, expectedHLDash;
		uint16_t expectedIX, expectedIY, expectedSP, expectedPC;
		while(1)
		{
			NSArray *possibleNextResults = [[expectedOutputEnumerator nextObject] componentsSeparatedByCharactersInSet:whitespaceCharacterset];
			if([possibleNextResults count] == 12 && [[possibleNextResults componentsJoinedByString:@""] length] == 48)
			{
				expectedAF =		[possibleNextResults[0] hexValue];
				expectedBC =		[possibleNextResults[1] hexValue];
				expectedDE =		[possibleNextResults[2] hexValue];
				expectedHL =		[possibleNextResults[3] hexValue];
				expectedAFDash =	[possibleNextResults[4] hexValue];
				expectedBCDash =	[possibleNextResults[5] hexValue];
				expectedDEDash =	[possibleNextResults[6] hexValue];
				expectedHLDash =	[possibleNextResults[7] hexValue];
				expectedIX =		[possibleNextResults[8] hexValue];
				expectedIY =		[possibleNextResults[9] hexValue];
				expectedSP =		[possibleNextResults[10] hexValue];
				expectedPC =		[possibleNextResults[11] hexValue];
				break;
			}
		}

		if(![testsToIgnore containsObject:nameOfTest])
		{
//			if([nameOfTest isEqualToString:@"eda0"])
//				NSLog(@"hat");

			[testProcessor runUntilPC:expectedPC];

			if([testsToIgnore5And3 containsObject:nameOfTest])
			{
				expectedAF &= ~0x28;
				testProcessor.afRegister &= ~0x28;
			}

			if(
				(testProcessor.afRegister != expectedAF) ||
				(testProcessor.bcRegister != expectedBC) ||
				(testProcessor.deRegister != expectedDE) ||
				(testProcessor.hlRegister != expectedHL) ||
				(testProcessor.afDashRegister != expectedAFDash) ||
				(testProcessor.bcDashRegister != expectedBCDash) ||
				(testProcessor.deDashRegister != expectedDEDash) ||
				(testProcessor.hlDashRegister != expectedHLDash) ||
				(testProcessor.ixRegister != expectedIX) ||
				(testProcessor.iyRegister != expectedIY) ||
				(testProcessor.spRegister != expectedSP) ||
				(testProcessor.programCounter != expectedPC)
			)
			{
				failedTests++;
				NSLog(@"!! failed test %@ !!", nameOfTest);
				NSLog(@"AF:%04x BC:%04x DE:%04x HL:%04x AF':%04x BC':%04x DE':%04x HL':%04x IX:%04x IY:%04x SP:%04x PC:%04x; versus",
					testProcessor.afRegister, testProcessor.bcRegister, testProcessor.deRegister, testProcessor.hlRegister,
					testProcessor.afDashRegister, testProcessor.bcDashRegister, testProcessor.deDashRegister, testProcessor.hlDashRegister,
					testProcessor.ixRegister, testProcessor.iyRegister, testProcessor.spRegister, testProcessor.programCounter
				);
				NSLog(@"AF:%04x BC:%04x DE:%04x HL:%04x AF':%04x BC':%04x DE':%04x HL':%04x IX:%04x IY:%04x SP:%04x PC:%04x",
					expectedAF, expectedBC, expectedDE, expectedHL,
					expectedAFDash, expectedBCDash, expectedDEDash, expectedHLDash,
					expectedIX, expectedIY, expectedSP, expectedPC
				);
				NSLog(@"====================");
			}
		}

		// skip separator
		if(![inputEnumerator nextObject]) break;
	}

	NSLog(@"==all tests complete==");
	NSLog(@"Failed %lu of %lu (%0.2f %%)", failedTests, totalTests, ((float)failedTests * 100.0f) / totalTests);
}

@end
