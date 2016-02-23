//
//  main.m
//  Lock screen when a USB token is removed. Wake the screen again on
//  re-insertion of the token.
//
//  Created by Christof Rath on 18.09.15.
//  Copyright © 2015 Christof Rath. All rights reserved.
//

#include <Foundation/Foundation.h>
#include <IOKit/usb/IOUSBLib.h>
#include <AppKit/AppKit.h>
#include "iTunes.h"

static BOOL wasITunesRunning = false;
static iTunesApplication *iTunes = 0;

static void lockOrUnlockScreen(CFBooleanRef doLock) {
	io_registry_entry_t ioRegistry = IORegistryEntryFromPath(kIOMasterPortDefault, kIOServicePlane ":/IOResources/IODisplayWrangler");
	kern_return_t kr;
	if (ioRegistry) {
		kr = IORegistryEntrySetCFProperty(ioRegistry, CFSTR("IORequestIdle"), doLock);
		IOObjectRelease(ioRegistry);
		if(kr) {
			NSLog(@"usb-lock: Failed to %@ the screens: 0x%x", doLock == kCFBooleanTrue ? @"lock" : @"unlock", kr);
		}
	}
}

static void stopITunesIfPlaying() {
	if ( [iTunes isRunning] ) {
		wasITunesRunning = [iTunes playerState] == iTunesEPlSPlaying;
		if ( wasITunesRunning ) {
			[iTunes playpause];
		}
	}
}

static void resumeITunes() {
	if ( [iTunes isRunning] && wasITunesRunning && [iTunes playerState] != iTunesEPlSPlaying ) {
		[iTunes playpause];
	}
}

static void tokenInsertCallback(void* refcon, io_iterator_t portIterator)
{
	BOOL match = false;
	while (IOIteratorNext(portIterator)) {
		match = true;
	};

	if (match) {
		lockOrUnlockScreen(kCFBooleanFalse);
		resumeITunes();
	}
}

static void tokenRemoveCallback(void* refcon, io_iterator_t portIterator)
{
	BOOL match = false;
	while (IOIteratorNext(portIterator)) {
		match = true;
	};

	if (match) {
		if( NSAlternateKeyMask & [NSEvent modifierFlags] ){
			NSLog(@"Prevent screen lock for pressed option key");
		} else {
			stopITunesIfPlaying();
			lockOrUnlockScreen(kCFBooleanTrue);
		}
	}
}

static int usage(char *program, char *error)
{
	if (error) {
		printf("Error: %s\n\n", error);
	}

	printf("Usage: %s vendorId [productId]\n", program);
	printf("  e.g. %s 0x1050\n\n", program);
	printf("  or:  %s config\n\n", program);
	return error == 0 ? 1 : 2;
}

static void listUSBDevice(int *i, io_service_t usbDevice, int *vArr, int *pArr) {
	io_name_t devicename;
	if (IORegistryEntryGetName(usbDevice, devicename) != KERN_SUCCESS) {
		NSLog(@"***Failed to get device name***");
		return;
	}

	CFNumberRef vendorId = (CFNumberRef) IORegistryEntrySearchCFProperty(usbDevice
																		 , kIOServicePlane
																		 , CFSTR("idVendor")
																		 , NULL
																		 , kIORegistryIterateRecursively | kIORegistryIterateParents);
	if(!CFNumberGetValue(vendorId, kCFNumberSInt32Type, vArr+(*i))) {
		NSLog(@"***CFNumber overflow***");
		return;
	}
	CFRelease(vendorId);

	CFNumberRef productId = (CFNumberRef) IORegistryEntrySearchCFProperty(usbDevice
																		  , kIOServicePlane
																		  , CFSTR("idProduct")
																		  , NULL
																		  , kIORegistryIterateRecursively | kIORegistryIterateParents);
	if(!CFNumberGetValue(productId, kCFNumberSInt32Type, pArr+1+(*i))) {
		NSLog(@"***CFNumber overflow***");
		return;
	}
	CFRelease(productId);

	CFStringRef vendorname = (CFStringRef) IORegistryEntrySearchCFProperty(usbDevice
																		   , kIOServicePlane
																		   , CFSTR("USB Vendor Name")
																		   , NULL
																		   , kIORegistryIterateRecursively | kIORegistryIterateParents);

	if (vendorname) {
		char* cVal = malloc(CFStringGetLength(vendorname) * sizeof(char));

		if (cVal) {
			if (CFStringGetCString(vendorname, cVal, CFStringGetLength(vendorname) + 1, kCFStringEncodingASCII)) {
				pArr[*i] = -1;
				vArr[(*i) + 1] = vArr[*i];
				printf("%2u: %-40s0x%04x   *\n", *i, cVal, vArr[*i]);
				(*i)++;
			}
			free(cVal);
		}
	}

	printf("%2u: %-40s0x%04x   0x%04x\n", *i, devicename, vArr[*i], pArr[*i]);
	(*i)++;
}

static void writePlist(CFStringRef prg, CFStringRef vID, CFStringRef pID) {
	NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity:3];
	NSArray *prgArgs = 0;

	if (pID == 0) {
		prgArgs = [NSArray arrayWithObjects: (__bridge id _Nonnull)(prg), vID, nil];
	} else {
		prgArgs = [NSArray arrayWithObjects: (__bridge id _Nonnull)(prg), vID, pID, nil];
	}

	[rootObj setObject:@"at.tugraz.iaik.usb-lock" forKey:@"Label"];
	[rootObj setObject:prgArgs forKey:@"ProgramArguments"];
	[rootObj setValue:[NSNumber numberWithBool:YES]	forKey:@"KeepAlive"];

#ifdef DEBUG
	NSError * error=nil;
	NSPropertyListFormat format=NSPropertyListXMLFormat_v1_0;
	NSData * data =  [NSPropertyListSerialization dataWithPropertyList:rootObj format:format options:NSPropertyListImmutable error:&error];
	NSLog(@"Plist =%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
#else
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString *librarayDirectory = [paths objectAtIndex:0];
	NSString *path = [librarayDirectory stringByAppendingPathComponent:@"LaunchAgents/at.tugraz.iaik.usb-lock.plist"];
	[rootObj writeToFile:path atomically:YES];
	printf("Start script successfully written.\nTo launch the service now call:\n\n  launchctl load %s\n\n", [path cStringUsingEncoding:NSUTF8StringEncoding]);
#endif
}

int main(int argc, char **argv)
{
	iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];

	io_iterator_t portIterator = 0;
	IONotificationPortRef notificationObject = 0;
	CFNumberRef vid_num = 0;
	CFNumberRef pid_num = 0;

	if (argc < 2 || argc > 3) {
		return usage(argv[0], 0);
	}

	if (strcmp(argv[1], "config") != 0) {
		NSLog(@"Parsing vendor ID: %s", argv[1]);
		int vid = EOF;
		if (sscanf(argv[1], "%x", &vid) != 1) {
			return usage(argv[0], "Failed to parse VendorId");
		}
		vid_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
	}

	if (argc == 3) {
		NSLog(@"Parsing product ID: %s", argv[2]);
		int pid = EOF;
		if (sscanf(argv[2], "%x", &pid) != 1) {
			return usage(argv[0], "Failed to parse ProductId");
		}
		pid_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
	}

	CFMutableDictionaryRef myUSBMatchDictionary = IOServiceMatching(kIOUSBDeviceClassName);

	if (vid_num == 0) { // install
		CFDictionarySetValue(myUSBMatchDictionary, CFSTR(kUSBVendorID), CFSTR("*"));
	} else {
		CFRetain(myUSBMatchDictionary); // Need to use it twice and IOServiceAddMatchingNotification() consumes a reference
		CFDictionarySetValue(myUSBMatchDictionary, CFSTR(kUSBVendorID), vid_num);
		CFRelease(vid_num);
	}

	if (pid_num == 0) {
		CFDictionarySetValue(myUSBMatchDictionary, CFSTR (kUSBProductID), CFSTR("*"));
	} else {
		CFDictionarySetValue(myUSBMatchDictionary, CFSTR (kUSBProductID), pid_num);
		CFRelease(pid_num);
	}

	notificationObject = IONotificationPortCreate(kIOMasterPortDefault);

	CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationObject), kCFRunLoopDefaultMode);

	if (vid_num == 0) { // install
		int vArr[100], pArr[100];

		IOServiceAddMatchingNotification(notificationObject, kIOMatchedNotification, myUSBMatchDictionary, 0, 0, &portIterator);
		io_service_t usbDevice;
		int i = 0;
		printf(" #  %-40sVendorID ProductID\n", "Name");
		printf("--------------------------------------------------------------\n");
		while ((usbDevice = IOIteratorNext(portIterator))) {
			listUSBDevice(&i, usbDevice, vArr, pArr);
			IOObjectRelease(usbDevice);
		}
		printf("\n");
		printf("Select your USB device: ");
		int n=-1;
		scanf("%d", &n);
		if (n < 0) {
			return 3;
		}
		if (n >= i) {
			return 4;
		}
		CFStringRef prg, vID, pID;
		prg = CFStringCreateWithFormat(NULL, NULL, CFSTR("%s"), argv[0]);
		vID = CFStringCreateWithFormat(NULL, NULL, CFSTR("0x%04x"), vArr[n]);
		if (pArr[n] == -1) {
			pID = 0;
		} else {
			pID = CFStringCreateWithFormat(NULL, NULL, CFSTR("0x%04x"), pArr[n]);
		}

		writePlist(prg, vID, pID);
	} else {
		// Lock screen on removal
		IOServiceAddMatchingNotification(notificationObject, kIOTerminatedNotification, myUSBMatchDictionary, tokenRemoveCallback, 0, &portIterator);
		while (IOIteratorNext(portIterator)) {}; // Run out the iterator or notifications won't start (you can also use it to iterate the available devices).

		// Wake-up on re-insert
		IOServiceAddMatchingNotification(notificationObject, kIOPublishNotification, myUSBMatchDictionary, tokenInsertCallback, 0, &portIterator);
		while (IOIteratorNext(portIterator)) {}; // Run out the iterator or notifications won't start (you can also use it to iterate the available devices).

		CFRunLoopRun();
	}

	return 0;
}
