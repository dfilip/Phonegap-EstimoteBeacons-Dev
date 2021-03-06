#import <Cordova/CDV.h>
#import "EstimoteBeacons.h"
#import "ESTBeaconManager.h"

@interface EstimoteBeacons () <ESTBeaconManagerDelegate,ESTBeaconDelegate>

@property (nonatomic, strong) ESTBeaconManager* beaconManager;

@end


@implementation EstimoteBeacons

@synthesize onEnter;
@synthesize onExit;
@synthesize placeholderUUID;

- (EstimoteBeacons*)pluginInitialize
{
    NSLog(@"Estimote: init");
    // craete manager instance

    self.placeholderUUID = @"B9407F30-F5F8-466E-AFF9-25556B57FE6D";

    self.beaconManager = [[ESTBeaconManager alloc] init];
    self.beaconManager.delegate = self;
    self.beaconManager.avoidUnknownStateBeacons = YES;


    //ios8 location stuff
    @try{
        [self.beaconManager requestAlwaysAuthorization];
    }@catch(NSException *e){
        NSLog(e.reason);
    }
    


    // create sample region object (you can additionaly pass major / minor values)
    self.currentRegion = [[ESTBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:self.placeholderUUID] identifier:self.placeholderUUID];

    // region watchers
    self.regionWatchers = [[NSMutableDictionary alloc] init];

    return self;
}

#pragma mark - Start monitoring methods

- (void)startEstimoteBeaconsDiscoveryForRegion:(CDVInvokedUrlCommand*)command {
    NSLog(@"Estimote: startEstimoteBeaconsDiscoveryForRegion");
    // stop existing discovery/ranging
    [self.beaconManager stopEstimoteBeaconDiscovery];
    [self.beaconManager stopRangingBeaconsInRegion:self.currentRegion];

    // start discovery
    [self.beaconManager startEstimoteBeaconsDiscoveryForRegion:self.currentRegion];

    // respond to JS with OK
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}


- (void)startRangingBeaconsInRegion:(CDVInvokedUrlCommand*)command {
    // stop existing discovery/ranging
    [self.beaconManager stopEstimoteBeaconDiscovery];
    [self.beaconManager stopRangingBeaconsInRegion:self.currentRegion];

    // start ranging
    [self.beaconManager startRangingBeaconsInRegion:self.currentRegion];

    // respond to JS with OK
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

- (void)startMonitoringForRegion:(CDVInvokedUrlCommand*)command
{
    NSLog(@"Estimote: startMonitoringForRegion");
    //NSLog(@"Estimote: AuthorizationStatus:%@",[self.beaconManager authorizationStatus]);

    NSString* regionid = [command.arguments objectAtIndex:0];
    id major = [command.arguments objectAtIndex:1];
    id minor = [command.arguments objectAtIndex:2];
    self.onEnter = [command.arguments objectAtIndex:4];
    self.onExit = [command.arguments objectAtIndex:5];

    if([self.regionWatchers objectForKey:regionid] != nil) {
        NSLog(@"Estimote: Region with given ID is already monitored.");
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Region with given ID is already monitored."] callbackId:command.callbackId];
    } else {
        ESTBeaconRegion* region;

        if((NSNull *)major == [NSNull null] || (NSNull *)minor == [NSNull null]) {
            //region = [[ESTBeaconRegion alloc] initRegionWithIdentifier:regionid];
            region = [[ESTBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:regionid] identifier:regionid];
        } else {
            region = [[ESTBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:regionid] major:[major intValue] minor:[minor intValue] identifier:regionid];
        }

        region.notifyEntryStateOnDisplay = [command.arguments objectAtIndex:3];

        [self.beaconManager startMonitoringForRegion:region];
        [self.beaconManager requestStateForRegion:region];

        [self.regionWatchers setObject:command.callbackId  forKey:regionid];
    }
    NSLog(@"Estimote: Finished call - startMonitoringForRegion");
}

#pragma mark - Stop monitoring methods

- (void)stopEsimoteBeaconsDiscoveryForRegion:(CDVInvokedUrlCommand*)command {
    // stop existing discovery/ranging
    [self.beaconManager stopEstimoteBeaconDiscovery];

    // respond to JS with OK
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

- (void)stopRangingBeaconsInRegion:(CDVInvokedUrlCommand*)command {
    // stop existing discovery/ranging
    [self.beaconManager stopRangingBeaconsInRegion:self.currentRegion];

    // respond to JS with OK
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}


- (void)stopMonitoringForRegion:(CDVInvokedUrlCommand*)command
{
    NSString* regionid = [command.arguments objectAtIndex:0];
    ESTBeaconRegion* regionFound = nil;

    for(ESTBeaconRegion* region in self.regionWatchers) {
        if([region.identifier compare:regionid]) {
            regionFound = region;
            break;
        }
    }

    if(regionFound != nil) {
        [self.beaconManager stopMonitoringForRegion:regionFound];

        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Region with given ID not found."] callbackId:command.callbackId];
    }
}

#pragma mark - Get beacons methods

- (void)getBeacons:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSMutableArray* output = [NSMutableArray array];

        if([self.beacons count] > 0)
        {
            //convert list of beacons to a an array of simple property-value objects
            for (id beacon in self.beacons) {
                [output addObject:[self beaconToDictionary:beacon]];
            }
        }

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:output];

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)getBeaconByIdx:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSInteger idx = [[command.arguments objectAtIndex:0] intValue];

    if (idx < [self.beacons count] && idx >= 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                     messageAsDictionary:[self beaconToDictionary:[self.beacons objectAtIndex:idx]]];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid index."];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getClosestBeacon:(CDVInvokedUrlCommand*)command
{
    if ([self.beacons count] > 0) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                             messageAsDictionary:[self beaconToDictionary:[self.beacons objectAtIndex:0]]]
                                    callbackId:command.callbackId];
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
    }
}

- (void)getConnectedBeacon:(CDVInvokedUrlCommand*)command
{
    if(self.connectedBeacon != nil) {
        [self.commandDelegate runInBackground:^{
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                 messageAsDictionary:[self beaconToDictionary:self.connectedBeacon]] callbackId:command.callbackId];
        }];
    } else {
        //no connected beacons
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"There are no connected beacons."] callbackId:command.callbackId];
    }
}

#pragma mark - Virtual Beacon methods

- (void)startVirtualBeacon:(CDVInvokedUrlCommand*)command
{
    NSInteger major = [[command.arguments objectAtIndex:0] intValue];
    NSInteger minor = [[command.arguments objectAtIndex:1] intValue];
    NSString* beaconid = [command.arguments objectAtIndex:2];

    //[self.beaconManager startAdvertisingWithMajor:major withMinor:minor withIdentifier:beaconid];
    [self.beaconManager startAdvertisingWithProximityUUID:[[NSUUID alloc] initWithUUIDString:beaconid] major:major minor:minor identifier:beaconid];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

- (void)stopVirtualBeacon:(CDVInvokedUrlCommand*)command
{
    [self.beaconManager stopAdvertising];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
}

#pragma mark - Connect to methods

- (void)connectToBeacon:(CDVInvokedUrlCommand*)command
{
    NSInteger major = [[command.arguments objectAtIndex:0] intValue];
    NSInteger minor = [[command.arguments objectAtIndex:1] intValue];
    ESTBeacon* foundBeacon = nil;

    if([self.beacons count] > 0)
    {
        //convert list of beacons to a an array of simple property-value objects
        for (id beacon in self.beacons) {
            ESTBeacon* currentBeacon = beacon;
            NSNumber* currentMajor = currentBeacon.major;
            NSNumber* currentMinor = currentBeacon.minor;

            if(currentMajor == nil) {
                currentMajor = currentBeacon.major;
            }
            if(currentMinor == nil) {
                currentMinor = currentBeacon.minor;
            }

            if(currentMajor == nil || currentMajor == nil) {
                continue;
            }

            if(minor == [currentMinor intValue] && major == [currentMajor intValue]) {
                foundBeacon = beacon;
            }
        }
    }

    if(foundBeacon) {
        if(foundBeacon.connectionStatus == ESTBeaconConnectionStatusConnected) {
            //beacon is already connected
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Beacon is already connected."] callbackId:command.callbackId];
        } else if(foundBeacon.connectionStatus == ESTBeaconConnectionStatusConnecting) {
            //some callback is already waiting for connection
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"App is already waiting for connection."] callbackId:command.callbackId];
        } else {
            //everything OK - try connecting
            self.connectionCallbackId = command.callbackId;
            self.connectedBeacon = foundBeacon;
            foundBeacon.delegate = self;
            [foundBeacon connect];
        }
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Beacon not found."] callbackId:command.callbackId];
    }
}

- (void)connectToBeaconByMacAddress:(CDVInvokedUrlCommand*)command
{
    NSString* macAddress = [command.arguments objectAtIndex:0];
    ESTBeacon* foundBeacon = nil;

    if([self.beacons count] > 0)
    {
        //convert list of beacons to a an array of simple property-value objects
        for (id beacon in self.beacons) {
            ESTBeacon* currentBeacon = beacon;
            NSString* currentMac = currentBeacon.macAddress;

            if(currentMac == nil) {
                continue;
            }

            if([currentMac isEqualToString:macAddress]) {
                foundBeacon = beacon;
            }
        }
    }

    if(foundBeacon) {
        if(foundBeacon.connectionStatus == ESTBeaconConnectionStatusConnected) {
            //beacon is already connected
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Beacon is already connected."] callbackId:command.callbackId];
        } else if(foundBeacon.connectionStatus == ESTBeaconConnectionStatusConnecting) {
            //some callback is already waiting for connection
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"App is already waiting for connection."] callbackId:command.callbackId];
        } else {
            //everything OK - try connecting
            self.connectionCallbackId = command.callbackId;
            self.connectedBeacon = foundBeacon;
            foundBeacon.delegate = self;
            [foundBeacon connect];
        }
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Beacon not found."] callbackId:command.callbackId];
    }
}

#pragma mark - Disconnect from Beacon

- (void)disconnectFromBeacon:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* pluginResult = nil;

        if(self.connectedBeacon != nil) {
            [self.connectedBeacon disconnect];

            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsDictionary:[self beaconToDictionary:self.connectedBeacon]];

            self.connectedBeacon = nil;
        } else {
            //no connected beacons
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"There are no connected beacons."];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

#pragma mark - Change attributes of beacon

- (void)setAdvIntervalOfConnectedBeacon:(CDVInvokedUrlCommand*)command
{
    if(self.connectedBeacon != nil) {
        NSNumber* advInterval = [command.arguments objectAtIndex:0];

        if(advInterval != nil && [advInterval intValue] >= 80 && [advInterval intValue] <= 3200) {


            [self.connectedBeacon writeAdvInterval:[advInterval shortValue] completion:^(unsigned short value, NSError *error) {
                if(error != nil) {
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription] callbackId:command.callbackId];
                } else {
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                         messageAsDictionary:[self beaconToDictionary:self.connectedBeacon]] callbackId:command.callbackId];
                }

            }];

        } else {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid advInterval value."] callbackId:command.callbackId];
        }
    } else {
        //no connected beacons
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"There are no connected beacons."] callbackId:command.callbackId];
    }
}

- (void)setPowerOfConnectedBeacon:(CDVInvokedUrlCommand*)command
{
    if(self.connectedBeacon != nil) {
        NSNumber* power = [command.arguments objectAtIndex:0];
        ESTBeaconPower powerLevel;

        switch ([power intValue]) {
            case -40:
                powerLevel = ESTBeaconPowerLevel1;
                break;
            case -20:
                powerLevel = ESTBeaconPowerLevel2;
                break;
            case -16:
                powerLevel = ESTBeaconPowerLevel3;
                break;
            case -12:
                powerLevel = ESTBeaconPowerLevel4;
                break;
            case -8:
                powerLevel = ESTBeaconPowerLevel5;
                break;
            case -4:
                powerLevel = ESTBeaconPowerLevel6;
                break;
            case 0:
                powerLevel = ESTBeaconPowerLevel7;
                break;
            case 4:
                powerLevel = ESTBeaconPowerLevel8;
                break;
        }

        if(powerLevel || powerLevel == ESTBeaconPowerLevel7) {
            [self.connectedBeacon writePower:powerLevel completion:^(ESTBeaconPower value, NSError *error) {
                if(error != nil) {
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription] callbackId:command.callbackId];
                } else {
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                         messageAsDictionary:[self beaconToDictionary:self.connectedBeacon]] callbackId:command.callbackId];
                }
            }];
        } else {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid power value."] callbackId:command.callbackId];
        }
    } else {
        //no connected beacons
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"There are no connected beacons."] callbackId:command.callbackId];
    }
}

- (void)updateFirmwareOfConnectedBeacon:(CDVInvokedUrlCommand*)command
{
    if(self.connectedBeacon != nil) {
        [self.connectedBeacon updateFirmwareWithProgress:^(NSInteger value, NSString *description, NSError *error){
            if(error == nil) {
                self.firmwareUpdateProgress = description;
            }

        } completion:^(NSError *error){
            if(error == nil) {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                     messageAsDictionary:[self beaconToDictionary:self.connectedBeacon]] callbackId:command.callbackId];
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription] callbackId:command.callbackId];
            }

            self.firmwareUpdateProgress = nil;
        }];
    } else {
        //no connected beacons
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"There are no connected beacons."] callbackId:command.callbackId];
    }
}

- (void)getFirmwareUpdateProgress:(CDVInvokedUrlCommand*)command
{
    if(self.firmwareUpdateProgress != nil) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                 messageAsString:self.firmwareUpdateProgress] callbackId:command.callbackId];
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No beacon is being updated right now."] callbackId:command.callbackId];
    }
}

#pragma mark - Helpers

- (NSMutableDictionary*)beaconToDictionary:(ESTBeacon*)beacon
{
    NSMutableDictionary* props = [NSMutableDictionary dictionaryWithCapacity:16];
    NSNumber* major = beacon.major;
    NSNumber* minor = beacon.minor;
    NSNumber* rssi = [NSNumber numberWithInt:beacon.rssi];

    if(major == nil) {
        major = beacon.major;
    }
    if(minor == nil) {
        minor = beacon.minor;
    }
    if(rssi == nil) {
        rssi = [NSNumber numberWithInt:beacon.rssi];
    }

    [props setValue:beacon.batteryLevel forKey:@"batteryLevel"];
    [props setValue:beacon.firmwareVersion forKey:@"firmwareVersion"];
    [props setValue:beacon.hardwareVersion forKey:@"hardwareVersion"];
    [props setValue:major forKey:@"major"];
    [props setValue:minor forKey:@"minor"];
    [props setValue:beacon.advInterval forKey:@"advInterval"];
    [props setValue:beacon.description forKey:@"description"];
    [props setValue:rssi forKey:@"rssi"];
    [props setValue:beacon.debugDescription forKey:@"debugDescription"];
    [props setValue:beacon.macAddress forKey:@"macAddress"];
    [props setValue:beacon.measuredPower forKey:@"measuredPower"];
    [props setValue:[NSNumber numberWithBool:(bool)beacon.connectionStatus] forKey:@"isConnected"];

    if(beacon.power != nil) {
        [props setValue:[NSNumber numberWithChar:[beacon.power charValue]] forKey:@"power"];
    }

    if(beacon != nil) {
        [props setValue:beacon.distance forKey:@"distance"];
        [props setValue:[NSNumber numberWithInt:beacon.proximity] forKey:@"proximity"];

        if(beacon.proximityUUID != nil) {
            [props setValue:beacon.proximityUUID.UUIDString forKey:@"proximityUUID"];
        }
    }


    return props;
}

#pragma mark - Beacon Manager delegate methods.

- (void)beaconManager:(ESTBeaconManager *)manager
   didDiscoverBeacons:(NSArray *)beacons
             inRegion:(ESTBeaconRegion *)region
{

    NSLog(@"Estimote: didDiscoverBeacons");

    @try{
        self.beacons = beacons;

        NSMutableArray* output = [NSMutableArray array];

        if([self.beacons count] > 0)
        {
            //convert list of beacons to a an array of simple property-value objects
            for (id beacon in self.beacons) {
                [output addObject:[self beaconToDictionary:beacon]];
            }
        }

        //NSMutableDictionary *bcns = [beacons mutableCopy];
        NSError *error;

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:output
                                                       options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                         error:&error];
        if (! jsonData) {
            NSLog(@"Estimote: %@", error);
        } else {

            NSLog(@"Estimote: about to create jsonStr");
            NSLog(@"Estimote: jsonData: %@",jsonData);
            NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

            NSString * jsCallBack = [NSString stringWithFormat:@"%@(%@);", self.onEnter, jsonStr];
            NSLog(@"jsCallBack: %@",jsCallBack);
            [self.webView stringByEvaluatingJavaScriptFromString:jsCallBack];
            NSLog(@"Estimote: didDiscoverBeacons");
        }

    }
    @catch(NSException *e){
        NSLog(@"Estimote Error: %@", e.reason);
    }




    
}

-(void)beaconManager:(ESTBeaconManager *)manager
     didEnterRegion:(ESTBeaconRegion *)region
{
    NSLog(@"Estimote: didEnterRegion");
    [manager startEstimoteBeaconsDiscoveryForRegion:region];
    NSLog(@"Estimote: called startEstimoteBeaconsDiscoveryForRegion");
}


-(void)beaconManager:(ESTBeaconManager *)manager
     didRangeBeacons:(NSArray *)beacons
            inRegion:(ESTBeaconRegion *)region
{
    NSLog(@"Estimote: didRangeBeacons");
    self.beacons = beacons;
}

- (void)beaconConnectionDidFail:(ESTBeacon *)beacon withError:(NSError *)error {
    if(self.connectionCallbackId != nil) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                 messageAsString:error.localizedDescription]
                                    callbackId:self.connectionCallbackId];
    }

    self.connectionCallbackId = nil;
    self.connectedBeacon = nil;
}

- (void)beaconConnectionDidSucceeded:(ESTBeacon *)beacon {
    if(self.connectionCallbackId != nil) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                             messageAsDictionary:[self beaconToDictionary:self.connectedBeacon]]
                                    callbackId:self.connectionCallbackId];
    }

    self.connectionCallbackId = nil;
}

- (void)beaconDidDisconnectWithError:(NSError*)error {
    if(self.connectionCallbackId == nil) {
        self.connectedBeacon = nil;
    }
}

- (void)beaconManager:(ESTBeaconManager *)manager didDetermineState:(CLRegionState)state forRegion:(ESTBeaconRegion *)region {
    NSString *result = nil;

    switch(state) {
        case CLRegionStateUnknown:
            result = @"unknown";
            break;
        case CLRegionStateInside:
            result = @"enter";
            break;
        case CLRegionStateOutside:
            result = @"exit";
            break;
        default:
            result = @"unknown";
    }

    NSLog(@"Estimote: didDetermineState: %@",result);
    NSLog(@"Estimote: region=%@",(NSString*)region.proximityUUID);

    NSString* callbackId = [self.regionWatchers objectForKey:region.identifier];

    if(callbackId != nil) {
        NSMutableDictionary* props = [NSMutableDictionary dictionaryWithCapacity:4];

        [props setValue:region.identifier forKey:@"id"];
        [props setValue:region.major forKey:@"major"];
        [props setValue:region.minor forKey:@"minor"];
        [props setValue:result forKey:@"action"];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:props];
        [result setKeepCallback:[NSNumber numberWithBool:YES]];

        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

@end