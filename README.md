#  Dynamic Library Load Tracker

This was from a programming challenge given to me a few years ago. If you want to take a basic look at how to use pointers in Swift, this is your project!

### The Challenge
The challenge was to implement an SDK that tracks binary image loading. It contains a test iOS app target, which links to the SDK and calls some method to initialize it. The SDK’s job is to record dynamic library loading and unloading to some kind of persistent storage (I went with a simple plist). Upon a subsequent launch, the SDK should print out a list of dynamic libraries and base addresses that were loaded on the last run.

### Design Considerations
1. Launch performance is important. Your SDK should impact application launch time as little as possible. (As I had never worked with C API's in Swift before, the main challenge was to even get it working! I am proud of this code, although I have not optimized it yet.)
2. Pay attention to dependencies. Make sure you set up one single Xcode project that can be built and run from scratch.
3. Storage format matters. Consider the format and methodology you use to persist library data to disk, both for IO performance and complexity of the SDK and the target application. (I prefer plists simply due to their easy of use with obj-c API's, but there would likely be a faster yet more complicated way to save to disk using something like a custom text file encoder/decoder)
