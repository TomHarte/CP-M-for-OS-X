//
//  CPMFuseTestRunner.h
//  CP-Em
//
//  Created by Thomas Harte on 11/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

/*

	This is a unit test, essentially. It runs the FUSE Z80 tests
	(applying only a subset of the critera, admittedly) against
	this emulator's Z80 engine and logs some results.

	This requires the FUSE files tests.expected and tests.in to
	be incorporated into the project.

*/

@interface CPMFuseTestRunner : NSObject

- (void)go;

@end
