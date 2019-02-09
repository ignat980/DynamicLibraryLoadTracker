//
//  DLLoadTracker.swift
//  DynamicLibraryLoadTracker
//
//  Created by Ignat Remizov on 11/8/15.
//  Copyright © 2019 Ignat Remizov. All rights reserved.
//
// I used http://ddeville.me/2014/04/dynamic-linking for reference. It was a great blog to direct me on how to use the dyld API

import Foundation

// MARK: Constants
///The location where the sdk saves the data
let directoryForLog = (NSSearchPathForDirectoriesInDomains(
    .cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true
    )[0] as NSString).appending("/Log.plist")

///An array of entries for each library that was loaded and unloaded, added by order of events
let logs: NSMutableArray = []


//MARK: -
///This SDK tracks dynamic library loading and unloading
open class DynamicLibraryLoadTracker: NSObject {
    
    ///An array of entries for each library that was loaded and unloaded, added by order of events
    @objc open var log:NSArray {
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
        NotificationCenter.default.addObserver(self, selector: #selector(DynamicLibraryLoadTracker.save), name: UIApplication.didEnterBackgroundNotification, object: nil)

    }
    

    @objc open func printLastLog() {
        if let unarchivedLibrariesFile = NSKeyedUnarchiver.unarchiveObject(withFile: directoryForLog) as? NSMutableArray {
            print(unarchivedLibrariesFile)
        }
    }
    
    ///Save the log to disk into the caches directory
    @objc open func save() {
        NSKeyedArchiver.archiveRootObject(logs, toFile: directoryForLog)
    }

    deinit {
        //Save on deinitailzation (edge case where this library is set as an optional)
        save()
    }
}


//MARK: - Callbacks for the dyld api

func callback_remove_image(_ mh:UnsafePointer<mach_header>?, slide:Int) {
    _update_record_for_image(mh, added: false)
}

 func callback_add_image(_ mh:UnsafePointer<mach_header>?, slide:Int) {
    _update_record_for_image(mh, added: true)
}


///Logs the deatils of the dynamic library when one is added or removed
func _update_record_for_image(_ mh:UnsafePointer<mach_header>?, added:Bool) {
    
    //Dynamic Library Info
    var image_info = Dl_info()
    //Fill the image_info struct with data from the mach-o header
    let result = dladdr(mh, &image_info)

    if (result == 0) {
        print("Could not find dynamic libray: \(String(describing: mh?.pointee))\n\n")
        return
    }
    
    let image_path:String
    let image_name:String
    
    if let image_name_unwrapped = String(validatingUTF8: image_info.dli_fname) { //Get Dynamic library executable path
        image_path = image_name_unwrapped
        image_name = image_path.components(separatedBy: "/").last!
    } else {
        image_path = "Name Not Found"
        image_name = ""
    }
    
    let image_base_address = String(image_info.dli_fbase.hashValue, radix:16) //Get Dynamic Library base address in hex
    let image_text_size = String(_image_text_segment_size(mh!), radix:16) //Get the exectution size of the library
    let image_uuid = _image_retrieve_uuid(mh!).uuidString //Get the uuid for the library
    let log = added ? "Added" : "Removed"
    let info = "\(log): \(image_name): 0x\(image_base_address) (0x\(image_text_size)) \(image_path) <\(image_uuid)>"
    logs.add(info)
}

//MARK: - Dynamic Library information functions

///Gives the size of the mach-o header in bytes depending on 32 bit or 64 bit architectures
/// - Parameter mh: A pointer to the mach-o header
/// - Returns: Size of the header in bytes
func _image_header_size(_ mh:UnsafePointer<mach_header>) -> Int {
    let is_header_64_bit = (mh.pointee.magic == MH_MAGIC_64 || mh.pointee.magic == MH_CIGAM_64)
    return is_header_64_bit ? MemoryLayout<mach_header_64>.stride : MemoryLayout<mach_header>.stride
}


/// This function iterates over every load command in a given mach-o file with a callback function.
///
/// - Parameters:
///     - mh: A pointer to the mach-o header
///     - visitor: A callback function that is given a pointer to a load command and an inout boolean (which is used to stop iteration)
func _image_visit_load_commands(_ mh:UnsafePointer<mach_header>, visitor: ((UnsafePointer<load_command>, inout Bool) throws -> Void)) {
    
    let header_size = _image_header_size(mh)
    var stop:Bool = false
    
    if var lc_cursor = UnsafeRawPointer(bitPattern: mh.hashValue + header_size) { //Create a pointer past the header
        for _:UInt32 in 0 ..< mh.pointee.ncmds {
            let lc = lc_cursor.assumingMemoryBound(to: load_command.self)
            
            do {
                try visitor(lc, &stop)
            } catch let error as NSError{
                print("Visitor function threw an error: \(error.localizedDescription)")
            }
            
            //If the visitor reached its desired command, stop iteration
            if stop {return}
            
            //Assign cursor to next command
            lc_cursor += Int(lc.pointee.cmdsize)
            /* - NOTE -
             += forcefully creates an unwrapped pointer after calling .advance() on itself.
             It is possible to use this shorthand with an UnsafePointer, but only in specific cases where the size of the struct is small so it is easy to understand, since advance() uses the size of the struct that the UnsafePointer is typed to when performing the operation.
             The more 'proper' way to do this would be to construct a new pointer like this:
             lc_cursor = UnsafeRawPointer(bitPattern: lc_cursor.hashValue + Int(lc_cursor.pointee.cmdsize))
            */
        }
    }
}

/// Gets the uuid from a mach-o file
/// - Returns: a CFUUID, it is used instead of NSUUID because you can create one from individual bytes and it has a method to generate a formatted uuid string
func _image_retrieve_uuid(_ mh:UnsafePointer<mach_header>) -> UUID {
    
    var uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")! //initialize an empty uuid

    _image_visit_load_commands(mh) { (lc, stop) -> Void in
        if lc.pointee.cmdsize == 0 {
            return
        }
        if lc.pointee.cmd == UInt32(LC_UUID) {
            lc.withMemoryRebound(to: uuid_command.self, capacity: 1, {
                uuid = UUID(uuid: $0.pointee.uuid)
            })
            stop = true
        }
    }
    return uuid
}


/// Gets the executable text segment size for a library from a mach-o file
/// - Returns: A 32-bit unsinged integer representing the executable text segment size
func _image_text_segment_size(_ mh:UnsafePointer<mach_header>) -> UInt32 {

    var text_size:UInt32 = 0
    
    _image_visit_load_commands(mh, visitor: {(lc, stop) in
        if (lc.pointee.cmdsize == 0) {
            return
        }
        if (lc.pointee.cmd == UInt32(LC_SEGMENT)) {
            let seg_cmd = UnsafeMutableRawPointer(mutating: lc).bindMemory(to: segment_command.self, capacity: 1)
            let segname = String(validatingUTF8: &seg_cmd.pointee.segname.0)! //TODO: figure out why I can't use a non-muating pointer to pass a value to generate a string
            if segname == SEG_TEXT {
                text_size = UInt32(seg_cmd.pointee.vmsize)
                stop = true
                return
            }
        } else if (lc.pointee.cmd == UInt32(LC_SEGMENT_64)) {
            let seg_cmd = UnsafeMutableRawPointer(mutating: lc).bindMemory(to: segment_command_64.self, capacity: 1)
            let segname = String(validatingUTF8: &seg_cmd.pointee.segname.0)!
            if segname == SEG_TEXT {
                text_size = UInt32(seg_cmd.pointee.vmsize)
                stop = true
                return
            }
        }
    })
    
    return text_size
}
