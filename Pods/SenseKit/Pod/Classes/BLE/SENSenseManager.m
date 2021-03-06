//
//  SENSenseManager.m
//  Pods
//
//  Created by Jimmy Lu on 8/22/14.
//  Copyright (c) 2014 Hello Inc. All rights reserved.
//

#import <CocoaLumberjack/DDLog.h>
#import <CocoaLumberjack/DDLogMacros.h>

#import <CoreBluetooth/CoreBluetooth.h>

#import <LGBluetooth/LGBluetooth.h>

#import "LGCentralManager.h"
#import "LGPeripheral.h"

#import "SENSenseManager.h"
#import "SENSense+Protected.h"
#import "SENSenseMessage.pb.h"

#ifndef ddLogLevel
#define ddLogLevel LOG_LEVEL_VERBOSE
#endif

static CGFloat const kSENSenseDefaultTimeout = 20.0f;
static CGFloat const kSENSenseRescanTimeout = 8.0f;
static CGFloat const kSENSenseSetWifiTimeout = 60.0f; // firmware suggestion
static CGFloat const kSENSenseScanWifiTimeout = 45.0f; // firmware actually suggests 60, but 45 seems to work consistently
static CGFloat const kSENSensePillPairTimeout = 90.0f; // firmware timesout at 60, we need this to be longer.  90 was ok'ed by firwmare

static NSString* const kSENSenseErrorDomain = @"is.hello.ble";
static NSString* const kSENSenseServiceID = @"0000FEE1-1212-EFDE-1523-785FEABCD123";
static NSString* const kSENSenseCharacteristicInputId = @"BEEB";
static NSString* const kSENSenseCharacteristicResponseId = @"B00B";
static NSInteger const kSENSensePacketSize = 20;
static NSInteger const kSENSenseMessageVersion = 0;

typedef BOOL(^SENSenseUpdateBlock)(id response);

@interface SENSenseManager()

@property (nonatomic, assign, readwrite, getter=isValid) BOOL valid;
@property (nonatomic, strong, readwrite) SENSense* sense;
@property (nonatomic, strong, readwrite) id disconnectNotifyObserver;
@property (nonatomic, strong, readwrite) NSMutableDictionary* disconnectObservers;
@property (nonatomic, strong, readwrite) NSMutableDictionary* messageSuccessCallbacks;
@property (nonatomic, strong, readwrite) NSMutableDictionary* messageFailureCallbacks;
@property (nonatomic, strong, readwrite) NSMutableDictionary* messageUpdateCallbacks;
@property (nonatomic, strong, readwrite) NSMutableDictionary* messageTimeoutTimers;

@end

@implementation SENSenseManager

+ (BOOL)scanForSense:(void(^)(NSArray* senses))completion {
    return [self scanForSenseWithTimeout:kSENSenseDefaultTimeout
                              completion:completion];
}

+ (BOOL)scanForSenseWithTimeout:(NSTimeInterval)timeout
                     completion:(void(^)(NSArray* senses))completion {
    
    LGCentralManager* btManager = [LGCentralManager sharedInstance];
    if (![btManager isCentralReady]) return NO;
    
    DDLogVerbose(@"scanning for Sense started");
    CBUUID* serviceId = [CBUUID UUIDWithString:kSENSenseServiceID];
    [btManager scanForPeripheralsByInterval:timeout
                                   services:@[serviceId]
                                    options:nil
                                 completion:^(NSArray* peripherals) {
                                     NSMutableArray* senses = nil;
                                     NSInteger count = [peripherals count];
                                     SENSense* sense = nil;
                                     if (count > 0) {
                                         senses = [NSMutableArray arrayWithCapacity:count];
                                         for (LGPeripheral* device in peripherals) {
                                             sense = [[SENSense alloc] initWithPeripheral:device];
                                             [senses addObject:sense];
                                         }
                                     }
                                     DDLogVerbose(@"scan completed with %ld Sense(s) found", (long)count);
                                     if (completion) completion(senses);
                                 }];
    return YES;
}

+ (void)stopScan {
    DDLogVerbose(@"scan stopped");
    if ([[LGCentralManager sharedInstance] isScanning]) {
        [[LGCentralManager sharedInstance] stopScanForPeripherals];
    }
}

+ (BOOL)isScanning {
    return [[LGCentralManager sharedInstance] isScanning];
}

+ (BOOL)isReady {
    return [[LGCentralManager sharedInstance] isCentralReady];
}

+ (BOOL)canScan {
    CBCentralManagerState state = [[[LGCentralManager sharedInstance] manager] state];
    return state != CBCentralManagerStateUnauthorized
            && state != CBCentralManagerStateUnsupported;
}

- (instancetype)initWithSense:(SENSense*)sense {
    self = [super init];
    if (self) {
        DDLogVerbose(@"Sense manager initialized for %@", [sense name]);
        [self setSense:sense];
        [self setValid:YES];
        [self setMessageSuccessCallbacks:[NSMutableDictionary dictionary]];
        [self setMessageFailureCallbacks:[NSMutableDictionary dictionary]];
        [self setMessageUpdateCallbacks:[NSMutableDictionary dictionary]];
        [self setMessageTimeoutTimers:[NSMutableDictionary dictionary]];
    }
    return self;
}

- (BOOL)isConnected {
    return [[[[self sense] peripheral] cbPeripheral] state] == CBPeripheralStateConnected;
}

- (void)rediscoverToConnectThen:(void(^)(NSError* error))completion {
    __weak typeof(self) weakSelf = self;
    DDLogVerbose(@"rediscovering Sense %@", [[self sense] name]);
    [[self class] scanForSenseWithTimeout:kSENSenseRescanTimeout completion:^(NSArray *senses) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            BOOL foundAgain = NO;
            if ([senses count] > 0) {
                for (SENSense* sense in senses) {
                    if ([[[strongSelf sense] deviceId] isEqualToString:[sense deviceId]]) {
                        [strongSelf setSense:sense];
                        foundAgain = YES;
                        break;
                    }
                }
                
                if (foundAgain) {
                    DDLogVerbose(@"Sense rediscovered");
                    [strongSelf setValid:YES];
                    LGPeripheral* peripheral = [[strongSelf sense] peripheral];
                    [peripheral connectWithTimeout:kSENSenseDefaultTimeout completion:completion];
                }
            }
            
            if (!foundAgain && completion) {
                DDLogVerbose(@"Sense not found when trying to rediscover");
                completion ([NSError errorWithDomain:kSENSenseErrorDomain
                                                code:SENSenseManagerErrorCodeInvalidated
                                            userInfo:nil]);
            }
            
        }
    }];
}

/**
 * Connect to Sense then invoke the completion block.  If already connected, completion
 * block will be immediately invoked.
 * param: completion block to invoke when connected, or when there is an error
 */
- (void)connectThen:(void(^)(NSError* error))completion {
    if (!completion) return; // even if we do stuff, what would it be for?
    
    LGPeripheral* peripheral = [[self sense] peripheral];
    if (peripheral == nil) {
        completion ([NSError errorWithDomain:kSENSenseErrorDomain
                                        code:SENSenseManagerErrorCodeNoDeviceSpecified
                                    userInfo:nil]);
        return;
    }
    
    if (![self isConnected]) {
        __weak typeof(self) weakSelf = self;
        
        id postConnectionBlock = ^(NSError* error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && error == nil) {
                [strongSelf listenForUnexpectedDisconnects];
            }
            if (completion) completion (error);
        };
        
        if (![self isValid]) {
            [self rediscoverToConnectThen:postConnectionBlock];
        } else {
            DDLogVerbose(@"attempting to connect to Sense %@", [[self sense] name]);
            [peripheral connectWithTimeout:kSENSenseDefaultTimeout
                                completion:postConnectionBlock];
        }
    } else {
        DDLogVerbose(@"Sense %@ is already connected", [[self sense] name]);
        completion (nil);
    }
}

/**
 * Obtain LGCharacteristic objects that match the characteristicIds specified.  On completion, the
 * response in the completion block will be a NSDictionary with the characteristicId as the key and
 * the value being the LGCharacteristic object.
 *
 * To obtain such characteristics, this method will connect to the initialized device, scan for the
 * device service and then retrieve the matching characteristics.
 *
 * @param characteristicIds: a set of characteristicIds to retrieve
 * @param completion: the block to call upon completion
 */
- (void)characteristicsFor:(NSSet*)characteristicIds completion:(SENSenseCompletionBlock)completion {
    [self characteristicsForServiceId:kSENSenseServiceID
                    characteristicIds:characteristicIds
                           completion:completion];
}

/**
 * Discover characteristics for the specified serviceId.  Upon completion, the
 * characteristics will be returned in a dictionary where key is the id of the
 * characteristic and value is an instance of LGCharacteristic.  If an error
 * is encountered, response will be nil and an NSError is returned instead.
 * @param serviceUUID:       the service UUID to discover
 * @param characteristicIds: a set of characteristicIds that the service broadcasts
 * @param completion:        the block to invoke when done
 */
- (void)characteristicsForServiceId:(NSString*)serviceUUID
                  characteristicIds:(NSSet*)characteristicIds
                         completion:(SENSenseCompletionBlock)completion {
    if (!completion) return; // even if we do stuff, what would it be for?
    if ([characteristicIds count] == 0) {
        completion (nil, [NSError errorWithDomain:kSENSenseErrorDomain
                                             code:SENSenseManagerErrorCodeInvalidArgument
                                         userInfo:nil]);
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [self connectThen:^(NSError *error) {
        if (error != nil) {
            completion (nil, [NSError errorWithDomain:kSENSenseErrorDomain
                                                 code:SENSenseManagerErrorCodeConnectionFailed
                                             userInfo:nil]);
            return;
        }
        
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        LGPeripheral* peripheral = [[strongSelf sense] peripheral];
        CBUUID* serviceId = [CBUUID UUIDWithString:serviceUUID];
        [peripheral discoverServices:@[serviceId] completion:^(NSArray *services, NSError *error) {
            if (error != nil || [services count] != 1) {
                completion (nil, error?error:[NSError errorWithDomain:kSENSenseErrorDomain
                                                                 code:SENSenseManagerErrorCodeUnexpectedResponse
                                                             userInfo:nil]);
                return;
            }
            
            LGService* lgService = [services firstObject];
            [lgService discoverCharacteristicsWithCompletion:^(NSArray *characteristics, NSError *error) {
                if (error != nil) {
                    
                    completion (nil, error);
                    return;
                }
                NSMutableDictionary* abilities = [NSMutableDictionary dictionaryWithCapacity:2];
                NSString* uuid = nil;
                for (LGCharacteristic* characteristic in characteristics) {
                    uuid = [[characteristic UUIDString] uppercaseString];
                    if ([characteristicIds containsObject:uuid]) {
                        [abilities setValue:characteristic forKey:uuid];
                    }
                }
                completion (abilities, nil);
            }];
        }];
    }];
}

- (void)characteristics:(SENSenseCompletionBlock)completion {
    [self characteristicsFor:[NSMutableSet setWithObjects:kSENSenseCharacteristicInputId,
                                                          kSENSenseCharacteristicResponseId,
                                                          nil]
                  completion:completion];
}

- (void)failWithBlock:(SENSenseFailureBlock)failure andCode:(SENSenseManagerErrorCode)code {
    if (failure) {
        failure ([NSError errorWithDomain:kSENSenseErrorDomain
                                     code:code
                                 userInfo:nil]);
    }
}

#pragma mark - (Private) Sending Data

- (SENSenseMessageBuilder*)messageBuilderWithType:(SENSenseMessageType)type {
    SENSenseMessageBuilder* builder = [[SENSenseMessageBuilder alloc] init];
    [builder setType:type];
    [builder setVersion:kSENSenseMessageVersion];
    return builder;
}

/**
 * Format the SENSenseMessage in to HELLO BLE PACKET FORMAT where data is divided
 * in to packets with max size kSENSensePacketSize.  Each packet is stored in
 * order in an array and returned.
 * @param message: a sense message to format
 * @return a sorted array of hello ble packets
 */
- (NSArray*)blePackets:(SENSenseMessage*)message {
    NSInteger initialPayloadSize = kSENSensePacketSize - 2;
    NSInteger additionalPacketSize = kSENSensePacketSize - 1;
    NSData* payload = [message data];
    NSInteger totalPayloadSize = [payload length];
    NSInteger addlPacketSize = MAX(0, totalPayloadSize- initialPayloadSize);
    
    double packets = ceil((double)addlPacketSize / (additionalPacketSize));
    uint8_t numberOfPackets = (uint8_t)(1 + packets);
    
    NSMutableArray* helloBlePackets = [NSMutableArray array];
    NSMutableData* packetData = nil;
    int bytesWritten = 0;
    
    for (uint8_t packetNumber = 0; packetNumber < numberOfPackets; packetNumber++) {
        packetData = [NSMutableData data];
        NSInteger payloadSize = additionalPacketSize; // first byte should always be a sequence number
        
        if (packetNumber == 0) {
            payloadSize = initialPayloadSize;
            uint8_t seq = 0;
            [packetData appendData:[NSData dataWithBytes:&seq
                                                  length:sizeof(seq)]];
            [packetData appendData:[NSData dataWithBytes:&numberOfPackets
                                                  length:sizeof(numberOfPackets)]];
        } else {
            [packetData appendData:[NSData dataWithBytes:&packetNumber
                                                  length:sizeof(packetNumber)]];
        }
        
        uint8_t actualSize = MIN(totalPayloadSize - bytesWritten, payloadSize);
        uint8_t partial[actualSize];
        [payload getBytes:&partial range:NSMakeRange(bytesWritten, actualSize)];
        
        [packetData appendBytes:partial length:actualSize];
        [helloBlePackets addObject:packetData];
        
        bytesWritten += actualSize;
    }
    
    DDLogVerbose(@"protobuf message %@ with size %ld", helloBlePackets, (long)bytesWritten);
    
    return helloBlePackets;
}

/**
 * Send a message to the initialized Sense through the main service.
 * @param command: the command to send
 * @param timeout: time in seconds before operation fails with timeout error
 * @param success: the success callback when command was sent
 * @param failure: the failure callback called when command failed
 */
- (void)sendMessage:(SENSenseMessage*)message
            timeout:(NSTimeInterval)timeout
             update:(SENSenseUpdateBlock)update
            success:(SENSenseSuccessBlock)success
            failure:(SENSenseFailureBlock)failure {
    
    __block LGPeripheral* peripheral = [[self sense] peripheral];
    if (peripheral == nil) {
        return [self failWithBlock:failure andCode:SENSenseManagerErrorCodeNoDeviceSpecified];
    }
    
    DDLogVerbose(@"sending message of type %u", [message type]);
    
    __weak typeof(self) weakSelf = self;
    [self characteristics:^(id response, NSError *error) {
        if (error != nil) {
            if (failure) failure (error);
            return;
        }
        
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        LGCharacteristic* writer = [response valueForKey:kSENSenseCharacteristicInputId];
        LGCharacteristic* reader = [response valueForKey:kSENSenseCharacteristicResponseId];
        if (writer == nil || reader == nil) {
            return [strongSelf failWithBlock:failure
                                     andCode:SENSenseManagerErrorCodeUnexpectedResponse];
        }
        
        NSArray* packets = [strongSelf blePackets:message];
        
        if ([packets count] > 0) {
            DDLogVerbose(@"# of packets being sent %ld", [packets count]);
            __block NSMutableArray* allPackets = nil;
            __block NSNumber* totalPackets = nil;
            __block typeof(reader) blockReader = reader;
            
            NSString* cbKey = [self cacheMessageCallbacks:update success:success failureBlock:^(NSError *error) {
                if (failure) failure (error);
                [blockReader setNotifyValue:NO completion:nil];
            }];
            [strongSelf scheduleMessageTimeOut:timeout withKey:cbKey];
            
            [reader setNotifyValue:YES completion:^(NSError *error) {
                if (error != nil) {
                    if (failure) failure (error);
                    return;
                }
                [strongSelf sendPackets:packets
                                   from:0
                          throughWriter:writer
                                success:nil
                                failure:^(NSError *error) {
                                    DDLogVerbose(@"message failed to send unsuccessfully with error %@, unsubscribing", error);
                                    [blockReader setNotifyValue:NO completion:nil];
                                    [strongSelf fireFailureMsgCbWithCbKey:cbKey andError:error];
                                }];
            } onUpdate:^(NSData *data, NSError *error) {
                [strongSelf handleResponseUpdate:data
                                           error:error
                                  forMessageType:[message type]
                                      allPackets:&allPackets
                                    totalPackets:&totalPackets
                                         success:^(id response) {
                                             SENSenseUpdateBlock updateBlock = [strongSelf messageUpdateCallbacks][cbKey];
                                             // if there's no update block or there is one and block tells us to finish
                                             if (!updateBlock || (updateBlock && updateBlock(response))) {
                                                 DDLogVerbose(@"message response received, unsubscribing");
                                                 [blockReader setNotifyValue:NO completion:nil];
                                                 [strongSelf fireSuccessMsgCbWithCbKey:cbKey andResponse:response];
                                             } else {
                                                 DDLogVerbose(@"partial message response received, waiting for next set");
                                                 // cannot nil out the allPackets array b/c that will deallocate the instance
                                                 // in the block and messages will be sent to a deallocated instance
                                                 [allPackets removeAllObjects];
                                                 totalPackets = @(1);
                                             }
                                         } failure:^(NSError *error) {
                                             DDLogVerbose(@"handling message response encountered error %@, unsubscribing", error);
                                             [blockReader setNotifyValue:NO completion:nil];
                                             [strongSelf fireFailureMsgCbWithCbKey:cbKey andError:error];
                                         }];
            }];

        } else {
            DDLogWarn(@"# of packets from message is 0");
            [strongSelf failWithBlock:failure andCode:SENSenseManagerErrorCodeInvalidCommand];
        }

    }];
}

- (NSString*)cacheMessageCallbacks:(SENSenseUpdateBlock)updateBlock
                           success:(SENSenseSuccessBlock)successBlock
                      failureBlock:(SENSenseFailureBlock)failureBlock {
    NSString* key = [[NSUUID UUID] UUIDString];
    
    if (updateBlock) {
        [[self messageUpdateCallbacks] setValue:[updateBlock copy] forKey:key];
    }
    
    if (successBlock) {
        [[self messageSuccessCallbacks] setValue:[successBlock copy] forKey:key];
    }
    
    if (failureBlock) {
        [[self messageFailureCallbacks] setValue:[failureBlock copy] forKey:key];
    }
    
    return key;
}

- (void)clearMessageCallbacksForKey:(NSString*)key {
    if (key != nil) {
        [[self messageFailureCallbacks] removeObjectForKey:key];
        [[self messageSuccessCallbacks] removeObjectForKey:key];
        [[self messageUpdateCallbacks] removeObjectForKey:key];
    }
}

- (void)fireSuccessMsgCbWithCbKey:(NSString*)cbKey andResponse:(id)response {
    [self cancelMessageTimeOutWithCbKey:cbKey];
    if (cbKey != nil) {
        SENSenseSuccessBlock callback = [[self messageSuccessCallbacks] valueForKey:cbKey];
        if (callback) {
            DDLogVerbose(@"firing success callback");
            callback (response);
        }
        [self clearMessageCallbacksForKey:cbKey];
    }
}

- (void)fireFailureMsgCbWithCbKey:(NSString*)cbKey andError:(NSError*)error {
    [self cancelMessageTimeOutWithCbKey:cbKey];
    if (cbKey != nil) {
        SENSenseFailureBlock callback = [[self messageFailureCallbacks] valueForKey:cbKey];
        if (callback) {
            DDLogVerbose(@"firing failure callback");
            callback (error);
        }
        [self clearMessageCallbacksForKey:cbKey];
    }
}

/**
 * Send all packets, recursively, starting from the specified index in the array.
 * If an error was encountered, recusion will stop and failure block will be called
 * right away.
 *
 * @param packets: the packets to send
 * @param from: index of the packet to send in this iteration
 * @param type: the type of the sense message
 * @param writer: the input characteristic
 * @param reader: the output characteristic
 * @param success: the block to call when all packets have been sent
 * @param failure: the block to call if any error was encountered along the way
 */
- (void)sendPackets:(NSArray*)packets
               from:(NSInteger)index
      throughWriter:(LGCharacteristic*)writer
            success:(SENSenseSuccessBlock)success
            failure:(SENSenseFailureBlock)failure {
    
    if (![self isConnected]) {
        [self failWithBlock:failure andCode:SENSenseManagerErrorCodeConnectionFailed];
        return;
    }
    
    if (index < [packets count]) {
        NSData* data = packets[index];
        __weak typeof(self) weakSelf = self;
        [writer writeValue:data completion:^(NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            
            if (error != nil) {
                if (failure) failure (error);
                return;
            }
            
            if (strongSelf) {
                [strongSelf sendPackets:packets
                                   from:index+1
                          throughWriter:writer
                                success:success
                                failure:failure];
            }

        }];
    } else {
        if (success) success (nil);
    }
}

#pragma mark - (Private) Reading Response

- (SENSenseManagerErrorCode)errorCodeFrom:(ErrorType)senseErrorType {
    SENSenseManagerErrorCode code = SENSenseManagerErrorCodeNone;
    switch (senseErrorType) {
        case ErrorTypeTimeOut:
            code = SENSenseManagerErrorCodeTimeout;
            break;
        case ErrorTypeDeviceAlreadyPaired:
            code = SENSenseManagerErrorCodeSenseAlreadyPaired;
            break;
        case ErrorTypeInternalOperationFailed:
            code = SENSenseManagerErrorCodeSenseInternalFailure;
            break;
        case ErrorTypeDeviceNoMemory:
            code = SENSenseManagerErrorCodeSenseOutOfMemory;
            break;
        case ErrorTypeDeviceDatabaseFull:
            code = SENSenseManagerErrorCodeSenseDbFull;
            break;
        case ErrorTypeNetworkError:
            code = SENSenseManagerErrorCodeSenseNetworkError;
            break;
        case ErrorTypeNoEndpointInRange:
            code = SENSenseManagerErrorCodeWifiNotInRange;
            break;
        case ErrorTypeWlanConnectionError:
            code = SENSenseManagerErrorCodeWLANConnection;
            break;
        case ErrorTypeFailToObtainIp:
            code = SENSenseManagerErrorCodeFailToObtainIP;
            break;
        default:
            code = SENSenseManagerErrorCodeUnexpectedResponse;
            break;
    }
    return code;
}

- (SENWiFiConnectionState)wiFiStateFromMessgage:(SENSenseMessage*)message {
    SENWiFiConnectionState state = SENWiFiConnectionStateUnknown;
    if ([message hasWifiState]) {
        switch ([message wifiState]) {
            case WiFiStateIpObtained:
                state = SENWiFiConnectionStateConnected;
                break;
            case WiFiStateWlanConnected:
                state = SENWiFiConnectionStateNoInternet;
                break;
            case WiFiStateWlanConnecting:
                state = SENWiFiConnectionStateConnecting;
                break;
            case WiFiStateNoWlanConnected:
                state = SENWifiConnectionStateDisconnected;
                break;
            default:
                break;
        }
    }
    return state;
}

/**
 * Handle response from Sense until it's done sending data back.  Since response
 * will likely be split in to multiple packets, we need to append all data as they
 * arrive until all packets are received.
 *
 * @param data:         the data from 1 update of a response
 * @param error:        any error that may have come from the response
 * @param type:         the type of the message this response is meant for
 * @param allPackets:   the address to the storage holding all data responses
 * @param totalPackets: the address to an object that holds the value of the 
 *                      total packets determined from the first update/packet
 * @param success:      the block to invoke when all updates completed successfully
 * @param failure:      the block to invoke when any update reported an error or
 *                      if the full response is not what was expected for the type
 */
- (void)handleResponseUpdate:(NSData*)data
                       error:(NSError*)error
              forMessageType:(SENSenseMessageType)type
                  allPackets:(NSMutableArray**)allPackets
                totalPackets:(NSNumber**)totalPackets
                     success:(SENSenseSuccessBlock)success
                     failure:(SENSenseFailureBlock)failure {
    
    uint8_t packet[[data length]];
    [data getBytes:&packet length:kSENSensePacketSize];
    if (sizeof(packet) >= 2 && error == nil) {
        uint8_t seq = packet[0];
        if (seq == 0) {
            *totalPackets = @(packet[1]);
            *allPackets = [NSMutableArray arrayWithCapacity:[*totalPackets intValue]];
        }
        
        [*allPackets addObject:data];
        
        if ([*totalPackets intValue] == 1 || [*totalPackets intValue] - 1 == seq) {
            NSError* parseError = nil;
            SENSenseMessage* responseMsg = [self messageFromBlePackets:*allPackets error:&parseError];
            if (parseError != nil || [responseMsg hasError]) {
                NSInteger code
                    = parseError != nil
                    ? [parseError code]
                    : SENSenseManagerErrorCodeUnexpectedResponse;
                [self failWithBlock:failure andCode:code];
            } else {
                if (success) success (responseMsg);
            }
        } // else, wait for next update
    } else {
        [self failWithBlock:failure andCode:SENSenseManagerErrorCodeUnexpectedResponse];
    }
}

/**
 * Parse the data back in to a SENSenseMessage protobuf object, following the
 * HELLO BLE PACKET FORMAT.
 * @param packets: all hello ble format packets returned from Sense
 * @param error:   a pointer to an error object that will be set if one encountered.
 * @return         a SENSenseMessage
 */
- (SENSenseMessage*)messageFromBlePackets:(NSArray*)packets error:(NSError**)error {
    SENSenseMessage* response = nil;
    SENSenseManagerErrorCode errCode = SENSenseManagerErrorCodeNone;
    NSMutableData* actualPayload = [NSMutableData data];
    
    int index = 0;
    for (NSData* packetData in packets) {
        int offset = index == 0 ? 2 : 1;
        long packetLength = [packetData length] - offset;
        uint8_t payloadPacket[packetLength];
        long length = sizeof(payloadPacket);
        [packetData getBytes:&payloadPacket range:NSMakeRange(offset, packetLength)];
        [actualPayload appendBytes:payloadPacket length:length];
        index++;
    }
    
    @try {
        response = [SENSenseMessage parseFromData:actualPayload];
        if ([response hasError]) {
            errCode = [self errorCodeFrom:[response error]];
            DDLogVerbose(@"ble response has an error with device code %ld", errCode);
        }
    } @catch (NSException *exception) {
        DDLogWarn(@"parsing ble protobuf message encountered exception %@", exception);
        errCode = SENSenseManagerErrorCodeUnexpectedResponse;
    }
    
    if (errCode != SENSenseManagerErrorCodeNone && error != NULL) {
        *error = [NSError errorWithDomain:kSENSenseErrorDomain
                                     code:errCode
                                 userInfo:nil];
    }
    return response;
}

#pragma mark - (Private) Timeout

- (void)scheduleMessageTimeOut:(NSTimeInterval)timeOutInSecs withKey:(NSString*)key {
    NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:timeOutInSecs
                                                      target:self
                                                    selector:@selector(timedOut:)
                                                    userInfo:key
                                                     repeats:NO];
    [[self messageTimeoutTimers] setValue:timer forKey:key];
}

- (void)cancelMessageTimeOutWithCbKey:(NSString*)cbKey {
    NSTimer* timer = [[self messageTimeoutTimers] objectForKey:cbKey];
    [timer invalidate];
    [[self messageTimeoutTimers] removeObjectForKey:cbKey];
}

- (void)timedOut:(NSTimer*)timer {
    DDLogVerbose(@"Sense operation timed out");
    NSString* cbKey = [timer userInfo];
    if (cbKey != nil) {
        [self cancelMessageTimeOutWithCbKey:cbKey];
        
        SENSenseFailureBlock failureCb = [[self messageFailureCallbacks] valueForKey:cbKey];
        if (failureCb) {
            failureCb ([NSError errorWithDomain:kSENSenseErrorDomain
                                           code:SENSenseManagerErrorCodeTimeout
                                       userInfo:nil]);
        }
        
        [self clearMessageCallbacksForKey:cbKey];
    }
}

#pragma mark - Pairing

/**
 * Pairing with Sense requires a simple subscription to the output characteristic,
 * which will force authorization from the device wanting to pair
 *
 * @param success: the block to invoke when pairing completed successfully
 * @param failure: the block to invoke when an error was encountered
 */
- (void)pair:(SENSenseSuccessBlock)success
     failure:(SENSenseFailureBlock)failure {
    __weak typeof(self) weakSelf = self;
    DDLogVerbose(@"attempting to pair with Sense");
    [self characteristicsFor:[NSSet setWithObject:kSENSenseCharacteristicResponseId]
                  completion:^(id response, NSError *error) {
                      __strong typeof(weakSelf) strongSelf = weakSelf;
                      if (!strongSelf) return;
                      
                      NSDictionary* readWrite = response;
                      __weak LGCharacteristic* reader = [readWrite valueForKey:kSENSenseCharacteristicResponseId];
                      
                      if (reader == nil) {
                          return [strongSelf failWithBlock:failure
                                                   andCode:SENSenseManagerErrorCodeUnexpectedResponse];
                      }
                      
                      NSString* cbKey = [strongSelf cacheMessageCallbacks:nil success:success failureBlock:^(NSError *error) {
                          __strong typeof(reader) strongReader = reader;
                          if (strongReader) {
                              [strongReader setNotifyValue:NO completion:nil];
                          }
                          
                          if (failure) failure (error);
                      }];
                      [strongSelf scheduleMessageTimeOut:kSENSenseDefaultTimeout withKey:cbKey];
                      
                      [reader setNotifyValue:YES completion:^(NSError *error) {
                          __strong typeof(reader) strongReader = reader;
                          if (!strongReader) return;
                          
                          [strongReader setNotifyValue:NO completion:nil];
                          
                          if (error != nil) {
                              DDLogVerbose(@"failed to pair with Sense with error %@", error);
                              [strongSelf fireFailureMsgCbWithCbKey:cbKey andError:error];
                          } else {
                              DDLogVerbose(@"Sense paired successfully");
                              [strongSelf fireSuccessMsgCbWithCbKey:cbKey andResponse:nil];
                          }

                      }];
                  }];
}

- (void)enablePairingMode:(BOOL)enable
                  success:(SENSenseSuccessBlock)success
                  failure:(SENSenseFailureBlock)failure {
    DDLogVerbose(@"%@ pairing mode on Sense", enable?@"enabling":@"disabling");
    
    SENSenseMessageType type
        = enable
        ? SENSenseMessageTypeSwitchToPairingMode
        : SENSenseMessageTypeSwitchToNormalMode;

    [self sendMessage:[[self messageBuilderWithType:type] build]
              timeout:kSENSenseDefaultTimeout
               update:nil
              success:success
              failure:failure];
}

- (void)removeOtherPairedDevices:(SENSenseSuccessBlock)success
                         failure:(SENSenseFailureBlock)failure {
    DDLogVerbose(@"removing paired devices from Sense");
    SENSenseMessageType type = SENSenseMessageTypeEreasePairedPhone;
    [self sendMessage:[[self messageBuilderWithType:type] build]
              timeout:kSENSenseDefaultTimeout
               update:nil
              success:success
              failure:failure];
}

- (void)linkAccount:(NSString*)accountAccessToken
            success:(SENSenseSuccessBlock)success
            failure:(SENSenseFailureBlock)failure {
    DDLogVerbose(@"linking account %@... through Sense", accountAccessToken?[accountAccessToken substringToIndex:3]:@"");
    SENSenseMessageType type = SENSenseMessageTypePairSense;
    SENSenseMessageBuilder* builder = [self messageBuilderWithType:type];
    [builder setAccountId:accountAccessToken];
    [self sendMessage:[builder build]
              timeout:kSENSenseDefaultTimeout
               update:nil
              success:success
              failure:failure];
}

- (void)pairWithPill:(NSString*)accountAccessToken
             success:(SENSenseSuccessBlock)success
             failure:(SENSenseFailureBlock)failure {
    DDLogVerbose(@"linking account %@... through Sense", accountAccessToken?[accountAccessToken substringToIndex:3]:@"");
    SENSenseMessageType type = SENSenseMessageTypePairPill;
    SENSenseMessageBuilder* builder = [self messageBuilderWithType:type];
    [builder setAccountId:accountAccessToken];
    [self sendMessage:[builder build]
              timeout:kSENSensePillPairTimeout
               update:nil
              success:success
              failure:failure];
}

#pragma mark - Wifi

- (void)setWiFi:(NSString*)ssid
       password:(NSString*)password
   securityType:(SENWifiEndpointSecurityType)securityType
        success:(SENSenseSuccessBlock)success
        failure:(SENSenseFailureBlock)failure {
    
    DDLogVerbose(@"setting wifi on Sense with ssid %@", ssid);
    SENSenseMessageType type = SENSenseMessageTypeSetWifiEndpoint;
    SENSenseMessageBuilder* builder = [self messageBuilderWithType:type];
    [builder setSecurityType:securityType];
    [builder setWifiSsid:ssid];
    [builder setWifiPassword:password];
    [self sendMessage:[builder build]
              timeout:kSENSenseSetWifiTimeout
               update:nil
              success:success
              failure:failure];
}

- (void)scanForWifiNetworks:(SENSenseSuccessBlock)success
                    failure:(SENSenseFailureBlock)failure {
    
    DDLogVerbose(@"scanning for wifi networks Sense can see");
    SENSenseMessageType type = SENSenseMessageTypeStartWifiscan;
    SENSenseMessageBuilder* builder = [self messageBuilderWithType:type];
    
    __block NSMutableArray* wifis = [NSMutableArray array];
    [self sendMessage:[builder build]
              timeout:kSENSenseScanWifiTimeout
               update:^BOOL(SENSenseMessage* updateResponse) {
                   if ([updateResponse wifisDetected]) {
                       [[updateResponse wifisDetected] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                           DDLogVerbose(@"found wifi %@", [((SENWifiEndpoint*)obj) ssid]);
                           [wifis addObject:obj];
                       }];
                   }
                   return [updateResponse type] == SENSenseMessageTypeStopWifiscan;
               }
              success:^(SENSenseMessage* response) {
                  [[response wifisDetected] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                      DDLogVerbose(@"found wifi %@", [((SENWifiEndpoint*)obj) ssid]);
                      [wifis addObject:obj];
                  }];
                  [wifis sortUsingComparator:^NSComparisonResult(SENWifiEndpoint* wifi1, SENWifiEndpoint* wifi2) {
                      NSComparisonResult result = NSOrderedSame;
                      if ([wifi1 rssi] < [wifi2 rssi]) {
                          result = NSOrderedDescending;
                      } else if ([wifi1 rssi] > [wifi2 rssi]) {
                          result = NSOrderedAscending;
                      }
                      return result;
                  }];
                  if (success) success (wifis);
              }
              failure:failure];
}

- (void)getConfiguredWiFi:(void(^)(NSString* ssid, SENWiFiConnectionState state))success
                  failure:(SENSenseFailureBlock)failure {
    
    if (!success) {
        if (failure) failure ([NSError errorWithDomain:kSENSenseErrorDomain
                                                  code:SENSenseManagerErrorCodeInvalidArgument
                                              userInfo:nil]);
        return;
    }
    
    DDLogVerbose(@"retrieving configured wifi on Sense");
    __weak typeof(self) weakSelf = self;
    SENSenseMessageType type = SENSenseMessageTypeGetWifiEndpoint;
    SENSenseMessageBuilder* builder = [self messageBuilderWithType:type];
    [self sendMessage:[builder build]
              timeout:kSENSenseDefaultTimeout
               update:nil
              success:^(SENSenseMessage* response) {
                  // connection state and protobuf wifiState maps 1:1, but with more caller
                  // friendly naming
                  __strong typeof(weakSelf) strongSelf = weakSelf;
                  SENWiFiConnectionState state = SENWiFiConnectionStateUnknown;
                  if (strongSelf) {
                      state = [strongSelf wiFiStateFromMessgage:response];
                  }

                  DDLogVerbose(@"wifi %@ is in state %ld", [response wifiSsid], state);
                  success ([response wifiSsid], state);
                  
              }
              failure:failure];
}

#pragma mark - Factory Reset

- (void)resetToFactoryState:(SENSenseSuccessBlock)success
                    failure:(SENSenseFailureBlock)failure {
    
    DDLogVerbose(@"resetting Sense to factory state");
    SENSenseMessageType type = SENSenseMessageTypeFactoryReset;
    SENSenseMessageBuilder* builder = [self messageBuilderWithType:type];
    [self sendMessage:[builder build]
              timeout:kSENSenseDefaultTimeout
               update:nil
              success:success
              failure:failure];
}

#pragma mark - Signal Strength / RSSI

- (void)currentRSSI:(SENSenseSuccessBlock)success
            failure:(SENSenseFailureBlock)failure {
    DDLogVerbose(@"getting current Sense rssi value");
    __weak typeof(self) weakSelf = self;
    [self connectThen:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            if (failure) failure (error);
        } else if (strongSelf) {
            [strongSelf readPeripheralRSSI:success failure:failure];
        }
    }];
}

- (void)readPeripheralRSSI:(SENSenseSuccessBlock)success
                   failure:(SENSenseFailureBlock)failure {
    [[[self sense] peripheral] readRSSIValueCompletion:^(NSNumber *RSSI, NSError *error) {
        if (error) {
            if (failure) failure (error);
        } else if (success) {
            DDLogVerbose(@"Sense's rssi value is %ld", [RSSI longValue]);
            success (RSSI);
        }
    }];
}

#pragma mark - Connections

- (void)disconnectFromSense {
    DDLogVerbose(@"manually disconnecting from Sense");
    if  ([self isConnected]) {
        __weak typeof(self) weakSelf = self;
        [[[self sense] peripheral] disconnectWithCompletion:^(NSError *error) {
            if (error == nil) {
                DDLogVerbose(@"disconnected from Sense");
            }
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf setValid:NO];
        }];
    }
}

- (void)listenForUnexpectedDisconnects {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    if ([self disconnectNotifyObserver] != nil) {
        [center removeObserver:[self disconnectNotifyObserver]];
    }
    
    __weak typeof(self) weakSelf = self;
    self.disconnectNotifyObserver =
        [center addObserverForName:kLGPeripheralDidDisconnect
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                            __strong typeof(weakSelf) strongSelf = weakSelf;
                            if (!strongSelf) return;
                            
                            DDLogVerbose(@"Sense disconnected unexpectedly");
                            // if peripheral is disconnected, it is removed from
                            // scannedPeripherals in LGCentralManager, which causes
                            // the reference to SENSense's peripheral to not be
                            // recognized.  This is actually not a logic problem
                            // from the library, but also the behavior in CoreBluetooth
                            [strongSelf setValid:NO];
                            
                            id errorObject = [[note userInfo] valueForKey:@"error"];
                            if ([errorObject isKindOfClass:[NSError class]]) {
                                DDLogVerbose(@"error from disconnect: %@", errorObject);
                            }
                            for (NSString* observerId in [strongSelf disconnectObservers]) {
                                SENSenseFailureBlock block = [[strongSelf disconnectObservers] valueForKey:observerId];
                                block ([NSError errorWithDomain:kSENSenseErrorDomain
                                                           code:SENSenseManagerErrorCodeUnexpectedDisconnect
                                                       userInfo:nil]);
                            }
                        }];
}

- (NSString*)observeUnexpectedDisconnect:(SENSenseFailureBlock)block {
    if ([self disconnectObservers] == nil) {
        [self setDisconnectObservers:[NSMutableDictionary dictionary]];
    }
    NSString* observerId = [[NSUUID UUID] UUIDString];
    [[self disconnectObservers] setValue:[block copy] forKey:observerId];
    return observerId;
}

- (void)removeUnexpectedDisconnectObserver:(NSString*)observerId {
    if (observerId != nil) {
        [[self disconnectObservers] removeObjectForKey:observerId];
    }
}

#pragma mark - Cleanup

- (void)dealloc {
    for (NSTimer* timer in [[self messageTimeoutTimers] allValues]) {
        [timer invalidate];
    }
    
    if ([self isConnected]) {
        [[[self sense] peripheral] disconnectWithCompletion:nil];
    }
    
    if ([self disconnectNotifyObserver]) {
        [[NSNotificationCenter defaultCenter] removeObserver:[self disconnectNotifyObserver]];
    }
}

@end
