//
//  CPMDocument.h
//  CPM for OS X
//
//  Created by Thomas Harte on 12/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TerminalView.h"

@interface CPMDocument : NSDocument <CPMTerminalViewDelegate>

@end
