# usb-lock
This tiny utility locks a Mac OSX computer as soon as a USB token is removed

## Build
```
$ cd usb-lock
$ make
$ sudo make install
```

## Use
The binary `usb-lock` is installed at `/usr/local/bin`. If you call it without
parameters you'll get a short usage output.

The most simple way to use this tool is to insert the usb device you want to
use to lock and unlock your computer and call `usb-lock install`. This will
create a LaunchAgent file for your user account and start the tool
automatically as soon as you are logged in.

To remove the USB device without locking the screen press <kbd>alt</kbd> while removing
the device.
