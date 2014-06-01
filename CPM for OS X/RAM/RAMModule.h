//
//  CPMRAMModule.h
//  CPM for OS X
//
//  Created by Thomas Harte on 12/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

/*

	RAM is given its own class on the expectation that I may
	want to add banking in the future, in which case there'll
	start being a conversion between logical and physical addresses

*/

@interface CPMRAMModule : NSObject

//
// plain init will return an unbanked, 64kb module
//

//
// setValue:atAddress: and valueAtAddress: read and write single bytes;
// they're directly analogous to the NSDictionary methods
//
- (void)setValue:(uint8_t)value atAddress:(uint16_t)address;
- (uint8_t)valueAtAddress:(uint16_t)address;

//
// pointerToAddress: returns a pointer that's valid for a single byte
// read or write (or both). It's primarily intended to allow the processor
// to perform read/modify/write operations concisely
//
- (uint8_t *)pointerToAddress:(uint16_t)address;

//
// reading and writing chunks of data should be achieved either with the
// two methods below or a byte at a time with the NSDictionary-like
// methods. These may need to work with non-contiguous regions underneath
// if and when paging becomes a consideration
//
- (void)setData:(NSData *)data atAddress:(uint16_t)address;
- (NSData *)dataAtAddress:(uint16_t)address length:(size_t)length;

@end
