# The Amazing Audio Engine + OpenEars
### A bug demonstration

I'm currently working on an app that has a few discrete features. Feature **A** uses OpenEars to recognize phrases, feature **B** uses The Amazing Audio Engine (TAAE) to display mic input meters; they are **NEVER** run simultaneously.

I know Apple doesn't expect multiple libraries passing around the AVAudioSession singleton, etc, but I know that both frameworks generally do their best to play nice and clean up after themselves well enough to run exclusively in the same app. I've created a very simple app to demonstrate a strange occational crashe that can occur after starting/stopping OpenEars and then starting TAAE:

````
Blackbox(80309,0x104310000) malloc: *** error for object 0x1380d0e08: incorrect checksum for freed object - object was probably modified after being freed.
````

### How to replicate using the demo
1. Run the app on a device.
2. Grant permission if necessary (may need to restart app)
2. Start OpenEars
3. Stop OpenEars
4. Start TAAE (observe crash)
5. If there's no crash, try stopping TAAE (sometimes it will crash differently on shutdown)
6. If there's still no crash, try running the app again and start from 3.

### The lifecycle of the app
Upon launch, OpenEars and TAAE are both initialized. Then the user can open feature A or B. Upon choosing, the library needed for the chosen feature is started. When the view/feature is dismissed, the library is stopped. Most of the time there is no issue moving from the TAAE dependent feature to the OE dependent one, but moving the other way around seems to cause some low level issue from some shared state:

![App Lifecycle](https://s3.amazonaws.com/f.cl.ly/items/332E3I380T0z2K1A2j0S/lifecycle.png)

Like all good bugs, it doesn't always occur, but when it does it's stacktrace looks a little like this:
![Stacktrace](https://s3.amazonaws.com/f.cl.ly/items/2y1Q0u1O2f1n1v433F34/Stacktrace.png)

### Running the demo project

The project is running the nightly version of TheAmazingAudioEngine, but also reproducably crashes with 1.4.6 (I moved to the nightly to see if recent additions/fixed would help, including the new method `updateWithAudioDescription:inputEnabled:useVoiceProcessing:outputEnabled:`).

The OpenEars version is 2.04
