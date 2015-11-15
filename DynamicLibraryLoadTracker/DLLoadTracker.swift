//
//  DLLoadTracker.swift
//  DynamicLibraryLoadTracker
//
//  Created by Ignat Remizov on 11/8/15.
//  Copyright © 2015 Ignat Remizov. All rights reserved.
//
// I used http://ddeville.me/2014/04/dynamic-linking/ for refrence. It was a great blog to direct me on how to use the dyld API

import Foundation


public class DynamicLibraryLoadTracker {
    public init() {
        _dyld_register_func_for_add_image(callback_add_image)
        _dyld_register_func_for_remove_image(callback_remove_image)
    }

}
func callback_remove_image(mh:UnsafePointer<mach_header>, slide:Int) {
    _update_record_for_image(mh, added: false)
}

func callback_add_image(mh:UnsafePointer<mach_header>, slide:Int) {
    _update_record_for_image(mh, added: true)
}

func _update_record_for_image(mh:UnsafePointer<mach_header>, added:Bool) {
    var image_info:Dl_info = Dl_info() //Dynamic Library Info
    let result = dladdr(mh, &image_info) //Change the address to the dynamic library
    print("Address of dynamic library: \(mh.debugDescription)")
    
    if (result == 0) {
        print("Could not find dynamic libray: \(mh.memory)\n\n")
        return
    }
    let image_name:String
    if let image_name_unwrapped = String(UTF8String: image_info.dli_fname) { //Get Dynamic library pathname
        image_name = image_name_unwrapped
        print("image name set: \(image_name)")
    } else {
        image_name = "Name Not Found"
    }
    
    let image_base_address = String(addr64_t(UnsafeMutablePointer<addr64_t>(image_info.dli_fbase).memory), radix:16) //Get Dynamic Library base address
    print("image base address set: \(image_base_address)")
    
    let image_text_size = _image_text_segment_size(mh) //Get the size of the library
    
    print("image text size set: \(image_text_size)")

    var image_uuid = "" //UnsafeMutablePointer<CChar>.alloc(37) //Allocate space for string representatin of uuid

    if let image_cfuuid = _image_retrieve_uuid(mh) {
        image_uuid = CFUUIDCreateString(kCFAllocatorDefault, image_cfuuid) as String
    } else {
        print("Failed to get uuid")
    }

    
    let log = added ? "Added" : "Removed"
    
    print("\(log): 0x\(image_base_address) (0x\(image_text_size)) \(image_name) <\(image_uuid)>\n\n")
    
}

/// Helper method to convert a swift struct of one type to swift struct of another
func _unsafely_convert_struct<T, U>(originalStruct:UnsafePointer<T>, _ _:U.Type) -> U? {
    print("Converting struct, pointer before:", originalStruct)
    print("Converting struct, memory before:", originalStruct.memory)
    let b_ptr = UnsafeMutablePointer<U>(originalStruct)
    print("Converting struct, pointer after:", b_ptr)
    if b_ptr != nil {
        print("Converting struct, memory after:", b_ptr.memory)
        return b_ptr.memory
    } else {
        return nil
    }
}

func _image_header_size(mh:UnsafePointer<mach_header>) -> Int {
    let is_header_64_bit = (mh.memory.magic == MH_MAGIC_64 || mh.memory.magic == MH_CIGAM_64)
    return is_header_64_bit ? strideof(mach_header_64) : strideof(mach_header)
}

//MARK: Visit commands
func _image_visit_load_commands(mh:UnsafePointer<mach_header>, visitor: ((inout load_command, inout Bool) throws -> Void)?) {
    if visitor != nil {
        print("The pointer to the mach header is \(mh.debugDescription) and the memory is \(mh.memory)")
        let header_size = _image_header_size(mh)
        print("the header size is \(header_size)")
        print("There are \(mh.memory.ncmds) commands")
        print("Cursor before: \(mh.debugDescription)")
        var lc_cursor = UnsafePointer<mach_header>.init(bitPattern: mh.hashValue + 13 * 8)//.advancedBy(header_size)
        
        for (var idx:UInt32 = 0; idx < mh.memory.ncmds; idx++) {
            print("Cursor after: \(lc_cursor.debugDescription)")
            
            if var lc = _unsafely_convert_struct(lc_cursor, load_command.self) {//UnsafeMutablePointer<load_command>(lc_cursor).memory //Fundamentally unsafe conversion

                print(lc)
                var stop:Bool = false
                print("Before Visitor, stop has been set to false")
                do {
                    try visitor!(&lc, &stop)
                } catch let error as NSError{
                    print("Visitor function failed, error: \(error.localizedDescription)")
                }
                print("After visitor, stop is \(stop)")
                if (stop) {
                    return
                }
                
                lc_cursor = UnsafePointer<mach_header>(bitPattern: lc_cursor.hashValue + Int(lc.cmdsize))
            }
        }
    }
}


func _image_retrieve_uuid(mh:UnsafePointer<mach_header>) -> CFUUID? {
    
    var uuid_cmd:uuid_command?
    _image_visit_load_commands(mh, visitor: {(lc, stop) in
        if (lc.cmdsize == 0) {
            return
        }
        if (Int32(lc.cmd) == LC_UUID) {
            uuid_cmd = _unsafely_convert_struct(&lc, uuid_command.self)
            print("Stop has been set to true")
            stop = true
        }
    })
    
    if let uuid_cmd = uuid_cmd {
        return CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, CFUUIDBytes.init(byte0: uuid_cmd.uuid.0, byte1: uuid_cmd.uuid.1, byte2: uuid_cmd.uuid.2, byte3: uuid_cmd.uuid.3, byte4: uuid_cmd.uuid.4, byte5: uuid_cmd.uuid.5, byte6: uuid_cmd.uuid.6, byte7: uuid_cmd.uuid.7, byte8: uuid_cmd.uuid.8, byte9: uuid_cmd.uuid.9, byte10: uuid_cmd.uuid.10, byte11: uuid_cmd.uuid.11, byte12: uuid_cmd.uuid.12, byte13: uuid_cmd.uuid.13, byte14: uuid_cmd.uuid.14, byte15: uuid_cmd.uuid.15))
    } else {
        return nil
    }
}

//MARK: - Get text segment size
func _image_text_segment_size(mh:UnsafePointer<mach_header>) -> UInt64 {
    let text_segment_name = "__TEXT" //let text_segment_name:UnsafeMutablePointer<CChar> = UnsafePointer<CChar>(CChar("__TEXT")!)
    
    var text_size:UInt64 = 0
    let segm = getsegbyname("__TEXT") //I just discovered this, all the helper methods are useless now :/
    var segmem = segm.memory
    print("mach_header pointer: \(mh), memory: \(mh.memory)")
    print("Possible pointer: \(segm), memory: \(segm.memory)")
    let str = withUnsafePointer(&segmem.segname.0) {(ptr) -> String in
        return String(UTF8String: ptr)!
    }
    
    print("Segname is \(str)")
//    CFStringCreateWithBytes(kCFAllocatorDefault, segmem.segname, 16, CFStringBuiltInEncodings.UTF8 , false)
////    String(CString: UnsafeMutablePointer<CChar> segm.memory.segname.0), encoding: NSNEXTSTEPStringEncoding)
//    withUnsafePointer(&segm.memory.segname, { (ptr:UnsafePointer<CChar>) -> String in
//        return String(UTF8String: ptr)!
//    })
    
    _image_visit_load_commands(mh, visitor: {(lc, stop) in
        print(lc)
        if (lc.cmdsize == 0) {
            print("Load command is empty")
            return
        }
        if (Int32(lc.cmd) == LC_SEGMENT) {
            if var seg_cmd = _unsafely_convert_struct(&lc, segment_command.self) {
                if let segname = withUnsafePointer(&seg_cmd.segname.0, { (segname_ptr) -> String? in
                    return String(UTF8String: segname_ptr)
                }) {
                    if segname == text_segment_name {
                        text_size = UInt64(seg_cmd.vmsize)
                        print("Stop has been set to true")
                        stop = true
                        return
                    }
                }
            }
        } else if (Int32(lc.cmd) == LC_SEGMENT_64) {
            if var seg_cmd = _unsafely_convert_struct(&lc, segment_command_64.self) {
                if let segname = withUnsafePointer(&seg_cmd.segname.0, { (segname_ptr) -> String? in
                    return String(UTF8String: segname_ptr)
                }) {
                    if segname == text_segment_name {
                        text_size = UInt64(seg_cmd.vmsize)
                        print("Stop has been set to true")
                        stop = true
                        return
                    }
                }
            }
        } else {
            throw NSError(domain: "_image_text_segment_size, _image_visit_load_commands, load command is not a segment command", code: 0, userInfo: nil)
        }
        
    })
    
    return text_size
}
