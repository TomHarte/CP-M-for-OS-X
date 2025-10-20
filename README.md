CP/M for OS X
=============
Build command for macOS this will give you CPM for OS X.app the local directory, move it into the applications directory.
- CPM for OS X-Info.plist modified so it will run on macOS Tahoe

% xcodebuild -project "CPM for OS X.xcodeproj" \
           -scheme "CPM for OS X" \
           -configuration Release \
           CONFIGURATION_BUILD_DIR="$(pwd)" \
           clean build
           
It…

* allows you to run CP/M-80 software on your Mac:

![WordStar; opening](Images/WordStar.gif)

* supports drag and drop mounting of drives for opening files:

![SuperCalc; receiving a file](Images/SuperCalc.gif)

* supports copy and paste:

![Zork; being copied from and pasted to](Images/Zork.gif)

* uses native text rendering for a completely flexible window:

![Turbo Pascal; resizing](Images/TurboPascal.gif)

* multitasks, naturally:

![WordStar, SuperCalc, Zork and Turbo Pascal in harmony](Images/Multitasking.gif)
