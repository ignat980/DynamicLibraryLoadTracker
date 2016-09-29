//
//  DLLoadTracker.swift
//  DynamicLibraryLoadTracker
//
//  Created by IR on 11/8/15.
//  Copyright © 2015 IR. All rights reserved.
//
// I used http://ddeville.me/2014/04/dynamic-linking/ for refrence. It was a great blog to direct me on how to use the dyld API

import Foundation

// MARK: Constants
///The location where the sdk saves the data
let directoryForLog = (NSSearchPathForDirectoriesInDomains(
    .CachesDirectory, NSSearchPathDomainMask.UserDomainMask, true
    )[0] as NSString).stringByAppendingString("/Log.plist")

///An array of entries for each library that was loaded and unloaded, added by order of events
let logs: NSMutableArray = []


//MARK: -
///This SDK tracks dynamic library loading and unloading
public class DynamicLibraryLoadTracker: NSObject {
    
    ///An array of entries for each library that was loaded and unloaded, added by order of events
    public var log:NSArray {
        get {
            return logs
        }
    }
    ///Initializes a Dynamic Library load/unload tracker.
    public override init() {
        super.init()
        
        _dyld_register_func_for_add_image(callback_add_image)
        _dyld_register_func_for_remove_image(callback_remove_image)
        
        ///Save when the app is put into background or closed
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "save", name: UIApplicationDidEnterBackgroundNotification, object: nil)

    }
    

    public func printLastLog() {
        if let unarchivedLibrariesFile = NSKeyedUnarchiver.unarchiveObjectWithFile(directoryForLog) as? NSMutableArray {
            print(unarchivedLibrariesFile)
        }
    }
    
    ///Save the log to disk into the caches directory
    public func save() {
        NSKeyedArchiver.archiveRootObject(logs, toFile: directoryForLog)
    }

    deinit {
        //Save on deinitailzation (edge case where this library is set as an optional)
        save()
    }
}


//MARK: - Callbacks for the dyld api

func callback_remove_image(mh:UnsafePointer<mach_header>, slide:Int) {
    _update_record_for_image(mh, added: false)
}

func callback_add_image(mh:UnsafePointer<mach_header>, slide:Int) {
    _update_record_for_image(mh, added: true)
}


///Logs the deatils of the dynamic library when one is added or removed
func _update_record_for_image(mh:UnsafePointer<mach_header>, added:Bool) {
    
    //Dynamic Library Info
    var image_info:Dl_info = Dl_info()
    //Fill the image_info struct with data from the mach-o header
    let result = dladdr(mh, &image_info)

    if (result == 0) {
        print("Could not find dynamic libray: \(mh.memory)\n\n")
        return
    }
    
    let image_path:String
    let image_name:String
    
    if let image_name_unwrapped = String(UTF8String: image_info.dli_fname) { //Get Dynamic library executable path
        image_path = image_name_unwrapped
        image_name = image_path.componentsSeparatedByString("/").last!
    } else {
        image_path = "Name Not Found"
        image_name = ""
    }
    
    let image_base_address = String(image_info.dli_fbase.hashValue, radix:16) //Get Dynamic Library base address in hex
    let image_text_size = String(_image_text_segment_size(mh), radix:16) //Get the exectution size of the library
    let image_uuid = CFUUIDCreateString(kCFAllocatorDefault, _image_retrieve_uuid(mh)) as String //Get the uuid for the library
    let log = added ? "Added" : "Removed"
    let info = "\(log): \(image_name): 0x\(image_base_address) (0x\(image_text_size)) \(image_path) <\(image_uuid)>"
    logs.addObject(info)
}

//MARK: - Dynamic Library information functions

///Calculates the size of the mach-o header in bytes (for 32 bit or 64 bit architectures)
/// - Parameter mh: A pointer to the mach-o header
/// - Returns: Size of the header in bytes
func _image_header_size(mh:UnsafePointer<mach_header>) -> Int {
    let is_header_64_bit = (mh.memory.magic == MH_MAGIC_64 || mh.memory.magic == MH_CIGAM_64)
    return is_header_64_bit ? strideof(mach_header_64) : strideof(mach_header)
}


/// This function iterates over every load command in a given mach-o file with a callback function.
///
/// - Parameters:
///     - mh: A pointer to the mach-o header
///     - visitor: A callback function that is given a pointer to a load command and an inout boolean (which is used to stop iteration)
/// - Warning: A breakpoint or crash in this function will crash Xcode 7.1 (7B91b)
func _image_visit_load_commands(mh:UnsafePointer<mach_header>, visitor: ((UnsafeMutablePointer<load_command>, inout Bool) throws -> Void)) {
    
    let header_size = _image_header_size(mh)
    var lc_cursor = UnsafePointer<load_command>(bitPattern: mh.hashValue + header_size) //Offset the cursor past the header
    var stop:Bool = false
    
    for (var idx:UInt32 = 0; idx < mh.memory.ncmds; idx++) {
        
        do {
            try visitor(UnsafeMutablePointer<load_command>(lc_cursor), &stop)
        } catch let error as NSError{
            print("Visitor function threw an error: \(error.localizedDescription)")
        }
        
        //If the visitor reached its desired command, stop iteration
        if stop {return}
        
        //Assign cursor to next command
        lc_cursor = UnsafePointer<load_command>(bitPattern: lc_cursor.hashValue + Int(lc_cursor.memory.cmdsize))
    }
}

/// Gets the uuid from a mach-o file
/// - Returns: a CFUUID, it is used instead of NSUUID because you can create one from individual bytes and it has a method to generate a formatted uuid string
func _image_retrieve_uuid(mh:UnsafePointer<mach_header>) -> CFUUID {
    
    var uuid_cmd:UnsafePointer<uuid_command> = nil

    _image_visit_load_commands(mh) { (lc:UnsafeMutablePointer<load_command>, stop) -> Void in
        if lc.memory.cmdsize == 0 {
            return
        }
        if lc.memory.cmd == UInt32(LC_UUID) {
            uuid_cmd = UnsafePointer<uuid_command>(lc)
            stop = true
        }
    }
    return CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, CFUUIDBytes.init(byte0: uuid_cmd.memory.uuid.0, byte1: uuid_cmd.memory.uuid.1, byte2: uuid_cmd.memory.uuid.2, byte3: uuid_cmd.memory.uuid.3, byte4: uuid_cmd.memory.uuid.4, byte5: uuid_cmd.memory.uuid.5, byte6: uuid_cmd.memory.uuid.6, byte7: uuid_cmd.memory.uuid.7, byte8: uuid_cmd.memory.uuid.8, byte9: uuid_cmd.memory.uuid.9, byte10: uuid_cmd.memory.uuid.10, byte11: uuid_cmd.memory.uuid.11, byte12: uuid_cmd.memory.uuid.12, byte13: uuid_cmd.memory.uuid.13, byte14: uuid_cmd.memory.uuid.14, byte15: uuid_cmd.memory.uuid.15)) //Makes a Core Foundation "CFUUID" struct from the pointer

}


/// Gets the executable text segment size for a library from a mach-o file
/// - Returns: A 32-bit unsinged integer representing the executable text segment size
func _image_text_segment_size(mh:UnsafePointer<mach_header>) -> UInt32 {

    var text_size:UInt32 = 0
    
    _image_visit_load_commands(mh, visitor: {(lc, stop) in
        if (lc.memory.cmdsize == 0) {
            return
        }
        if (lc.memory.cmd == UInt32(LC_SEGMENT)) {
            let seg_cmd = UnsafeMutablePointer<segment_command>(lc)
            if let segname = withUnsafePointer(&seg_cmd.memory.segname.0, {(segname_ptr) -> String? in
                return String(UTF8String: segname_ptr)
            }) {
                if segname == SEG_TEXT {
                    text_size = UInt32(seg_cmd.memory.vmsize)
                    stop = true
                    return
                }
            }
        } else if (lc.memory.cmd == UInt32(LC_SEGMENT_64)) {
            let seg_cmd = UnsafeMutablePointer<segment_command_64>(lc)
            if let segname = withUnsafePointer(&seg_cmd.memory.segname.0, {(segname_ptr) -> String? in
                return String(UTF8String: segname_ptr)
            }) {
                if segname == SEG_TEXT {
                    text_size = UInt32(seg_cmd.memory.vmsize)
                    stop = true
                    return
                }
            }
        }
    })
    
    return text_size
}
