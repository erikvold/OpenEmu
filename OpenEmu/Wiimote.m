/*
 Copyright (c) 2012, OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the OpenEmu Team nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#import "Wiimote.h"

#import <IOBluetooth/objc/IOBluetoothL2CAPChannel.h>
#import <IOBluetooth/objc/IOBluetoothDevice.h>
#import <IOBluetooth/objc/IOBluetoothSDPServiceRecord.h>
#import <IOBluetooth/objc/IOBluetoothSDPDataElement.h>

NSString *const OEWiimoteDidConnectNotificationName = @"OEWiimoteDidConnectNotificationName";
NSString *const OEWiimoteDidDisconnectNotificationName = @"OEWiimoteDidDisconnectNotificationName";

typedef unsigned char darr[];
typedef enum {
	kWiiRemoteTwoButton				= 0x0001,
	kWiiRemoteOneButton				= 0x0002,
	kWiiRemoteBButton					= 0x0004,
	kWiiRemoteAButton					= 0x0008,
	kWiiRemoteMinusButton				= 0x0010,
	kWiiRemoteHomeButton				= 0x0080,
	kWiiRemoteLeftButton				= 0x0100,
	kWiiRemoteRightButton				= 0x0200,
	kWiiRemoteDownButton				= 0x0400,
	kWiiRemoteUpButton					= 0x0800,
	kWiiRemotePlusButton				= 0x1000,
	
	kWiiNunchukZButton					= 0x01,
	kWiiNunchukCButton					= 0x02,
	
	kWiiClassicControllerUpButton		= 0x0001,
	kWiiClassicControllerLeftButton		= 0x0002,
	kWiiClassicControllerZRButton		= 0x0004,
	kWiiClassicControllerXButton		= 0x0008,
	kWiiClassicControllerAButton		= 0x0010,
	kWiiClassicControllerYButton		= 0x0020,
	kWiiClassicControllerBButton		= 0x0040,
	kWiiClassicControllerZLButton		= 0x0080,
    // 0x0100 is unsued
	kWiiClassicControllerRButton		= 0x0200,
	kWiiClassicControllerPlusButton		= 0x0400,
	kWiiClassicControllerHomeButton		= 0x0800,
	kWiiClassicControllerMinusButton	= 0x1000,
	kWiiClassicControllerLButton		= 0x2000,
	kWiiClassicControllerDownButton		= 0x4000,
	kWiiClassicControllerRightButton	= 0x8000
} WiiButtonBitMask;

typedef enum {
    kWiiNunchukPressedTreshhold = 10,
    kWiiNunchukMaxValue = 255
} WiiNunchukParameters;

typedef enum {
	kWiiExpansionNunchuck = 0x0000,
	kWiiExpansionClassicController = 0x0101,
} WiiExpansionIdentifier;

@interface Wiimote ()
{
    IOBluetoothDevice* _btDevice;
	IOBluetoothL2CAPChannel * _ichan;
	IOBluetoothL2CAPChannel * _cchan;
	
	WiiIRModeType irMode;
	
    UInt16 lastWiimoteButtonReport;
    UInt8 lastNunchuckButtonReport;
    UInt8 lastNunchuckVirtualJoystickButtonReport;
    
    UInt16 lastClassicControllerButtonReport;
}
@property BOOL statusReportRequested;
@property float batteryLevel;
@property WiiExpansionType expansionType;

- (void)setDevice:(IOBluetoothDevice*)newDev;
# pragma mark - Data Handling -
- (void)writeData:(const unsigned char*)data at:(unsigned long)address length:(size_t)length;
- (void)readData:(unsigned long)address length:(unsigned short)length;
- (void)sendCommand:(const unsigned char*)data length:(size_t)length;

- (IOBluetoothL2CAPChannel *)openL2CAPChannelWithPSM:(BluetoothL2CAPPSM)psm delegate:(id)delegate;
@end

@implementation Wiimote
@synthesize irSensorEnabled, motionSensorEnabled, rumbleActivated;

# pragma mark -
- (Wiimote*)init
{
	self = [super init];
	
	if (self != nil)
    {
		LED1Illuminated = YES;
		LED2Illuminated = YES;
		LED3Illuminated = YES;
		LED4Illuminated = YES;
		
		rumbleActivated = NO;
		irSensorEnabled = NO;
		motionSensorEnabled = NO;
		
		expansionPortEnabled   = YES;
		expansionPortAttached  = NO;
        expansionType          = WiiExpansionNotConnected;
        
		speakerEnabled = NO;	// sound is not implemented yet
		speakerMuted   = NO;	// sound is not implemented yet
        
        lastWiimoteButtonReport = 0;
        lastNunchuckButtonReport = 0;
        lastClassicControllerButtonReport = 0;
    }
	return self;
}

- (Wiimote*)initWithDevice:(IOBluetoothDevice*)newDevice
{
	self = [self init];
	if(self != nil)
    {
		[self setDevice:newDevice];
	}
	
	return self;
}
# pragma mark -
# pragma mark - Connection
- (void)setDevice:(IOBluetoothDevice*)newDev
{
	if(connected) // disconnect when changing device
		[self disconnect];
	
	_btDevice = newDev;
}

- (void)connect
{
	if(connected || _btDevice == nil)
		return;
	
	connected = YES;
	
	// Open Channels and
	// Allow bluetooth stack to 'settle', wait few milliseconds
	_cchan = [self openL2CAPChannelWithPSM:kBluetoothL2CAPPSMHIDControl delegate:self];
	usleep (20000);
	_ichan = [self openL2CAPChannelWithPSM:kBluetoothL2CAPPSMHIDInterrupt delegate:self];
	usleep (20000);
	
	if(_cchan!=nil && _ichan!=nil)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:OEWiimoteDidConnectNotificationName object:self];
    }
	else
    {
		[_cchan closeChannel];
		[_ichan closeChannel];
                
		connected = NO;
	}
	
    if([_btDevice getLastServicesUpdate] != NULL)
        [_btDevice performSDPQuery:nil];
    
	[self requestStatus];
	usleep (10000);
	
	[self syncConfig];
	[self syncLEDAndRumble];
}

- (void)disconnect
{
	if(!connected)
		return;
	
	connected = NO;
	
	// Close Channel
	[_cchan closeChannel];
	[_ichan closeChannel];
    
    if(_btDevice)
        [_btDevice closeConnection];
	
    [[NSNotificationCenter defaultCenter] postNotificationName:OEWiimoteDidDisconnectNotificationName object:self];
}
@synthesize connected;
# pragma mark -
- (void)requestStatus
{
	unsigned char cmd[] = {0x15, 0x00};
	[self sendCommand:cmd length:2];
    statusReportRequested = YES;
}
#pragma mark - Device Info -
- (NSString*)nameOrAddress
{
    return [_btDevice nameOrAddress];
}

- (NSString*)address
{
    return [_btDevice addressString];
}

- (NSNumber*)productID
{
    return @(0x0306);
}
- (NSNumber*)vendorID
{
    return @(0x057E);
}
- (NSNumber*)locationID
{
    return @(0);
}
# pragma mark -
# pragma mark Wiimote Configuration
- (void)syncConfig
{
	// Set the report type the Wiimote should send.
	unsigned char cmd[] = {0x12, 0x02, 0x30}; // Just buttons.
	
	if (irSensorEnabled)
    {
        NSLog(@"ir enabled");
		cmd[2] = expansionPortEnabled ? 0x36 : 0x33;	// Buttons, 10 IR Bytes, 9 Extension Bytes
		irMode = expansionPortEnabled ? kWiiIRModeBasic : kWiiIRModeExtended;
		
		// Set IR Mode
		// I don't think it should be here ...
		[self writeData:(darr){ irMode } at:0x04B00033 length:1];
		usleep(10000);
	}
    else
    {
		cmd[2] = expansionPortEnabled ? 0x34 : 0x30;	// Buttons, 19 Extension Bytes
	}
    
	[self sendCommand:cmd length:3];
}
- (void)syncLEDAndRumble
{
	unsigned char cmd[] = {0x11, 0x00};
	if (rumbleActivated)
        cmd[1] |= 0x01;
	if (LED1Illuminated)
        cmd[1] |= 0x10;
	if (LED2Illuminated)
        cmd[1] |= 0x20;
	if (LED3Illuminated)
        cmd[1] |= 0x40;
	if (LED4Illuminated)
        cmd[1] |= 0x80;
	
	[self sendCommand:cmd length:2];
}
#pragma mark - LEDs
- (void)setLED1:(BOOL)flag1 LED2:(BOOL)flag2 LED3:(BOOL)flag3 LED4:(BOOL)flag4
{
	LED1Illuminated = flag1;
	LED2Illuminated = flag2;
	LED3Illuminated = flag3;
	LED4Illuminated = flag4;
}
@synthesize LED1Illuminated, LED2Illuminated, LED3Illuminated, LED4Illuminated;
#pragma mark -
@synthesize batteryLevel;
#pragma mark - Expansion Port -
- (void)initializeExpansionPort
{
    // Initializing expansion port based on http://wiibrew.org/wiki/Wiimote/Extension_Controllers#The_New_Way
    unsigned char data = 0x55;
    [self writeData:&data at:0x04A400F0 length:1];
    usleep(1000);
    
    data = 0x00;
    [self writeData:&data at:0x04A400FB length:1];
    usleep(1000);
    
    [self readData:0x04A400FE length:2]; // read expansion type
}
@synthesize expansionType, expansionPortAttached, expansionPortEnabled;
# pragma mark - Sound -
- (void)playSound:(NSSound*)theSound
{
	NSLog(@"playSound: Sound is not implemented yet!");
}
- (void)setSpeakerEnabled:(BOOL)flag
{
	NSLog(@"setSpeakerEnabled: Sound is not implemented yet!");
	speakerEnabled = flag;
}
- (void)setSpeakerMuted:(BOOL)flag
{
	NSLog(@"setSpeakerMuted: Sound is not implemented yet!");
	speakerMuted = flag;
}

- (BOOL)speakerEnabled
{
	NSLog(@"speakerEnabled: Sound is not implemented yet!");
	return speakerEnabled;
}

- (void)toggleMute
{
	NSLog(@"toggleMute: Sound is not implemented yet!");
	speakerMuted = !speakerMuted;
}

- (BOOL)speakerMuted
{
	// DLog(@"speakerMuted: Sound is not implemented yet!");
	return speakerMuted;
}
@synthesize speakerEnabled, speakerMuted;
# pragma mark -
# pragma mark Data Handling
- (void)writeData:(const unsigned char*)data at:(unsigned long)address length:(size_t)length
{
	unsigned char cmd [22];
	
	if (length > 16)
		; // DLog (@"Error! Trying to write more than 16 bytes of data (length=%lu)", length);
	
	memset (cmd, 0, 22);
	memcpy (cmd + 6, data, length);
	
	// register write header
	cmd[0] = 0x16;
	
	// write address
	cmd[1] = (address >> 24) & 0xFF;
	cmd[2] = (address >> 16) & 0xFF;
	cmd[3] = (address >>  8) & 0xFF;
	cmd[4] = (address >>  0) & 0xFF;
	
	// data length
	cmd[5] = length;
	
	// and of course the vibration flag, as usual
	if (rumbleActivated)
		cmd[1] |= 0x01;
	
	[self sendCommand:cmd length:22];
}

- (void)readData:(unsigned long)address length:(unsigned short)length
{
	unsigned char cmd[7];
	unsigned long addr = address;
	unsigned short len = length;
	
	cmd[0] = 0x17; // read memory
	
	// address
	cmd[1] = (addr >> 24) & 0xFF;  // bit 2 being set indicates read from control registers, 0 indicates EEPROM Memory
	cmd[2] = (addr >> 16) & 0xFF;
	cmd[3] = (addr >>  8) & 0xFF;
	cmd[4] = (addr >>  0) & 0xFF;
	
	// Number of bytes to read
	cmd[5] = (len >> 8) & 0xFF;
	cmd[6] = (len >> 0) & 0xFF;
	
	if (rumbleActivated)
		cmd[1] |= 0x01;
	
	[self sendCommand:cmd length:7];
}

- (void)sendCommand:(const unsigned char*)data length:(size_t)length
{
	if(!connected)
		return;
	
	unsigned char buf[40];
	memset(buf, 0, 40);
	
	buf[0] = 0x52;
	memcpy(buf+1, data, length);
	if (buf[1] == 0x16)
        length = 23;
	else
        length++;
    
	int i;
	IOReturn ret = kIOReturnSuccess;
	for (i=0; i < 10 ; i++)
    {
		ret = [_cchan writeSync:buf length:length];
		if (ret != kIOReturnSuccess)
        {
            usleep (10000);
        }
		else break;
	}
	
	if(ret != kIOReturnSuccess)
    {
		// DLog(@"Did Wiimote Disconnect? - we might need to disconnect");
	}
}
@synthesize statusReportRequested;
# pragma mark -
- (void)handleDataReport:(unsigned char *) dp length:(size_t) dataLength
{
	// wiimote buttons
    if(dp[1] != 0x3d)
    {
        UInt16 buttonData = ((short)dp[2] << 8) + dp[3];
        [self parseWiiRemoteButtonData:buttonData];
    }
    
    // Expansion Port
    switch(dp[1])
    {
		case 0x34:
			[self handleExtensionReport:dp length:dataLength startByte:4];
			break;
		case 0x35:
			[self handleExtensionReport:dp length:dataLength startByte:7];
			break;
		case 0x36:
			[self handleExtensionReport:dp length:dataLength startByte:14];
			break;
		case 0x37:
			[self handleExtensionReport:dp length:dataLength startByte:17];
			break;
        case 0x3d:
			[self handleExtensionReport:dp length:dataLength startByte:2];
			break;
	}
}
- (void)handleExtensionReport:(unsigned char *) dp length:(size_t)dataLength startByte:(char)startByte
{
    if(![self expansionPortEnabled] || ![self expansionPortAttached])
        return;
    
    switch ([self expansionType])
    {
        case WiiExpansionNunchuck:
            [self parseNunchuckJoystickData: ((short)dp[startByte] << 8) + dp[startByte+1]];
            [self parseNunchuckButtonData: dp[startByte+5]];
            break;
        case WiiExpansionClassicController:;
            UInt16 data = ((short)dp[startByte+4] << 8) + dp[startByte+5];
            [self parseClassicControllerButtonData:data];
            break;
        default:
            break;
    }
}

- (void)parseWiiRemoteButtonData:(UInt16) data
{
    UInt16 buttonChanges = data ^ lastWiimoteButtonReport;
    lastWiimoteButtonReport = data;
    
    // One, Two, A, B Buttons:
	if (buttonChanges & kWiiRemoteOneButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteOneButton state:(data & kWiiRemoteOneButton)!=0];
	}
    
    if (buttonChanges & kWiiRemoteTwoButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteTwoButton state:(data & kWiiRemoteTwoButton)!=0];
	}
    
    if (buttonChanges & kWiiRemoteAButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteAButton state:(data & kWiiRemoteAButton)!=0];
	}
    
    if (buttonChanges & kWiiRemoteBButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteBButton state:(data & kWiiRemoteBButton)!=0];
	}
    
    // +, -, Home Buttons:
    if (buttonChanges & kWiiRemoteMinusButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteMinusButton state:(data & kWiiRemoteMinusButton)!=0];
	}
    
    if (buttonChanges & kWiiRemoteHomeButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteHomeButton state:(data & kWiiRemoteHomeButton)!=0];
	}
    
    if (buttonChanges & kWiiRemotePlusButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemotePlusButton state:(data & kWiiRemotePlusButton)!=0];
	}
    
    // D-Pad Buttons:
    if (buttonChanges & kWiiRemoteUpButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteUpButton state:(data & kWiiRemoteUpButton)!=0];
	}
    
    if (buttonChanges & kWiiRemoteDownButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteDownButton state:(data & kWiiRemoteDownButton)!=0];
	}
    
    if (buttonChanges & kWiiRemoteLeftButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteLeftButton state:(data & kWiiRemoteLeftButton)!=0];
	}
    
    if (buttonChanges & kWiiRemoteRightButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiRemoteRightButton state:(data & kWiiRemoteRightButton)!=0];
	}
}

- (void)parseNunchuckJoystickData:(UInt16)analogData
{   
    UInt8 yAxisData = analogData & 0xff;
    UInt8 xAxisData = (analogData >> 8) & 0xff;
    [[self handler] dispatchEventWithWiiJoystick:WiiNunchukJoyStick tiltX:xAxisData tiltY:yAxisData];
}

- (void)parseNunchuckButtonData:(UInt8)data
{
    UInt8 buttonChanges = data ^ lastNunchuckButtonReport;
    lastNunchuckButtonReport = data;
    NSLog(@"Nun?");
    if (buttonChanges & kWiiNunchukCButton)
    {
        NSLog(@"\tNun C");
        [[self handler] dispatchEventWithWiiButton:WiiNunchukCButton state:(data & kWiiNunchukCButton)!=0];
	}
    
    if (buttonChanges & kWiiNunchukZButton)
    {
        NSLog(@"\tNun Z");
        [[self handler] dispatchEventWithWiiButton:WiiNunchukZButton state:(data & kWiiNunchukZButton)!=0];
	}
}

- (void)parseClassicControllerButtonData:(UInt16)data
{
    UInt16 buttonChanges = data ^ lastClassicControllerButtonReport;
    lastClassicControllerButtonReport = data;
    
    if (buttonChanges & kWiiClassicControllerXButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerXButton state:(data & kWiiClassicControllerXButton)!=0];
	}
    
    if (buttonChanges & kWiiClassicControllerYButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerYButton state:(data & kWiiClassicControllerYButton)!=0];
	}
    
    if (buttonChanges & kWiiClassicControllerAButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerAButton state:(data & kWiiClassicControllerAButton)!=0];
	}
    
	if (buttonChanges & kWiiClassicControllerBButton)
    {
		[[self handler] dispatchEventWithWiiButton:WiiClassicControllerBButton state:(data & kWiiClassicControllerBButton)!=0];
	}
    
    
	if (buttonChanges & kWiiClassicControllerLButton)
    {
		[[self handler] dispatchEventWithWiiButton:WiiClassicControllerLButton state:(data & kWiiClassicControllerLButton)!=0];
	}
    
	if (buttonChanges & kWiiClassicControllerRButton)
    {
		[[self handler] dispatchEventWithWiiButton:WiiClassicControllerRButton state:(data & kWiiClassicControllerRButton)!=0];
	}
    
    
	if (buttonChanges & kWiiClassicControllerRButton)
    {
		[[self handler] dispatchEventWithWiiButton:WiiClassicControllerRButton state:(data & kWiiClassicControllerRButton)!=0];
	}
    
	if (buttonChanges & kWiiClassicControllerZRButton)
    {
		[[self handler] dispatchEventWithWiiButton:WiiClassicControllerZRButton state:(data & kWiiClassicControllerZRButton)!=0];
	}
    
    
    // +, -, Home Buttons:
    if (buttonChanges & kWiiClassicControllerMinusButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerMinusButton state:(data & kWiiClassicControllerMinusButton)!=0];
    }
    
    if (buttonChanges & kWiiClassicControllerHomeButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerHomeButton state:(data & kWiiClassicControllerHomeButton)!=0];
    }
    
    if (buttonChanges & kWiiClassicControllerPlusButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerPlusButton state:(data & kWiiClassicControllerPlusButton)!=0];
    }
    
    // D-Pad Buttons:
    if (buttonChanges & kWiiClassicControllerUpButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerUpButton state:(data & kWiiClassicControllerUpButton)!=0];
    }
    
    if (buttonChanges & kWiiClassicControllerDownButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerDownButton state:(data & kWiiClassicControllerDownButton)!=0];
    }
    
    if (buttonChanges & kWiiClassicControllerLeftButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerLeftButton state:(data & kWiiClassicControllerLeftButton)!=0];
    }
    
    if (buttonChanges & kWiiClassicControllerRightButton)
    {
        [[self handler] dispatchEventWithWiiButton:WiiClassicControllerRightButton state:(data & kWiiClassicControllerRightButton)!=0];
    }
}

# pragma mark -
# pragma mark Response Handler
- (void)handleWriteResponse:(unsigned char *)dp length:(size_t)dataLength
{
    if(dataLength > 5)
    {
        switch (dp[5])
        {
            case 0x00:
                // DLog(@"Write %0x - Success", dp[4]);
                break;
            case 0x03:
                // DLog(@"Write %0x - Error", dp[4]);
                break;
            default:
                // DLog(@"Write %0x - Unkown", dp[4]);
                break;
        }
    }
}

- (void)handleRAMData:(unsigned char *)dp length:(size_t)dataLength
{
    unsigned short addr = (dp[5] * 256) + dp[6];
    if (addr == 0x00FE) // Response to expansion type request
    {
        UInt16 identifier = ((dp[7]&0xFF) << 8)|(dp[8]&0xFF);
        WiiExpansionType connectedExpansion = WiiExpansionNotConnected;
        if(!(dp[4] & 0x0F))
        {
            switch (identifier)
            {
                case kWiiExpansionNunchuck:
                    connectedExpansion = WiiExpansionNunchuck;
                    break;
                case kWiiExpansionClassicController:
                    connectedExpansion = WiiExpansionClassicController;
                    break;
                default:
                    connectedExpansion = WiiExpansionUnkown;
                    break;
            }
        }
        if (connectedExpansion != self.expansionType)
        {
            self.expansionType = connectedExpansion;
            expansionPortAttached = (connectedExpansion != WiiExpansionNotConnected);
            // TODO: implement expansion port changes when needed
            [self syncConfig];
        }
    }
}

- (void)handleStatusReport:(unsigned char *) dp length:(size_t)dataLength
{
	if(!statusReportRequested)
        [self syncConfig];
    else
        statusReportRequested = NO;
    
	self.batteryLevel =  (double) dp[7]/(double) 0xC0; // C0 = fully charged.
    
    if ((dp[4] & 0x02) && !expansionPortAttached)  // Expansion port changed
    {
        self.expansionType = WiiExpansionNotInitialized;
        // TODO: implement expansion port changes when needed
        [self initializeExpansionPort];
    }
    else if(expansionPortAttached)
    {
        expansionPortAttached = NO;
        // TODO: implement expansion port changes when needed
    }
}
# pragma mark -
# pragma mark BluetoothChannel Delegate methods
- (void) l2capChannelClosed:(IOBluetoothL2CAPChannel*) l2capChannel
{
	if (l2capChannel == _cchan)
		_cchan = nil;
	
	if (l2capChannel == _ichan)
		_ichan = nil;
	
	[self disconnect];
}

- (void)l2capChannelData:(IOBluetoothL2CAPChannel*) l2capChannel data:(void *) dataPointer length:(size_t) dataLength
{
	unsigned char * dp = (unsigned char *) dataPointer;
    
	if (dp[1] == 0x20 && dataLength >= 8)
    {
		[self handleStatusReport:dp length:dataLength];
	}
    else if (dp[1] == 0x21) // read data response
    {
		[self handleRAMData:dp length:dataLength];
        [self handleDataReport:dp length:dataLength];
	}
    else if (dp[1] == 0x22) // Write data response
    {
		[self handleWriteResponse:dp length:dataLength];
        [self handleDataReport:dp length:dataLength];
	}
    else if ((dp[1] & 0xF0) == 0x30) // report contains button info
    {
        [self handleDataReport:dp length:dataLength];
	}
}

- (IOBluetoothL2CAPChannel *)openL2CAPChannelWithPSM:(BluetoothL2CAPPSM)psm delegate:(id)aDelegate
{
	IOBluetoothL2CAPChannel * channel = nil;
	
	// DLog(@"Open channel (PSM:%i) ...", psm);
	if ([_btDevice openL2CAPChannelSync:&channel withPSM:psm delegate:aDelegate] != kIOReturnSuccess)
    {
		// DLog (@"Could not open L2CAP channel (psm:%i)", psm);
		channel = nil;
		[self disconnect];
	}
    else
    {
		[channel setDelegate:self];
	}
	
	return channel;
}

@end