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
	BOOL _shouldAddOffset;

	uint16_t *_indexRegister;
	uint8_t _aRegister;
	uint8_t _lastSignResult, _lastZeroResult, _bit5And3Flags, _generalFlags;

	CPMRAMModule *_memory;
}

/*

	Standard lifecycle stuff

*/

- (id)initWithRAM:(CPMRAMModule *)RAM
{
	self = [super init];

	if(self)
	{
		_memory = RAM;
		_indexRegister = &_hlRegister;
		_shouldAddOffset = NO;
	}

	return self;
}

#pragma mark -
#pragma mark Read/Write/Offset Helpers

/*

	These are a couple of helpers for reading a value from the PC,
	incrementing it as we go

*/
#define readByteFromPC() [_memory valueAtAddress:_programCounter++]

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
	return (uint16_t)((int8_t)readByteFromPC() + _programCounter);
}

- (uint16_t)getAddress
{
	return [self readShortFromPC];
}

- (uint8_t *)indexPlusOffset:(int8_t)offset
{
	return [_memory pointerToAddress:(uint16_t)(*_indexRegister + offset)];
}

#pragma mark -
#pragma mark Condition Lookup and Parity Helpers

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
		
		case 0: return !!_lastZeroResult;							//NZ
		case 1: return !_lastZeroResult;							//Z
		case 2: return !(_generalFlags&LLZ80FlagCarry);				//NC
		case 3: return !!(_generalFlags&LLZ80FlagCarry);			//C
		case 4: return !(_generalFlags&LLZ80FlagParityOverflow);	//PO
		case 5: return !!(_generalFlags&LLZ80FlagParityOverflow);	//PE
		case 6: return !(_lastSignResult&0x80);						//P
		case 7: return !!(_lastSignResult&0x80);					//M
	}
}

#pragma mark -
#pragma mark Register Table Lookups

/*
*/
- (uint16_t *)rpTable:(int)index
{
	uint16_t *rpTable[] = {&_bcRegister, &_deRegister, nil, &_spRegister};
	return rpTable[index] ? rpTable[index] : _indexRegister;
}

- (uint16_t *)rp2Table:(int)index
{
	switch(index)
	{
		case 0: return &_bcRegister;
		case 1: return &_deRegister;
		case 2: return _indexRegister;
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
		case 0:	return (uint8_t *)&_bcRegister + kOffsetToHighByte;
		case 1:	return (uint8_t *)&_bcRegister + kOffsetToLowByte;
		case 2:	return (uint8_t *)&_deRegister + kOffsetToHighByte;
		case 3:	return (uint8_t *)&_deRegister + kOffsetToLowByte;
		case 4:	return (uint8_t *)_indexRegister + kOffsetToHighByte;
		case 5:	return (uint8_t *)_indexRegister + kOffsetToLowByte;

		case 6:
			if(_shouldAddOffset)
			{
				uint16_t address = *_indexRegister;
				address += (int8_t)readByteFromPC();
				return [_memory pointerToAddress:address];
			}
			else
				return [_memory pointerToAddress:_hlRegister];
		break;

		case 7:	return (uint8_t *)&_aRegister;
	}

	return NULL;
}

- (uint8_t *)hlrTable:(int)index
{
	uint16_t *realIndexRegister = _indexRegister;
	_indexRegister = &_hlRegister;
	uint8_t *result = [self rTable:index];
	_indexRegister = realIndexRegister;
	return result;
}

#pragma mark -
#pragma mark ALU Operations

- (void)inc:(uint8_t *)value
{
	int result = (*value) + 1;

	// with an increment, overflow occurs if the sign changes from
	// positive to negative
	int overflow = (*value ^ result) & ~(*value);
	int halfResult = (*value&0xf) + 1;

	*value = (uint8_t)result;

	// sign, zero and 5 & 3 are set directly from the result
	_bit5And3Flags = _lastSignResult = _lastZeroResult = (uint8_t)result;
	_generalFlags =
		(_generalFlags & LLZ80FlagCarry) |		// carry isn't affected
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
	_bit5And3Flags = _lastZeroResult = _lastSignResult = (uint8_t)result;
	_generalFlags =
		(_generalFlags & LLZ80FlagCarry) |		// carry isn't affected
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
			int result = _aRegister + value;
			int halfResult = (_aRegister&0xf) + (value&0xf);

			// overflow for addition is when the signs were originally
			// the same and the result is different
			int overflow = ~(value^_aRegister) & (result^_aRegister);

			_aRegister = (uint8_t)result;

			_lastSignResult = _lastZeroResult =
			_bit5And3Flags = (uint8_t)result;				// set sign, zero and 5 and 3
			_generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5);						// overflow flag
															// subtraction is implicitly unset
		}
		break;
		
		case 1: // adc a, ...
		{
			int result = _aRegister + value + (_generalFlags&LLZ80FlagCarry);
			int halfResult = (_aRegister&0xf) + (value&0xf) + (_generalFlags&LLZ80FlagCarry);

			// overflow for addition is when the signs were originally
			// the same and the result is different
			int overflow = ~(value^_aRegister) & (result^_aRegister);

			_aRegister = (uint8_t)result;

			_lastSignResult = _lastZeroResult =
			_bit5And3Flags = (uint8_t)result;			// set sign, zero and 5 and 3
			_generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5);						// overflow flag
															// subtraction is implicitly unset
		}
		break;
		
		case 2:	// sub ...
		{
			int result = _aRegister - value;
			int halfResult = (_aRegister&0xf) - (value&0xf);

			// overflow for a subtraction is when the signs were originally
			// different and the result is different again
			int overflow = (value^_aRegister) & (result^_aRegister);

			_aRegister = (uint8_t)result;

			_lastSignResult = _lastZeroResult =
			_bit5And3Flags = (uint8_t)result;			// set sign, zero and 5 and 3
			_generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5)				|		// overflow flag
				LLZ80FlagSubtraction;						// and this counts as a subtraction
		}
		break;
		
		case 3:	// SBC A, ...
		{
			int result = _aRegister - value - (_generalFlags&LLZ80FlagCarry);
			int halfResult = (_aRegister&0xf) - (value&0xf) - (_generalFlags&LLZ80FlagCarry);;

			// overflow for a subtraction is when the signs were originally
			// different and the result is different again
			int overflow = (value^_aRegister) & (result^_aRegister);

			_aRegister = (uint8_t)result;

			_lastSignResult = _lastZeroResult =
			_bit5And3Flags = (uint8_t)result;			// set sign, zero and 5 and 3
			_generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5)				|		// overflow flag
				LLZ80FlagSubtraction;						// and this counts as a subtraction
		}
		break;
		
		case 4:	// AND ...
		{
			_aRegister &= value;

			_lastSignResult = _lastZeroResult =
			_bit5And3Flags = _aRegister;

			_generalFlags =
				LLZ80FlagHalfCarry |
				[self parity:_aRegister];
		}
		break;

		case 5:	// XOR ...
		{
			_aRegister ^= value;

			_lastSignResult = _lastZeroResult =
			_bit5And3Flags = _aRegister;

			_generalFlags = [self parity:_aRegister];
		}
		break;

		case 6:	// OR ...
		{
			_aRegister |= value;

			_lastSignResult = _lastZeroResult =
			_bit5And3Flags = _aRegister;

			_generalFlags = [self parity:_aRegister];
		}
		break;

		case 7:	// CP ...
		{
			int result = _aRegister - value;
			int halfResult = (_aRegister&0xf) - (value&0xf);

			// overflow for a subtraction is when the signs were originally
			// different and the result is different again
			int overflow = (value^_aRegister) & (result^_aRegister);

			_lastSignResult =			// set sign and zero
			_lastZeroResult = (uint8_t)result;
			_bit5And3Flags = value;		// set the 5 and 3 flags, which come
											// from the operand atypically
			_generalFlags =
				((result >> 8) & LLZ80FlagCarry)	|		// carry flag
				(halfResult & LLZ80FlagHalfCarry)	|		// half carry flag
				((overflow&0x80) >> 5)				|		// overflow flag
				LLZ80FlagSubtraction;						// and this counts as a subtraction
		}
		break;
	}
}

- (void)sbc16:(uint16_t)operand
{
	int result = _hlRegister - operand - (_generalFlags&LLZ80FlagCarry);
	int halfResult = (_hlRegister&0xfff) - (operand&0xfff) - (_generalFlags&LLZ80FlagCarry);

	// subtraction, so parity rules are:
	// signs of operands were different, 
	// sign of result is different
	int overflow = (result ^ _hlRegister) & (operand ^ _hlRegister);

	_hlRegister = (uint16_t)result;

	_bit5And3Flags = _lastSignResult = (uint8_t)(result >> 8);
	_lastZeroResult	= (uint8_t)(result | _lastSignResult);
	_generalFlags =
		LLZ80FlagSubtraction					|
		((result >> 16)&LLZ80FlagCarry)			|
		((halfResult >> 8)&LLZ80FlagHalfCarry)	|
		((overflow&0x8000) >> 13);
}

- (void)adc16:(uint16_t)operand
{
	int result = _hlRegister + operand + (_generalFlags&LLZ80FlagCarry);
	int halfResult = (_hlRegister&0xfff) + (operand&0xfff) + (_generalFlags&LLZ80FlagCarry);

	int overflow = (result ^ _hlRegister) & ~(operand ^ _hlRegister);

	_bit5And3Flags = _lastSignResult = (uint8_t)(result >> 8);
	_lastZeroResult	= (uint8_t)(result | _lastSignResult);
	_generalFlags =
		((result >> 16)&LLZ80FlagCarry)			|
		((halfResult >> 8)&LLZ80FlagHalfCarry) |
		((overflow&0x8000) >> 13);	// implicitly, subtract isn't set

	_hlRegister = (uint16_t)result;
}

- (void)add16:(uint16_t *)target operand:(uint16_t)operand
{
	int result = *target + operand;
	int halfResult = (*target&0xfff) + (operand&0xfff);

	_bit5And3Flags = (uint8_t)(result >> 8);
	_generalFlags =
		(_generalFlags&LLZ80FlagParityOverflow)	|
		((result >> 16)&LLZ80FlagCarry)			|
		((halfResult >> 8)&LLZ80FlagHalfCarry);	// implicitly, subtract isn't set

	*target = (uint16_t)result;
}

#pragma mark -
#pragma mark Stack Operations

- (void)push:(uint16_t)value
{
	_spRegister--;
	[_memory setValue:value >> 8 atAddress:_spRegister];
	_spRegister--;
	[_memory setValue:value & 0xff atAddress:_spRegister];
}

- (uint16_t)pop
{
	uint16_t value = [_memory valueAtAddress:_spRegister];
	_spRegister++;
	value |= [_memory valueAtAddress:_spRegister] << 8;
	_spRegister++;

	return value;
}

- (void)call:(uint16_t)address
{
	[self push:_programCounter];
	_programCounter = address;
}

#pragma mark -
#pragma mark Block Copies/Moves

- (void)blockInstruction:(int)instruction repeatType:(int)repeatType
{
	uint8_t lastResult = 0xff, halfResult = 0, flagResult = 0;
	while(1)
	{
		switch(instruction)
		{
			case 0:	// ld
			{
				uint8_t value = [_memory valueAtAddress:_hlRegister];
				[_memory setValue:value atAddress:_deRegister];

				flagResult = _aRegister + value;
//				halfResult = (_aRegister&0xf) + (RAM[_hlRegister]&0xf);
			}
			break;
			case 1: // cp
			{
				uint8_t value = [_memory valueAtAddress:_hlRegister];

				flagResult = lastResult = _aRegister - value;
				halfResult = (_aRegister&0xf) - (value&0xf);
			}
			break;

			case 2:	// in
				// we'll assume we just read 0xff
			case 3: // out
			break;
		}

		if(instruction < 2)
			_bcRegister--;
		else
			_bcRegister-= 0x100;

		switch(repeatType)
		{
			case 0: // i
			case 2: // ir
				_hlRegister++;
				if(!instruction) _deRegister++;
			break;
			case 1: // d
			case 3: // dr
				_hlRegister--;
				if(!instruction) _deRegister--;
			break;
		}

		if(repeatType < 2) break;
		if(!(_bcRegister >> ((instruction < 2) ? 0 : 8)) || !lastResult) break;
	}

	_generalFlags =
		(_generalFlags&LLZ80FlagCarry) |
		(_bcRegister ? LLZ80FlagParityOverflow : 0) |
		(halfResult & LLZ80FlagHalfCarry);
	if(instruction == 1)
	{
		_generalFlags |= LLZ80FlagSubtraction;
		_lastSignResult = _lastZeroResult = flagResult;
	}

	_bit5And3Flags = (uint8_t)((flagResult&0x8) | ((flagResult&0x2) << 4));
}

#pragma mark -
#pragma mark Set/Res/Bit

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

	_lastSignResult = _lastZeroResult = result;
	_bit5And3Flags = *source;
	_generalFlags =
		(_generalFlags & LLZ80FlagCarry) |
		LLZ80FlagHalfCarry |
		(result ? 0 : LLZ80FlagParityOverflow);
}

#pragma mark -
#pragma mark Shifts and Rolls

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
			*source = (uint8_t)((*source << 1) | (_generalFlags&LLZ80FlagCarry));
		}
		break;
		case 3: // RR
		{
			carry = *source & 1;
			*source = (uint8_t)((*source >> 1) | (_generalFlags << 7));
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

	_generalFlags = carry | [self parity:*source];
	_bit5And3Flags = _lastSignResult = _lastZeroResult = *source;

	return *source;
}

#pragma mark -
#pragma mark Opcode Decoding Logic

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
						_aRegister = 0xff;
					}
					else
					{
						// in r, (c); sets f
						*[self rTable:y] = 0xff;
						_bit5And3Flags = 0xa4;
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

						*target = [_memory valueAtAddress:address];
						address++;
						*target |= (uint16_t)[_memory valueAtAddress:address] << 8;
						//LD rr, (nnnn)
					}
					else
					{
						uint16_t address = [self getAddress];
						uint16_t *target = [self rpTable:y >> 1];

						[_memory setValue:(*target)&0xff atAddress:address];
						address++;
						[_memory setValue:*target >> 8 atAddress:address];
						//LD (nnnn), rr
					}
				break;
				case 4: // NEG
				{
					// -128 is the only thing that'll overflow
					// when negated
					int overflow = (_aRegister == 0x80);
					int result = 0 - _aRegister;
					int halfResult = 0 - (_aRegister&0xf);

					_aRegister = (uint8_t)result;
					_bit5And3Flags = _lastSignResult = _lastZeroResult = _aRegister;
					_generalFlags =
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
						_programCounter = [self pop];
					}
					else
					{
						// reti
						_programCounter = [self pop];
					}
				break;
				case 6:
					// IM 0, 1 or 0/1; we don't really care
				break;
				case 7:
					switch(y)
					{
						case 0:	_iRegister = _aRegister;	break;
						case 1: _rRegister = _aRegister;	break;
						case 2:	// LD a, i
						{
							_aRegister = _iRegister;
							_lastZeroResult = _lastSignResult = _bit5And3Flags = _iRegister;
							_generalFlags &= LLZ80FlagCarry;
						}
						break;
						case 3: // ld a, r
						{
							_aRegister = _rRegister;
							_lastZeroResult = _lastSignResult = _bit5And3Flags = _rRegister;
							_generalFlags &= LLZ80FlagCarry;
						}
						break;
						case 4:	// RRD
						{
							uint8_t temporaryValue = [_memory valueAtAddress:_hlRegister];

							int lowNibble = _aRegister&0xf;
							_aRegister = (_aRegister&0xf0) | (temporaryValue & 0xf);
							temporaryValue = (uint8_t)((temporaryValue >> 4) | (lowNibble << 4));

							_generalFlags =
								[self parity:_aRegister] |
								(_generalFlags&LLZ80FlagCarry);
							_lastSignResult = _lastZeroResult =
							_bit5And3Flags = _aRegister;

							[_memory setValue:temporaryValue atAddress:_hlRegister];
						}
						break;
						case 5: // RLD
						{
							uint8_t temporaryValue = [_memory valueAtAddress:_hlRegister];

							int lowNibble = _aRegister&0xf;
							_aRegister = (_aRegister&0xf0) | (temporaryValue >> 4);
							temporaryValue = (uint8_t)((temporaryValue << 4) | lowNibble);

							_generalFlags =
								[self parity:_aRegister] |
								(_generalFlags&LLZ80FlagCarry);
							_lastSignResult = _lastZeroResult =
							_bit5And3Flags = _aRegister;

							[_memory setValue:temporaryValue atAddress:_hlRegister];
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
	if(_shouldAddOffset) displacement = (int8_t)readByteFromPC();
	uint8_t opcode = readByteFromPC();
	int x = opcode >> 6;
	int y = (opcode >> 3)&7;
	int z = opcode&7;

	if(_shouldAddOffset)
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
//	if(_programCounter == 29292) isLogging = YES;
//	if(isLogging)
//		printf("%04x AF:%04x BC:%04x DE:%04x HL:%04x SP:%04x [%02x %02x %02x %02x]\n", _programCounter, self.afRegister, _bcRegister, _deRegister, _hlRegister, _spRegister, [memory valueAtAddress:_programCounter], [memory valueAtAddress:_programCounter+1], [memory valueAtAddress:_programCounter+2], [memory valueAtAddress:_programCounter+3]);

	_rRegister = (_rRegister+1)&127;	// for the sake of incrementing this somewhere; we don't really care for accuracy
	uint8_t opcode = readByteFromPC();
	uint8_t x = opcode >> 6;
	uint8_t y = (opcode >> 3)&7;
	uint8_t z = opcode&7;

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
							self.afRegister = _afDashRegister;
							_afDashRegister = temp;
						}
						break;
						case 2:	// DJNZ
						{
							uint16_t address = [self getOffset];
							uint8_t *bRegister = [self rTable:rTableIndexB];

							(*bRegister)--;

							if(*bRegister)
							{
								_programCounter = address;
							}
						}
						break;
						case 3:
						{
							_programCounter = [self getOffset];
							// jr nn
						}
						break;
						default:
						{
							// JR cc, nn
							uint16_t address = [self getOffset];
							if([self condition:y-4])
								_programCounter = address;
						}
						break;
					}
				break;
				case 1:
					if(y&1)
					{
						[self add16:_indexRegister operand:*[self rpTable:y >> 1]];
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
							[_memory setValue:_aRegister atAddress:_bcRegister];
						break;
						case 1:	// LD A, (BC)
							_aRegister = [_memory valueAtAddress:_bcRegister];
						break;
						case 2: // LD (DE), A
							[_memory setValue:_aRegister atAddress:_deRegister];
						break;
						case 3: // LD A, (DE)
							_aRegister = [_memory valueAtAddress:_deRegister];
						break;
						case 4:
						{
							uint16_t address = [self getAddress];
							[_memory setValue:*[self rTable:rTableIndexL] atAddress:address];
							address++;
							[_memory setValue:*[self rTable:rTableIndexH] atAddress:address];
							// LD (nnnn), HL
						}
						break;
						case 5:
						{
							uint16_t address = [self getAddress];
							*[self rTable:rTableIndexL] = [_memory valueAtAddress:address];
							address++;
							*[self rTable:rTableIndexH] = [_memory valueAtAddress:address];
							//LD HL, (nnnn)
						}
						break;
						case 6:
							[_memory setValue:_aRegister atAddress:[self getAddress]];
							// LD (nnnn), a
						break;
						case 7:
							_aRegister = [_memory valueAtAddress:[self getAddress]];
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
							uint8_t newCarry = _aRegister >> 7;
							_aRegister = (uint8_t)((_aRegister << 1) | newCarry);
							_bit5And3Flags = _aRegister;
							_generalFlags =
								(_generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 1: // RRCA
						{
							uint8_t newCarry = _aRegister & 1;
							_aRegister = (uint8_t)((_aRegister >> 1) | (newCarry << 7));
							_bit5And3Flags = _aRegister;
							_generalFlags =
								(_generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 2: // RLA
						{
							uint8_t newCarry = _aRegister >> 7;
							_aRegister = (uint8_t)((_aRegister << 1) | (_generalFlags&LLZ80FlagCarry));
							_bit5And3Flags = _aRegister;
							_generalFlags =
								(_generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 3:	// RRA
						{
							uint8_t newCarry = _aRegister & 1;
							_aRegister = (uint8_t)((_aRegister >> 1) | ((_generalFlags&LLZ80FlagCarry) << 7));
							_bit5And3Flags = _aRegister;
							_generalFlags =
								(_generalFlags & LLZ80FlagParityOverflow) |
								newCarry;
						}
						break;
						case 4: // DAA
						{
							int lowNibble = _aRegister & 0xf;
							int highNibble = _aRegister >> 4;

							int amountToAdd = 0;

							if(_generalFlags & LLZ80FlagCarry)
							{
								if(lowNibble > 0x9 || _generalFlags&LLZ80FlagHalfCarry)
									amountToAdd = 0x66;
								else
									amountToAdd = 0x60;
							}
							else
							{
								if(_generalFlags & LLZ80FlagHalfCarry)
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

							int newCarry = _generalFlags & LLZ80FlagHalfCarry;
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
							if(_generalFlags&LLZ80FlagSubtraction)
							{
								(_aRegister) -= amountToAdd;
								if(_generalFlags&LLZ80FlagHalfCarry)
								{
									newHalfCarry = (lowNibble < 0x6) ? LLZ80FlagHalfCarry : 0;
								}
							}
							else
							{
								(_aRegister) += amountToAdd;
								newHalfCarry = (lowNibble > 0x9) ? LLZ80FlagHalfCarry : 0;
							}

							_lastSignResult = _lastZeroResult =
							_bit5And3Flags = _aRegister;
							
							uint8_t parity = _aRegister;
							parity ^= (parity >> 4);
							parity ^= (parity >> 2);
							parity ^= (parity >> 1);

							_generalFlags =
								(uint8_t)(
									newCarry |
									newHalfCarry |
									((parity&1) << 3) |
									(_generalFlags&LLZ80FlagSubtraction));
						}
						break;
						case 5:	// CPL
						{
							_aRegister ^= 0xff;
							_generalFlags |=
								LLZ80FlagHalfCarry |
								LLZ80FlagSubtraction;
							_bit5And3Flags = _aRegister;
						}
						break;
						case 6:	// SCF
						{
							_bit5And3Flags = _aRegister;
							_generalFlags =
								(_generalFlags & LLZ80FlagParityOverflow) |
								LLZ80FlagCarry;
						}
						break;
						case 7:	// CCF
						{
							_bit5And3Flags = _aRegister;
							_generalFlags =
								(uint8_t)(
									(_generalFlags & LLZ80FlagParityOverflow) |
									((_generalFlags & LLZ80FlagCarry) << 4) |	// so half carry is what carry was
									((_generalFlags&LLZ80FlagCarry)^LLZ80FlagCarry));
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
				_isBlocked = YES;
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
						_programCounter = [self pop];
					// ret cc
				break;
				case 1:
					if(y&1)
					{
						switch(y >> 1)
						{
							case 0:	// ret
								_programCounter = [self pop];
							break;
							case 1:	// exx
							{
								uint16_t temporaryStore;

								temporaryStore = _bcRegister;
								_bcRegister = _bcDashRegister;
								_bcDashRegister = temporaryStore;

								temporaryStore = _deRegister;
								_deRegister = _deDashRegister;
								_deDashRegister = temporaryStore;

								temporaryStore = _hlRegister;
								_hlRegister = _hlDashRegister;
								_hlDashRegister = temporaryStore;
							}
							break;
							case 2:	// JP indexRegister
								_programCounter = *_indexRegister;
							break;
							case 3: // LD SP, indexRegister
								_spRegister = *_indexRegister;
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
						_programCounter = address;
					// JP cc, nnnn
				}
				break;
				case 3:
					switch(y)
					{
						case 0: // JP nnnn
							_programCounter = [self getAddress];
						break;
						case 1: [self executeFromCBPage];										break;
						case 2: NSLog(@"OUT ($%02x), A [%02x]", readByteFromPC(), _aRegister);	break;
						case 3:
						{
							uint8_t portNumber = readByteFromPC();
							_aRegister = [self.delegate processor:self valueForPort:portNumber];
						}
						break;
						case 4:
						{
							uint16_t temporaryValue = [self pop];
							[self push:*_indexRegister];
							*_indexRegister = temporaryValue;
							// ex (sp), hl
						}
						break;
						case 5:
						{
							// EX DE, HL
							uint16_t temporaryValue = _deRegister;
							_deRegister = _hlRegister;
							_hlRegister = temporaryValue;
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
								_indexRegister = &_ixRegister;
								_shouldAddOffset = YES;
								[self executeFromStandardPage];
								_indexRegister = &_hlRegister;
								_shouldAddOffset = NO;
							break;
							case 2: [self executeFromEDPage];				break;
							case 3:
								_indexRegister = &_iyRegister;
								_shouldAddOffset = YES;
								[self executeFromStandardPage];
								_indexRegister = &_hlRegister;
								_shouldAddOffset = NO;
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
					[self call:(uint16_t)(y << 3)];	// recall: y doesn't use the top-three bits
					// RST n
				break;
			}
		break;
	}
}

#pragma mark -
#pragma mark Temporal Call-ins

- (void)runUntilPC:(uint16_t)targetPC
{
	int maxInstructionCount = 1000;
	while(_programCounter != targetPC && maxInstructionCount--)
	{
		[self executeFromStandardPage];
	}
}

- (void)runForTimeInterval:(NSTimeInterval)timeInterval
{
	NSTimeInterval timeAtStart = [NSDate timeIntervalSinceReferenceDate];

	while(!_isBlocked && [NSDate timeIntervalSinceReferenceDate] - timeAtStart < timeInterval)
	{
		[self runForNumberOfInstructions:1000];
	}
}

- (void)runForNumberOfInstructions:(NSUInteger)numberOfInstructions
{
	// we're going to call this thing millions of times a second, probably, so caching the IMP
	// is a pragmatic performance optimisation
	void (*executeFromStandardPage)(id, SEL) = (void(*)(id,SEL))[self methodForSelector:@selector(executeFromStandardPage)];

	while(!_isBlocked && numberOfInstructions--)
	{
		if(_programCounter >= _biosAddress)
		{
			_isBlocked = [self.delegate processor:self isMakingBIOSCall:(uint8_t)((_programCounter - _biosAddress) / 3)];
			_programCounter = [self pop];
		}
		else
		{
			executeFromStandardPage(self, @selector(executeFromStandardPage));
		}
	}
	
}

#pragma mark -
#pragma mark Getters and Setters

- (void)unblock
{
	if(_isBlocked)
		[self.delegate processorWillUnblock:self];
	_isBlocked = NO;
}

- (void)setAfRegister:(uint16_t)afRegister
{
	_lastSignResult = afRegister & LLZ80FlagSign;
	_lastZeroResult = (afRegister & LLZ80FlagZero)^LLZ80FlagZero;
	_bit5And3Flags = afRegister & (LLZ80FlagBit5 | LLZ80FlagBit3);
	_generalFlags = afRegister & (LLZ80FlagCarry | LLZ80FlagHalfCarry | LLZ80FlagParityOverflow | LLZ80FlagSubtraction);

	_aRegister = afRegister >> 8;
}

- (uint16_t)afRegister
{
	uint8_t fRegister =
		(_lastSignResult&LLZ80FlagSign) |
		(_lastZeroResult ? 0 : LLZ80FlagZero) |
		(_bit5And3Flags & (LLZ80FlagBit5 | LLZ80FlagBit3)) |
		(_generalFlags & (LLZ80FlagCarry | LLZ80FlagHalfCarry | LLZ80FlagParityOverflow | LLZ80FlagSubtraction));

	return (uint16_t)((_aRegister << 8) | fRegister);
}

- (void)set8bitCPMResult:(uint8_t)result
{
	// an 8-bit result goes to A and L
	_hlRegister = (_hlRegister & 0xff00) | result;
	_aRegister = result;
}

- (void)set16bitCPMResult:(uint16_t)result
{
	// an 16-bit result goes to BA and HL
	_hlRegister = result;
	_aRegister = (uint8_t)(result&0xff);
	_bcRegister = (_bcRegister & 0xff) | (result & 0xff00);
}

@end
