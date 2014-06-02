//
//  CPMDocument.m
//  CPM for OS X
//
//  Created by Thomas Harte on 12/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import "CPMDocument.h"
#import "BDOS.h"
#import "TerminalView.h"
#import "FuseTestRunner.h"

@class CPMTerminalView;

@interface CPMDocument ()

@property (nonatomic, weak) IBOutlet CPMTerminalView *terminalView;

@end

@implementation CPMDocument
{
	NSURL *_sourceURL;
	CPMBDOS *_bdos;
	NSTimer *_executionTimer;
	dispatch_queue_t _serialDispatchQueue;

	NSUInteger _blockedCount;
	BOOL _disallowFastExecution;
}

#pragma mark -
#pragma mark Document conversion to/from NSData
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	// Insert code here to write your document to data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning nil.
	// You can also choose to override -fileWrapperOfType:error:, -writeToURL:ofType:error:, or -writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.
//	NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
//	@throw exception;
	return [NSData data];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError
{
	// we do the actual setup consequentially to loading of the NIB so, for now,
	// just store the URL away
	_sourceURL = url;

	return YES;
}

#pragma mark -
#pragma mark NIB nomination and loading

- (NSString *)windowNibName
{
	// Override returning the nib file name of the document
	// If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
	return @"CPMDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];

	// create our BDOS instance and pipe the terminal view's delegate messages to here
	_bdos = [[CPMBDOS alloc] initWithContentsOfURL:_sourceURL terminalView:self.terminalView];
	self.terminalView.delegate = self;

	// we'll call our execution timer 50 times a second, as a nod towards PAL;
	// no need to worry about a retain cycle here as -close will be called
	// before any attempt to dealloc
	_executionTimer = [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(doMoreProcessing:) userInfo:nil repeats:YES];

	// a serial dispatch queue will keep actual machine execution off the main queue
	_serialDispatchQueue = dispatch_queue_create("CPM dispatch queue", DISPATCH_QUEUE_SERIAL);

	// this isn't entirely honest, but it'll force us to lock the aspect ratio now
	[self terminalViewDidChangeIdealRect:self.terminalView];

	// were you to want to run the FUSE Z80 conformance tests, you would...
//	CPMFuseTestRunner *testRunner = [[CPMFuseTestRunner alloc] init];
//	[testRunner go];
//	[testRunner release];
}

- (void)doMoreProcessing:(NSTimer *)timer
{
	/*

		Logic is:

			- ordinarily (ie, when fast execution isn't disallowed) allow up to 90%
			utilisation; but
			- if that full amount is used for five calls in a row then cut avaiable CPU time
			down to just 14000 instructions/second; and
			- restore full speed execution only if the CPU starts blocking again for
			at least a second.

		So the motivation is not to penalise apps that occasionally do a lot of
		processing but mostly block waiting for input while preventing apps that
		run a busy loop from wasting your modern multi-tasking computer's
		processing time.

		As for the 14000? 4Mhz/(50 calls * 6 cycles), rounded up a little. Is the average
		z80 instruction length really 6 cycles? Bearing in mind that all the more expensive
		instructions are ones that are absent on the 8080, it's probably something short.

	*/
	__weak typeof(self) weakSelf = self;
	dispatch_async(_serialDispatchQueue,
	^{
		typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		if(strongSelf->_disallowFastExecution)
		{
			[strongSelf->_bdos runForNumberOfInstructions:14000];
			if(strongSelf->_bdos.didBlock)
			{
				strongSelf->_blockedCount++;
				if(strongSelf->_blockedCount == 100) strongSelf->_disallowFastExecution = NO;
			}
			else
				strongSelf->_blockedCount = 0;
		}
		else
		{
			[strongSelf->_bdos runForTimeInterval:0.018];
			if(!strongSelf->_bdos.didBlock)
			{
				strongSelf->_blockedCount++;
				if(strongSelf->_blockedCount == 5) strongSelf->_disallowFastExecution = YES;
			}
			else
				strongSelf->_blockedCount = 0;
		}
	});
}

- (void)close
{
	[_executionTimer invalidate];
	[self.terminalView invalidate];
	if(_serialDispatchQueue)
	{
		dispatch_release(_serialDispatchQueue), _serialDispatchQueue = NULL;
	}

	[super close];
}


#pragma mark -
#pragma mark CPMTerminalViewDelegate

- (void)terminalViewDidAddCharactersToBuffer:(CPMTerminalView *)terminalView
{
	// channel the news onto our serial dispatch queue
	__weak typeof(self) weakSelf = self;
	dispatch_async(_serialDispatchQueue,
	^{
		typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;
		[strongSelf->_bdos terminalViewDidAddCharactersToBuffer:terminalView];
	});
}

- (void)terminalViewDidChangeIdealRect:(CPMTerminalView *)terminalView
{
	// we have only one window, so...
	NSWindow *window = [(NSWindowController *)[self windowControllers][0] window];

	// restrict our window's aspect ratio appropriately
	NSSize idealSize = [self.terminalView idealSize];
	[window setContentAspectRatio:idealSize];

	// adjust the frame to enforce the correct aspect ratio now, not just
	// whenever the user next resizes
	NSRect frame = window.frame;
	NSSize contentSize = ((NSView *)window.contentView).frame.size;

	// we'll adjust whichever of x or y makes the least difference
	CGFloat xDifference = (contentSize.height * idealSize.width / idealSize.height) - contentSize.width;
	CGFloat yDifference = (contentSize.width * idealSize.height / idealSize.width) - contentSize.height;

	if(fabs(xDifference) < fabs(yDifference))
		frame.size.width += xDifference;
	else
		frame.size.height += yDifference;

	[window setFrame:frame display:YES animate:YES];
}

- (void)terminalView:(CPMTerminalView *)terminalView didReceiveFileAtURL:(NSURL *)URL
{
	[_bdos addAccessToURL:URL];
}

@end
