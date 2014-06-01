//
//  CPMProcessor.h
//  CP-Em
//
//  Created by Thomas Harte on 09/09/2012.
//  Copyright (c) 2012 Thomas Harte. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CPMProcessor;
typedef BOOL CPMProcessorShouldBlock;

@protocol CPMProcessorDelegate <NSObject>

- (CPMProcessorShouldBlock)processor:(CPMProcessor *)processor isMakingBDOSCall:(uint8_t)call parameter:(uint16_t)parameter;
- (CPMProcessorShouldBlock)processor:(CPMProcessor *)processor isMakingBIOSCall:(uint8_t)call;
- (void)processorDidHalt:(CPMProcessor *)processor;

@end

@class CPMRAMModule;

@interface CPMProcessor : NSObject

+ (id)processorWithRAM:(CPMRAMModule *)RAM;

- (void)runForTimeInterval:(NSTimeInterval)timeInterval;
- (void)runForNumberOfInstructions:(NSUInteger)numberOfInstructions;
- (void)runUntilPC:(uint16_t)targetPC;

- (void)unblock;

- (void)set8bitCPMResult:(uint8_t)result;
- (void)set16bitCPMResult:(uint16_t)result;

@property (nonatomic, weak) id <CPMProcessorDelegate> delegate;

@property (nonatomic, assign) uint16_t afRegister;
@property (nonatomic, assign) uint16_t bcRegister;
@property (nonatomic, assign) uint16_t deRegister;
@property (nonatomic, assign) uint16_t hlRegister;
@property (nonatomic, assign) uint16_t afDashRegister;
@property (nonatomic, assign) uint16_t bcDashRegister;
@property (nonatomic, assign) uint16_t deDashRegister;
@property (nonatomic, assign) uint16_t hlDashRegister;
@property (nonatomic, assign) uint16_t ixRegister;
@property (nonatomic, assign) uint16_t iyRegister;
@property (nonatomic, assign) uint16_t spRegister;
@property (nonatomic, assign) uint16_t programCounter;
@property (nonatomic, assign) uint8_t iRegister;
@property (nonatomic, assign) uint8_t rRegister;

@property (nonatomic, assign) uint16_t biosAddress;
@property (nonatomic, readonly) BOOL isBlocked;

@end
