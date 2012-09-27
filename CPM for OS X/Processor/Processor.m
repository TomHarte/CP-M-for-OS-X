//
//  CPMProcessor.m
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "Processor.h"
#import "RAMModule.h"

#define rTableIndexB	0
#define rTableIndexC	1
#define rTableIndexD	2
#define rTableIndexE	3
#define rTableIndexH	4
#define rTableIndexL	5
//#define rTableIndexA	7

#define LLZ80FlagCarry				0x01
#define LLZ80FlagSubtraction		0x02
#define LLZ80FlagParityOverflow		0x04
#define LLZ80FlagBit3				0x08
#define LLZ80FlagHalfCarry			0x10
#define LLZ80FlagBit5				0x20
#define LLZ80FlagZero				0x40
#define LLZ80FlagSign				0x80

@implementation CPMProcessor
{
	BOOL addOffset;

	BOOL isBlocked;

	uint16_t *indexRegister;

	uint16_t bcRegister, deRegister, hlRegister;
	uint16_t afDashRegister, bcDashRegister, deDashRegister, hlDashRegister;
	uint16_t ixRegister, iyRegister, spRegister;
	uint16_t programCounter;
	uint8_t iRegister, rRegister, aRegister;

	uint8_t lastSignResult, lastZeroResult, bit5And3Flags, generalFlags;

	CPMRAMModule *memory;
}

/*

	Standard lifecycle stuff

*/

+ (id)processorWithRAM:(CPMRAMModule *)RAM
{
	return [[[self alloc] initWithRAM:RAM] autorelease];
}

- (id)initWithRAM:(CPMRAMModule *)RAM
{
	self = [super init];

	if(self)
	{
		memory = [RAM retain];
		indexRegister = &hlRegister;
		addOffset = NO;
	}

	return self;
}

- (void)dealloc
{
	[memory release], memory = nil;
	[super dealloc];
}


/*

	These are a couple of helpers for reading a value from the PC,
	incrementing it as we go

*/
#define readByteFromPC() [memory valueAtAddress:programCounter++]
//- (uint8_t)readByteFromPC
//{
//	return [memory valueAtAddress:programCounter++];
//}

- (uint16_t)readShortFromPC
{
	uint16_t returnValue = readByteFromPC();
	returnValue |= ((uint16_t)readByteFromPC()) << 8;
	return returnValue;
}

/*

	From the primitive methods above the few below are
	derived; they're used to get the full write address

*/
- (uint16_t)getOffset
{
	return (int8_t)readByteFromPC() + programCounter;
}

- (uint16_t)getAddress
{
	return [self readShortFromPC];
}

- (uint8_t *)indexPlusOffset:(int8_t)offset
{
	return [memory pointerToAddress:*indexRegister + offset];
}

/*

	These return a canned result

*/
- (uint8_t)parity:(uint8_t)input
{
	uint8_t parity = input^1;
	parity ^= parity >> 4;
	parity ^= parity << 2;
	parity ^= parity >> 1;
	return parity & LLZ80FlagParityOverflow;
}

- (BOOL)condition:(int)index
{
	switch(index)
	{
		default: return NO;
		
		case 0: return lastZeroResult;							//NZ
		case 1: return !lastZeroResult;							//Z
		case 2: return !(generalFlags&LLZ80FlagCarry);			//NC
		case 3: return (generalFlags&LLZ80FlagCarry);			//C
		case 4: return !(generalFlags&LLZ80FlagParityOverflow);	//PO
		case 5: return (generalFlags&LLZ80FlagParityOverflow);	//PE
		case 6: return !(lastSignResult&0x80);					//P
		case 7: return lastSignResult&0x80;						//M
	}
}

/*
*/
- (uint16_t *)rpTable:(int)index
{
	uint16_t *rpTable[] = {&bcRegister, &deRegister, nil, &spRegister};
	return rpTable[index] ? rpTable[index] : indexRegister;
}

- (uint16_t *)rp2Table:(int)index
{
	switch(index)
	{
		case 0: return &bcRegister;
		case 1: return &deRegister;
		case 2: return indexRegister;
		default: return nil;
	}
}

#if TARGET_RT_BIG_ENDIAN == 1
#define kOffsetToHighByte 0
#define kOffsetToLowByte 1
#else
#define kOffsetToHighByte 1
#define kOffsetToLowByte 0
#endif

- (uint8_t *)rTable:(int)index
{
	switch(index)
	{
		case 0:	return (uint8_t *)&bcRegister + kOffsetToHighByte;
		case 1:	return (uint8_t *)&bcRegister + kOffsetToLowByte;
		case 2:	return (uint8_t *)&deRegister + kOffsetToHighByte;
		case 3:	return (uint8_t *)&deRegister + kOffsetToLowByte;
		case 4:	return (uint8_t *)indexRegister + kOffsetToHighByte;
		case 5:	return (uint8_t *)indexRegister + kOffsetToLowByte;

		case 6:
			if(addOffset)
			{
				uint16_t address = *indexRegister;
				address += (int8_t)readByteFromPC();
				return [memory pointerToAddress:address];
			}
			else
				return [memory pointerToAddress:hlRegister];
		break;

		case 7:	return (uint8_t *)&aRegister;
	}

	return NULL;
}

- (uint8_t *)hlrTable:(int)index
{
	uint16_t *realIndexRegister = indexRegister;
	indexRegister = &hlRegister;
	uint8_t *result = [self rTable:index];
	indexRegister = realIndexRegister;
	return result;
}

- (void)inc:(uint8_t *)value
{
	int result = (*value) + 1;

	// with an increment, overflow occurs if the sign changes from
	// positive to negative
	int overflow = (*value ^ result) & ~(*value);
	int halfResult = (*value&0xf) + 1;

	*value = (uint8_t)result;

	// sign, zero and 5 & 3 are set directly from the result
	bit5And3Flags = lastSignResult = lastZeroResult = (uint8_t)result;
	generalFlags =
		(generalFlags & LLZ80FlagCarry) |		// carry isn't affected
		(halfResult&LLZ80FlagHalfCarry) |			// half carry
		((overflow >> 5)&LLZ80FlagParityOverflow);	// overflow
													// implicitly: subtraction is reset
}

- (void)dec:(uint8_t *)value
{
	int result = (*value) - 1;

	// with a decrement, overflow occurs if the sign changes from
	// negative to positive
	int overflow = (*value ^ result) & (*value);
	int halfResult = (*value&0xf) - 1;

	*value = (uint8_t)result;

	// sign, zero and 5 & 3 are set directly from the result
	bit5And3Flags = lastZeroResult = lastSignResult = (uint8_t)result;
	generalFlags =
		(generalFlags & LLZ80FlagCarry) |		// carry isn't affected
		(halfResult&LLZ80FlagHalfCarry) |			// half carry
		((overflow >> 5)&LLZ80FlagParityOverflow) |	// overflow
		LLZ80FlagSubtraction;						// subtraction is set
}


- (void)aluOp:(int)operation value:(uint8_t)value
{
	switch(operation)
	{
		default: break;

		case 0:	// add a, ...
		{
			int result = aRegister + value;
			int halfResult = (aRegister&0xf) + (value&0xf);

			// overflow for addition is when the signs were originally
			// the same and the result is different
			int overflow = ~(value^aRegister) & (result^aRegister);

			aRegister = (uint8_t)result;

			lastSignResult = lastZeroResult =
			bit5And3Flags = (uint8_t)result;				// set sign, zero and 5 and 3
			generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5);						// overflow flag
															// subtraction is implicitly unset
		}
		break;
		
		case 1: // adc a, ...
		{
			int result = aRegister + value + (generalFlags&LLZ80FlagCarry);
			int halfResult = (aRegister&0xf) + (value&0xf) + (generalFlags&LLZ80FlagCarry);

			// overflow for addition is when the signs were originally
			// the same and the result is different
			int overflow = ~(value^aRegister) & (result^aRegister);

			aRegister = (uint8_t)result;

			lastSignResult = lastZeroResult =
			bit5And3Flags = (uint8_t)result;			// set sign, zero and 5 and 3
			generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5);						// overflow flag
															// subtraction is implicitly unset
		}
		break;
		
		case 2:	// sub ...
		{
			int result = aRegister - value;
			int halfResult = (aRegister&0xf) - (value&0xf);

			// overflow for a subtraction is when the signs were originally
			// different and the result is different again
			int overflow = (value^aRegister) & (result^aRegister);

			aRegister = (uint8_t)result;

			lastSignResult = lastZeroResult =
			bit5And3Flags = (uint8_t)result;			// set sign, zero and 5 and 3
			generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5)				|		// overflow flag
				LLZ80FlagSubtraction;						// and this counts as a subtraction
		}
		break;
		
		case 3:	// SBC A, ...
		{
			int result = aRegister - value - (generalFlags&LLZ80FlagCarry);
			int halfResult = (aRegister&0xf) - (value&0xf) - (generalFlags&LLZ80FlagCarry);;

			// overflow for a subtraction is when the signs were originally
			// different and the result is different again
			int overflow = (value^aRegister) & (result^aRegister);

			aRegister = (uint8_t)result;

			lastSignResult = lastZeroResult =
			bit5And3Flags = (uint8_t)result;			// set sign, zero and 5 and 3
			generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5)				|		// overflow flag
				LLZ80FlagSubtraction;						// and this counts as a subtraction
		}
		break;
		
		case 4:	// AND ...
		{
			aRegister &= value;

			lastSignResult = lastZeroResult =
			bit5And3Flags = aRegister;

			generalFlags =
				LLZ80FlagHalfCarry |
				[self parity:aRegister];
		}
		break;

		case 5:	// XOR ...
		{
			aRegister ^= value;

			lastSignResult = lastZeroResult =
			bit5And3Flags = aRegister;

			generalFlags = [self parity:aRegister];
		}
		break;

		case 6:	// OR ...
		{
			aRegister |= value;

			lastSignResult = lastZeroResult =
			bit5And3Flags = aRegister;

			generalFlags = [self parity:aRegister];
		}
		break;

		case 7:	// CP ...
		{
			int result = aRegister - value;
			int halfResult = (aRegister&0xf) - (value&0xf);

			// overflow for a subtraction is when the signs were originally
			// different and the result is different again
			int overflow = (value^aRegister) & (result^aRegister);

			lastSignResult =			// set sign and zero
			lastZeroResult = (uint8_t)result;
			bit5And3Flags = value;		// set the 5 and 3 flags, which come
											// from the operand atypically
			generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5)				|		// overflow flag
				LLZ80FlagSubtraction;						// and this counts as a subtraction
		}
		break;
	}
}

- (void)push:(uint16_t)value
{
	spRegister--;
	[memory setValue:value >> 8 atAddress:spRegister];
	spRegister--;
	[memory setValue:value & 0xff atAddress:spRegister];
}

- (uint16_t)pop
{
	uint16_t value = [memory valueAtAddress:spRegister];
	spRegister++;
	value |= [memory valueAtAddress:spRegister] << 8;
	spRegister++;

	return value;
}

- (void)call:(uint16_t)address
{
	[self push:programCounter];
	programCounter = address;
}

- (void)sbc16:(uint16_t)operand
{
	int result = hlRegister - operand - (generalFlags&LLZ80FlagCarry);
	int halfResult = (hlRegister&0xfff) - (operand&0xfff) - (generalFlags&LLZ80FlagCarry);

	// subtraction, so parity rules are:
	// signs of operands were different, 
	// sign of result is different
	int overflow = (result ^ hlRegister) & (operand ^ hlRegister);

	hlRegister = (uint16_t)result;

	bit5And3Flags = lastSignResult = (uint8_t)(result >> 8);
	lastZeroResult	= (uint8_t)(result | lastSignResult);
	generalFlags =
		LLZ80FlagSubtraction					|
		((result >> 16)&LLZ80FlagCarry)			|
		((halfResult >> 8)&LLZ80FlagHalfCarry)	|
		((overflow&0x8000) >> 13);
}

- (void)adc16:(uint16_t)operand
{
	int result = hlRegister + operand + (generalFlags&LLZ80FlagCarry);
	int halfResult = (hlRegister&0xfff) + (operand&0xfff) + (generalFlags&LLZ80FlagCarry);

	int overflow = (result ^ hlRegister) & ~(operand ^ hlRegister);

	bit5And3Flags = lastSignResult = (uint8_t)(result >> 8);
	lastZeroResult	= (uint8_t)(result | lastSignResult);
	generalFlags =
		((result >> 16)&LLZ80FlagCarry)			|
		((halfResult >> 8)&LLZ80FlagHalfCarry) |
		((overflow&0x8000) >> 13);	// implicitly, subtract isn't set

	hlRegister = (uint16_t)result;
}

- (void)add16:(uint16_t *)target operand:(uint16_t)operand
{
	int result = *target + operand;
	int halfResult = (*target&0xfff) + (operand&0xfff);

	bit5And3Flags = (uint8_t)(result >> 8);
	generalFlags =
		(generalFlags&LLZ80FlagParityOverflow)	|
		((result >> 16)&LLZ80FlagCarry)			|
		((halfResult >> 8)&LLZ80FlagHalfCarry);	// implicitly, subtract isn't set

	*target = (uint16_t)result;
}

- (void)blockInstruction:(int)instruction repeatType:(int)repeatType
{
	uint8_t lastResult = 0xff, halfResult = 0, flagResult = 0;
	while(1)
	{
		switch(instruction)
		{
			case 0:	// ld
			{
				uint8_t value = [memory valueAtAddress:hlRegister];
				[memory setValue:value atAddress:deRegister];

				flagResult = aRegister + value;
//				halfResult = (aRegister&0xf) + (RAM[hlRegister]&0xf);
			}
			break;
			case 1: // cp
			{
				uint8_t value = [memory valueAtAddress:hlRegister];

				flagResult = lastResult = aRegister - value;
				halfResult = (aRegister&0xf) - (value&0xf);
			}
			break;

			case 2:	// in
				// we'll assume we just read 0xff
			case 3: // out
			break;
		}

		if(instruction < 2)
			bcRegister--;
		else
			bcRegister-= 0x100;

		switch(repeatType)
		{
			case 0: // i
			case 2: // ir
				hlRegister++;
				if(!instruction) deRegister++;
			break;
			case 1: // d
			case 3: // dr
				hlRegister--;
				if(!instruction) deRegister--;
			break;
		}

		if(repeatType < 2) break;
		if(!(bcRegister >> ((instruction < 2) ? 0 : 8)) || !lastResult) break;
	}

	generalFlags =
		(generalFlags&LLZ80FlagCarry) |
		(bcRegister ? LLZ80FlagParityOverflow : 0) |
		(halfResult & LLZ80FlagHalfCarry);
	if(instruction == 1)
	{
		generalFlags |= LLZ80FlagSubtraction;
		lastSignResult = lastZeroResult = flagResult;
	}

	bit5And3Flags = (uint8_t)((flagResult&0x8) | ((flagResult&0x2) << 4));
}

- (uint8_t)set:(int)bit source:(uint8_t *)source
{
	*source |= 1 << bit;
	return *source;
}

- (uint8_t)res:(int)bit source:(uint8_t *)source
{
	*source &= ~(1 << bit);
	return *source;
}

- (void)bit:(int)bit source:(uint8_t *)source
{
	uint8_t result = *source & (1 << bit);

	lastSignResult = lastZeroResult = result;
	bit5And3Flags = *source;
	generalFlags =
		(generalFlags & LLZ80FlagCarry) |
		LLZ80FlagHalfCarry |
		(result ? 0 : LLZ80FlagParityOverflow);
}

- (uint8_t)rotationOperation:(int)operation source:(uint8_t *)source
{
	uint8_t carry;

	switch(operation)
	{
		default:
		case 0:	// RLC
		{
			carry = *source >> 7;
			*source = (uint8_t)((*source << 1) | carry);
		}
		break;
		case 1: // RRC
		{
			carry = *source & 1;
			*source = (uint8_t)((*source >> 1) | (carry << 7));
		}
		break;
		case 2: // RL
		{
			carry = *source >> 7;
			*source = (uint8_t)((*source << 1) | (generalFlags&LLZ80FlagCarry));
		}
		break;
		case 3: // RR
		{
			carry = *source & 1;
			*source = (uint8_t)((*source >> 1) | (generalFlags << 7));
		}
		break;
		case 4: // SLA
		{
			carry = *source >> 7;
			*source <<= 1;
		}
		break;
		case 5: // SRA
		{
			carry = *source & 1;
			*source = (*source & 0x80) | (*source >> 1);
		}
		break;
		case 6:	// SLL
		{
			carry = *source >> 7;
			*source = (uint8_t)((*source << 1) | 1);
		}
		break;
		case 7: // SRL
		{
			carry = *source & 1;
			*source >>= 1;
		}
		break;
	}

	generalFlags = carry | [self parity:*source];
	bit5And3Flags = lastSignResult = lastZeroResult = *source;

	return *source;
}

- (void)executeFromEDPage
{
	uint8_t opcode = readByteFromPC();
	int x = opcode >> 6;
	int y = (opcode >> 3)&7;
	int z = opcode&7;

	switch(x)
	{
		case 0:
		case 3:	break;	// NOP
		case 2:
			if(y >= 4) [self blockInstruction:z repeatType:y-4];
		break;
		case 1:
			switch(z)
			{
				case 0:
					if(y == 6)
					{
						// in a, (c); no effect on f
						aRegister = 0xff;
					}
					else
					{
						// in r, (c); sets f
						*[self rTable:y] = 0xff;
						bit5And3Flags = 0xa4;
//						fRegister = (fRegister&0x01) | 0xa4;
					}
				break;
				case 1:
					if(y == 6)
					{
						// out (c), a
					}
					else
					{
						// out (c), r
					}
				break;
				case 2:
					if(y&1)
					{
						// ADC HL, rr
						[self adc16:*[self rpTable:y >> 1]];
					}
					else
					{
						// SBC HL, rr
						[self sbc16:*[self rpTable:y >> 1]];
					}
				break;
				case 3:
					if(y&1)
					{
						uint16_t address = [self getAddress];
						uint16_t *target = [self rpTable:y >> 1];

						*target = [memory valueAtAddress:address];
						address++;
						*target |= (uint16_t)[memory valueAtAddress:address] << 8;
						//LD rr, (nnnn)
					}
					else
					{
						uint16_t address = [self getAddress];
						uint16_t *target = [self rpTable:y >> 1];

						[memory setValue:(*target)&0xff atAddress:address];
						address++;
						[memory setValue:*target >> 8 atAddress:address];
						//LD (nnnn), rr
					}
				break;
				case 4: // NEG
				{
					// -128 is the only thing that'll overflow
					// when negated
					int overflow = (aRegister == 0x80);
					int result = 0 - aRegister;
					int halfResult = 0 - (aRegister&0xf);

					aRegister = (uint8_t)result;
					bit5And3Flags = lastSignResult = lastZeroResult = aRegister;
					generalFlags =
						(overflow ? LLZ80FlagParityOverflow : 0) |
						LLZ80FlagSubtraction |
						((result >> 8)&LLZ80FlagCarry) |
						(halfResult&LLZ80FlagHalfCarry);
				}
				break;
				case 5:
					if(y == 1)
					{
						// retn
						programCounter = [self pop];
					}
					else
					{
						// reti
						programCounter = [self pop];
					}
				break;
				case 6:
					// IM 0, 1 or 0/1; we don't really care
				break;
				case 7:
					switch(y)
					{
						case 0:	iRegister = aRegister;	break;
						case 1: rRegister = aRegister;	break;
						case 2:	// LD a, i
						{
							aRegister = iRegister;
							lastZeroResult = lastSignResult = bit5And3Flags = iRegister;
							generalFlags &= LLZ80FlagCarry;
						}
						break;
						case 3: // ld a, r
						{
							aRegister = rRegister;
							lastZeroResult = lastSignResult = bit5And3Flags = rRegister;
							generalFlags &= LLZ80FlagCarry;
						}
						break;
						case 4:	// RRD
						{
							uint8_t temporaryValue = [memory valueAtAddress:hlRegister];

							int lowNibble = aRegister&0xf;
							aRegister = (aRegister&0xf0) | (temporaryValue & 0xf);
							temporaryValue = (uint8_t)((temporaryValue >> 4) | (lowNibble << 4));

							generalFlags =
								[self parity:aRegister] |
								(generalFlags&LLZ80FlagCarry);
							lastSignResult = lastZeroResult =
							bit5And3Flags = aRegister;

							[memory setValue:temporaryValue atAddress:hlRegister];
						}
						break;
						case 5: // RLD
						{
							uint8_t temporaryValue = [memory valueAtAddress:hlRegister];

							int lowNibble = aRegister&0xf;
							aRegister = (aRegister&0xf0) | (temporaryValue >> 4);
							temporaryValue = (uint8_t)((temporaryValue << 4) | lowNibble);

							generalFlags =
								[self parity:aRegister] |
								(generalFlags&LLZ80FlagCarry);
							lastSignResult = lastZeroResult =
							bit5And3Flags = aRegister;

							[memory setValue:temporaryValue atAddress:hlRegister];
						}
						break;
						case 6:
						case 7:	// NOP
							break;
					}
				break;
			}
		break;
	}
}

- (void)executeFromCBPage
{
	int8_t displacement = 0;
	if(addOffset) displacement = (int8_t)readByteFromPC();
	uint8_t opcode = readByteFromPC();
	int x = opcode >> 6;
	int y = (opcode >> 3)&7;
	int z = opcode&7;

	if(addOffset)
	{
		switch(x)
		{
			case 0:
				if(z == 6)
				{
					[self rotationOperation:y source:[self indexPlusOffset:displacement]];
				}
				else
				{
					*[self hlrTable:z] = [self rotationOperation:y source:[self indexPlusOffset:displacement]];
				}
			break;
			case 1:
					[self bit:y source:[self indexPlusOffset:displacement]];
			break;
			case 2:
				if(z == 6)
				{
					[self res:y source:[self indexPlusOffset:displacement]];
				}
				else
				{
					*[self hlrTable:z] = [self res:y source:[self indexPlusOffset:displacement]];
				}
			break;
			case 3:
				if(z == 6)
				{
					[self set:y source:[self indexPlusOffset:displacement]];
				}
				else
				{
					*[self hlrTable:z] = [self set:y source:[self indexPlusOffset:displacement]];
				}
			break;
		}
	}
	else
	{
		uint8_t *source = [self rTable:z];
		switch(x)
		{
			case 0: [self rotationOperation:y source:[self rTable:z]];		break;
			case 1:	[self bit:y source:source];								break;
			case 2: [self res:y source:source];								break;
			case 3: [self set:y source:source];								break;
		}
	}
}

- (void)executeFromStandardPage
{
//	static BOOL isLogging = NO;
//	if(programCounter == 29292) isLogging = YES;
//	if(isLogging)
//		printf("%04x AF:%04x BC:%04x DE:%04x HL:%04x SP:%04x [%02x %02x %02x %02x]\n", programCounter, self.afRegister, bcRegister, deRegister, hlRegister, spRegister, [memory valueAtAddress:programCounter], [memory valueAtAddress:programCounter+1], [memory valueAtAddress:programCounter+2], [memory valueAtAddress:programCounter+3]);

	rRegister = (rRegister+1)&127;	// for the sake of incrementing this somewhere; we don't really care for accuracy
	uint8_t opcode = readByteFromPC();
	int x = opcode >> 6;
	int y = (opcode >> 3)&7;
	int z = opcode&7;

	switch(x)
	{
		case 0:
			switch(z)
			{
				case 0:
					switch(y)
					{
						case 0:
							// NOP
						break;
						case 1:
						{
							// EX AF, AF'
							uint16_t temp = self.afRegister;
							self.afRegister = afDashRegister;
							afDashRegister = temp;
						}
						break;
						case 2:	// DJNZ
						{
							uint16_t address = [self getOffset];
							uint8_t *bRegister = [self rTable:rTableIndexB];

							(*bRegister)--;

							if(*bRegister)
							{
								programCounter = address;
							}
						}
						break;
						case 3:
						{
							programCounter = [self getOffset];
							// jr nn
						}
						break;
						default:
						{
							// JR cc, nn
							uint16_t address = [self getOffset];
							if([self condition:y-4])
								programCounter = address;
						}
						break;
					}
				break;
				case 1:
					if(y&1)
					{
						[self add16:indexRegister operand:*[self rpTable:y >> 1]];
						// add hl, rr
					}
					else
					{
						*[self rpTable: y >> 1] = [self readShortFromPC];
						// LD rr, nnnn
					}
				break;
				case 2:
					switch(y)
					{
						case 0:	// LD (BC), A
							[memory setValue:aRegister atAddress:bcRegister];
						break;
						case 1:	// LD A, (BC)
							aRegister = [memory valueAtAddress:bcRegister];
						break;
						case 2: // LD (DE), A
							[memory setValue:aRegister atAddress:deRegister];
						break;
						case 3: // LD A, (DE)
							aRegister = [memory valueAtAddress:deRegister];
						break;
						case 4:
						{
							uint16_t address = [self getAddress];
							[memory setValue:*[self rTable:rTableIndexL] atAddress:address];
							address++;
							[memory setValue:*[self rTable:rTableIndexH] atAddress:address];
							// LD (nnnn), HL
						}
						break;
						case 5:
						{
							uint16_t address = [self getAddress];
							*[self rTable:rTableIndexL] = [memory valueAtAddress:address];
							address++;
							*[self rTable:rTableIndexH] = [memory valueAtAddress:address];
							//LD HL, (nnnn)
						}
						break;
						case 6:
							[memory setValue:aRegister atAddress:[self getAddress]];
							// LD (nnnn), a
						break;
						case 7:
							aRegister = [memory valueAtAddress:[self getAddress]];
							// LD a, (nnnn)
						break;
					}
				break;
				case 3:
					if(y&1)
					{
						(*[self rpTable:y >> 1]) --;
						// dec (rr)
					}
					else
					{
						(*[self rpTable:y >> 1]) ++;
						// inc (rr)
					}
				break;
				case 4:
					[self inc:[self rTable:y]];
					// inc r
				break;
				case 5:
					[self dec:[self rTable:y]];
					// dec r
				break;
				case 6:
				{
					// note: we could currently be in indexed addressing mode, in which case both
					// [self rTable:y] and readByteFromPC() read from the PC. It's therefore invalid
					// to combine the two lines below into a single.
					uint8_t *address = [self rTable:y];
					*address = readByteFromPC();
					// LD r, nn
				}
				break;
				case 7:
				{
					switch(y)
					{
						case 0:	// RLCA
						{
							uint8_t newCarry = aRegister >> 7;
							aRegister = (uint8_t)((aRegister << 1) | newCarry);
							bit5And3Flags = aRegister;
							generalFlags =
								(generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 1: // RRCA
						{
							uint8_t newCarry = aRegister & 1;
							aRegister = (uint8_t)((aRegister >> 1) | (newCarry << 7));
							bit5And3Flags = aRegister;
							generalFlags =
								(generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 2: // RLA
						{
							uint8_t newCarry = aRegister >> 7;
							aRegister = (uint8_t)((aRegister << 1) | (generalFlags&LLZ80FlagCarry));
							bit5And3Flags = aRegister;
							generalFlags =
								(generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 3:	// RRA
						{
							uint8_t newCarry = aRegister & 1;
							aRegister = (uint8_t)((aRegister >> 1) | ((generalFlags&LLZ80FlagCarry) << 7));
							bit5And3Flags = aRegister;
							generalFlags =
								(generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 4: // DAA
						{
							int lowNibble = aRegister & 0xf;
							int highNibble = aRegister >> 4;

							int amountToAdd = 0;

							if(generalFlags & LLZ80FlagCarry)
							{
								if(lowNibble > 0x9 || generalFlags&LLZ80FlagHalfCarry)
									amountToAdd = 0x66;
								else
									amountToAdd = 0x60;
							}
							else
							{
								if(generalFlags & LLZ80FlagHalfCarry)
								{
									amountToAdd = (highNibble > 0x9) ? 0x66 : 0x60;
								}
								else
								{
									if(lowNibble > 0x9)
									{
										if(highNibble > 0x8)
											amountToAdd = 0x66;
										else
											amountToAdd = 0x6;
									}
									else
									{
										amountToAdd = (highNibble > 0x9) ? 0x60 : 0x00;
									}
								}
							}

							int newCarry = generalFlags & LLZ80FlagHalfCarry;
							if(!newCarry)
							{
								if(lowNibble > 0x9)
								{
									if(highNibble > 0x8) newCarry = LLZ80FlagCarry;
								}
								else
								{
									if(highNibble > 0x9) newCarry = LLZ80FlagCarry;
								}
							}

							int newHalfCarry = 0;
							if(generalFlags&LLZ80FlagSubtraction)
							{
								(aRegister) -= amountToAdd;
								if(generalFlags&LLZ80FlagHalfCarry)
								{
									newHalfCarry = (lowNibble < 0x6) ? LLZ80FlagHalfCarry : 0;
								}
							}
							else
							{
								(aRegister) += amountToAdd;
								newHalfCarry = (lowNibble > 0x9) ? LLZ80FlagHalfCarry : 0;
							}

							lastSignResult = lastZeroResult =
							bit5And3Flags = aRegister;
							
							uint8_t parity = aRegister;
							parity ^= (parity >> 4);
							parity ^= (parity >> 2);
							parity ^= (parity >> 1);

							generalFlags =
								(uint8_t)(
									newCarry |
									newHalfCarry |
									((parity&1) << 3) |
									(generalFlags&LLZ80FlagSubtraction));
						}
						break;
						case 5:	// CPL
						{
							aRegister ^= 0xff;
							generalFlags |=
								LLZ80FlagHalfCarry |
								LLZ80FlagSubtraction;
							bit5And3Flags = aRegister;
						}
						break;
						case 6:	// SCF
						{
							bit5And3Flags = aRegister;
							generalFlags =
								(generalFlags & LLZ80FlagParityOverflow) |
								LLZ80FlagCarry;
						}
						break;
						case 7:	// CCF
						{
							bit5And3Flags = aRegister;
							generalFlags =
								(uint8_t)(
									(generalFlags & LLZ80FlagParityOverflow) |
									((generalFlags & LLZ80FlagCarry) << 4) |	// so half carry is what carry was
									((generalFlags&LLZ80FlagCarry)^LLZ80FlagCarry));
						}
						break;
					}
				}
				break;
			}
		break;
		case 1:
		{
			if((z == 6) && (y == 6))
			{
				NSLog(@"HALT");
				[self.delegate processorDidHalt:self];
				isBlocked = YES;
			}
			else
			{
				uint8_t *dest = (z == 6) ? [self hlrTable:y] : [self rTable:y];
				uint8_t *source = (y == 6) ? [self hlrTable:z] : [self rTable:z];

				*dest = *source;
				// LD r, r
			}
		}
		break;
		case 2:
			[self aluOp:y value:*[self rTable:z]];
			// alu[y] r
		break;
		case 3:
			switch(z)
			{
				case 0:
					if([self condition:y])
						programCounter = [self pop];
					// ret cc
				break;
				case 1:
					if(y&1)
					{
						switch(y >> 1)
						{
							case 0:	// ret
								programCounter = [self pop];
							break;
							case 1:	// exx
							{
								uint16_t temporaryStore;

								temporaryStore = bcRegister;
								bcRegister = bcDashRegister;
								bcDashRegister = temporaryStore;

								temporaryStore = deRegister;
								deRegister = deDashRegister;
								deDashRegister = temporaryStore;

								temporaryStore = hlRegister;
								hlRegister = hlDashRegister;
								hlDashRegister = temporaryStore;
							}
							break;
							case 2:	// JP indexRegister
								programCounter = *indexRegister;
							break;
							case 3: // LD SP, indexRegister
								spRegister = *indexRegister;
							break;
						}
					}
					else
					{
						uint16_t *address = [self rp2Table:y >> 1];
						
						if(address)
							*address = [self pop];
						else
						{
							uint16_t newAF = [self pop];
							self.afRegister = newAF;
						}
						// pop rr
					}
				break;
				case 2:
				{
					uint16_t address = [self getAddress];
					if([self condition:y])
						programCounter = address;
					// JP cc, nnnn
				}
				break;
				case 3:
					switch(y)
					{
						case 0: // JP nnnn
							programCounter = [self getAddress];
						break;
						case 1: [self executeFromCBPage];							break;
						case 2: NSLog(@"OUT ($%02x), A", readByteFromPC());			break;
						case 3: NSLog(@"IN A, ($%02x)", readByteFromPC());			break;
						case 4:
						{
							uint16_t temporaryValue = [self pop];
							[self push:*indexRegister];
							*indexRegister = temporaryValue;
							// ex (sp), hl
						}
						break;
						case 5:
						{
							// EX DE, HL
							uint16_t temporaryValue = deRegister;
							deRegister = hlRegister;
							hlRegister = temporaryValue;
						}
						break;
						case 6: break;//NSLog(@"DI");												break;
						case 7: break;//NSLog(@"EI");												break;
					}
				break;
				case 4:
				{
					uint16_t address = [self getAddress];
					if([self condition:y])
						[self call:address];
					// CALL cc, nnnn
				}
				break;
				case 5:
					if(y&1)
					{
						switch(y >> 1)
						{
							case 0:
							{
								[self call:[self getAddress]];
								// CALL nnnn
							}
							break;
							case 1:
								indexRegister = &ixRegister;
								addOffset = YES;
								[self executeFromStandardPage];
								indexRegister = &hlRegister;
								addOffset = NO;
							break;
							case 2: [self executeFromEDPage];				break;
							case 3:
								indexRegister = &iyRegister;
								addOffset = YES;
								[self executeFromStandardPage];
								indexRegister = &hlRegister;
								addOffset = NO;
							break;
						}
					}
					else
					{
						uint16_t *address = [self rp2Table:y >> 1];
						if(address)
							[self push:*address];
						else
							[self push:self.afRegister];
						// push rr
					}
				break;
				case 6:
					[self aluOp:y value:readByteFromPC()];
					// alu[y] nn
				break;
				case 7:
					[self call:y << 3];
					// RST n
				break;
			}
		break;
	}
}

- (void)runUntilPC:(uint16_t)targetPC
{
	int maxInstructionCount = 1000;
	while(programCounter != targetPC && maxInstructionCount--)
	{
		[self executeFromStandardPage];
	}
}

- (void)runForTimeInterval:(NSTimeInterval)timeInterval
{
	NSTimeInterval timeAtStart = [NSDate timeIntervalSinceReferenceDate];

	while(!isBlocked && [NSDate timeIntervalSinceReferenceDate] - timeAtStart < timeInterval)
	{
		[self runForNumberOfInstructions:1000];
	}
}

- (void)runForNumberOfInstructions:(NSUInteger)numberOfInstructions
{
	// we're going to call this thing millions of times a second, probably, so caching the IMP
	// is a pragmatic performance optimisation
	IMP executeFromStandardPage = [self methodForSelector:@selector(executeFromStandardPage)];

	while(!isBlocked && numberOfInstructions--)
	{
		if(programCounter >= _biosAddress)
		{
			isBlocked = [self.delegate processor:self isMakingBIOSCall:(programCounter - _biosAddress) / 3];
			programCounter = [self pop];
		}
		else
		{			
			executeFromStandardPage(self, @selector(executeFromStandardPage));
		}
	}
}

- (void)unblock
{
	isBlocked = NO;
}

@synthesize isBlocked;

- (void)setAfRegister:(uint16_t)afRegister
{
	lastSignResult = afRegister & LLZ80FlagSign;
	lastZeroResult = (afRegister & LLZ80FlagZero)^LLZ80FlagZero;
	bit5And3Flags = afRegister & (LLZ80FlagBit5 | LLZ80FlagBit3);
	generalFlags = afRegister & (LLZ80FlagCarry | LLZ80FlagHalfCarry | LLZ80FlagParityOverflow | LLZ80FlagSubtraction);

	aRegister = afRegister >> 8;
}

- (uint16_t)afRegister
{
	uint8_t fRegister =
		(lastSignResult&LLZ80FlagSign) |
		(lastZeroResult ? 0 : LLZ80FlagZero) |
		(bit5And3Flags & (LLZ80FlagBit5 | LLZ80FlagBit3)) |
		(generalFlags & (LLZ80FlagCarry | LLZ80FlagHalfCarry | LLZ80FlagParityOverflow | LLZ80FlagSubtraction));

	return (aRegister << 8) | fRegister;
}

@synthesize bcRegister;
@synthesize deRegister;
@synthesize hlRegister;
@synthesize afDashRegister;
@synthesize bcDashRegister;
@synthesize deDashRegister;
@synthesize hlDashRegister;
@synthesize ixRegister;
@synthesize iyRegister;
@synthesize spRegister;
@synthesize programCounter;
@synthesize iRegister, rRegister;

@end
