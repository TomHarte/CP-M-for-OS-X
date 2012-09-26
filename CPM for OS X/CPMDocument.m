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

@property (nonatomic, assign) IBOutlet CPMTerminalView *terminalView;

@end

@implementation CPMDocument
{
	NSURL *_sourceURL;
	CPMBDOS *_bdos;
	NSTimer *_executionTimer;
	dispatch_queue_t serialDispatchQueue;

	NSUInteger _blockedCount;
	BOOL _disallowFastExecution;
}

- (void)close
{
	[_bdos release], _bdos = nil;
	[_executionTimer invalidate], _executionTimer = nil;
	[_sourceURL release], _sourceURL = nil;
	[self.terminalView invalidate];
	if(serialDispatchQueue)
	{
		dispatch_release(serialDispatchQueue), serialDispatchQueue = NULL;
	}
}

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
	_bdos = [[CPMBDOS BDOSWithContentsOfURL:_sourceURL terminalView:self.terminalView] retain];
	self.terminalView.delegate = self;

	// get base path...
	_bdos.basePath = [[_sourceURL path] stringByDeletingLastPathComponent];

	// we'll call our execution timer 50 times a second, as a nod towards PAL
	_executionTimer = [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(doMoreProcessing:) userInfo:nil repeats:YES];

	// a serial dispatch queue will keep actual machine execution off the main queue
	serialDispatchQueue = dispatch_queue_create("CPM dispatch queue", DISPATCH_QUEUE_SERIAL);

//	CPMFuseTestRunner *testRunner = [[CPMFuseTestRunner alloc] init];
//	[testRunner go];
//	[testRunner release];
}

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
	_sourceURL = [url retain];
	return YES;
}

- (void)doMoreProcessing:(NSTimer *)timer
{
	/*

		Logic is:

			- ordinarily (ie, when fast execution isn't disallowed) allow up to 90%
			utilisation; but
			- if that full amount is used for a second then cut avaiable CPU time
			down to just 50%; and
			- restore full speed execution only if the alotted 50% isn't used for
			at least a second.

		So the motivation is not to penalise apps that occasionally do a lot of
		processing but mostly block waiting for input while preventing apps that
		run a busy loop from wasting your modern multi-tasking computer's
		processing time.

	*/
	dispatch_async(serialDispatchQueue,
	^{
		if(_disallowFastExecution)
		{
			[_bdos runForTimeInterval:0.01];
			if(_bdos.didBlock)
			{
				_blockedCount++;
				if(_blockedCount == 100) _disallowFastExecution = NO;
			}
			else
				_blockedCount = 0;
		}
		else
		{
			[_bdos runForTimeInterval:0.018];
			if(!_bdos.didBlock)
			{
				_blockedCount++;
				if(_blockedCount == 56) _disallowFastExecution = YES;
			}
			else
				_blockedCount = 0;
		}
	});
}

- (void)terminalViewDidAddCharactersToBuffer:(CPMTerminalView *)terminalView
{
	dispatch_async(serialDispatchQueue,
	^{
		[_bdos terminalViewDidAddCharactersToBuffer:terminalView];
	});
}

- (void)terminalViewDidChangeIdealRect:(CPMTerminalView *)terminalView
{
	// we have only one window, so...
	NSWindow *window = [[[self windowControllers] objectAtIndex:0] window];

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

	if(fabsf(xDifference) < fabsf(yDifference))
		frame.size.width += xDifference;
	else
		frame.size.height += yDifference;

	[window setFrame:frame display:YES animate:YES];
}

@end
