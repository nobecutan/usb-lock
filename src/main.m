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

static void tokenInsertCallback(void* refcon, io_iterator_t portIterator)
{
	BOOL match = false;
	while (IOIteratorNext(portIterator)) {
		match = true;
	};

	if (match) {
		io_registry_entry_t r = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
		if (r) {
			IORegistryEntrySetCFProperty(r, CFSTR("IORequestIdle"), kCFBooleanFalse);
			IOObjectRelease(r);
		}
	}
}

static void tokenRemoveCallback(void* refcon, io_iterator_t portIterator)
{
	BOOL match = false;
	while (IOIteratorNext(portIterator)) {
		match = true;
	};

	if (match) {
		io_registry_entry_t r = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
		if (r) {
			IORegistryEntrySetCFProperty(r, CFSTR("IORequestIdle"), kCFBooleanTrue);
			IOObjectRelease(r);
		}
	}
}

static int usage(char *program, char *error)
{
	if (error) {
		printf("Error: %s\n\n", error);
	}

	printf("Usage: %s vendorId [productId]\n\n  e.g. %s 0x1050\n\n", program, program);
	return error == 0 ? 1 : 2;
}

int main(int argc, char **argv)
{
	io_iterator_t portIterator = 0;
	IONotificationPortRef notificationObject = 0;
	CFNumberRef vid_num = 0;
	CFNumberRef pid_num = 0;

	if (argc < 2 || argc > 3) {
		return usage(argv[0], 0);
	}

	NSLog(@"Parsing vendor ID: %s", argv[1]);

	int vid = EOF;
	if (sscanf(argv[1], "%x", &vid) != 1) {
		return usage(argv[0], "Failed to parse VendorId");
	}
	vid_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);


	if (argc == 3) {
		NSLog(@"Parsing product ID: %s", argv[2]);
		int pid = EOF;
		if (sscanf(argv[2], "%x", &pid) != 1) {
			return usage(argv[0], "Failed to parse ProductId");
		}
		pid_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
	}

	CFMutableDictionaryRef myUSBMatchDictionary = IOServiceMatching(kIOUSBDeviceClassName);
	CFRetain(myUSBMatchDictionary); // Need to use it twice and IOServiceAddMatchingNotification() consumes a reference

	CFDictionarySetValue(myUSBMatchDictionary, CFSTR(kUSBVendorID), vid_num);
	CFRelease(vid_num);

	if (pid_num == 0) {
		CFDictionarySetValue(myUSBMatchDictionary, CFSTR (kUSBProductID), CFSTR("*"));
	} else {
		CFDictionarySetValue(myUSBMatchDictionary, CFSTR (kUSBProductID), pid_num);
		CFRelease(pid_num);
	}

	notificationObject = IONotificationPortCreate(kIOMasterPortDefault);


	CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationObject), kCFRunLoopDefaultMode);

	// Lock screen on removal
	IOServiceAddMatchingNotification(notificationObject, kIOTerminatedNotification, myUSBMatchDictionary, tokenRemoveCallback, 0, &portIterator);
	while (IOIteratorNext(portIterator)) {}; // Run out the iterator or notifications won't start (you can also use it to iterate the available devices).

	// Wake-up on re-insert
	IOServiceAddMatchingNotification(notificationObject, kIOPublishNotification, myUSBMatchDictionary, tokenInsertCallback, 0, &portIterator);
	while (IOIteratorNext(portIterator)) {}; // Run out the iterator or notifications won't start (you can also use it to iterate the available devices).

	CFRunLoopRun();
	return 0;
}
