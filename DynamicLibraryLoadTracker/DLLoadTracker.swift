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
    
    if (result == 0) {
        print("Could not print info for mach_header: \(mh.memory)\n\n")
        return
    }
    
    let image_name = String(UTF8String: image_info.dli_fname) //Get Dynamic library pathname
    
    let image_base_address:UnsafePointer<intptr_t> = UnsafePointer(image_info.dli_fbase) //Get Dynamic Library base address

    let image_text_size = _image_text_segment_size(mh) //Get the size of the library

    var image_uuid:UnsafeMutablePointer<CChar> = UnsafeMutablePointer<CChar>.alloc(37) //Allocate space for string representatin of uuid
    
    
    if let image_uuid_bytes = _image_retrieve_uuid(mh) {
        let newIntPtr = UnsafeMutablePointer<UInt8>.alloc(1)
        newIntPtr.memory = image_uuid_bytes.0
        uuid_unparse(newIntPtr, image_uuid)
    }
    
    let log = added ? "Added" : "Removed"
    
    print("\(log): 0x\(image_base_address) (0x\(image_text_size)) \(image_name) <\(image_uuid)>\n\n")
    
}

func _image_header_size(mh:UnsafePointer<mach_header>) -> Int {
    let is_header_64_bit = (mh.memory.magic == MH_MAGIC_64 || mh.memory.magic == MH_CIGAM_64)
    return is_header_64_bit ? sizeof(mach_header_64) : sizeof(mach_header)
}


func _image_visit_load_commands(mh:UnsafePointer<mach_header>, visitor: ((UnsafeMutablePointer<load_command>, inout Bool) -> Void)?)
{
    if visitor != nil {
        var lc_cursor = mh + _image_header_size(mh)
        
        for (var idx:UInt32 = 0; idx < mh.memory.ncmds; idx++) {
            var lc = UnsafeMutablePointer<load_command>(lc_cursor) //Fundamentally unsafe conversion
            print(lc.memory)
            var stop:Bool = false
            
//            do {
                 visitor!(lc, &stop)
//            } catch let error as NSError{
//                print("Visitor function failed, error: \(error.localizedDescription)")
//            }
            print(stop)
            if (stop) {
                return
            }
            
            lc_cursor += Int(lc.memory.cmdsize)
        }
    }
}

func _image_retrieve_uuid(mh:UnsafePointer<mach_header>) -> uuid_t? {
    var uuid_cmd:UnsafePointer<uuid_command> = nil
    _image_visit_load_commands(mh, visitor: {(lc, stop) in
        if (lc.memory.cmdsize == 0) {
            return
        }
        if (Int32(lc.memory.cmd) == LC_UUID) {
            uuid_cmd = UnsafePointer<uuid_command>(lc)
            stop = true
        }
    })
    
    if (uuid_cmd == nil) {
        return nil
    }
    
    return uuid_cmd.memory.uuid
}

func _image_text_segment_size(mh:UnsafePointer<mach_header>) -> UInt64 {
    let text_segment_name = "__TEXT" //let text_segment_name:UnsafeMutablePointer<CChar> = UnsafePointer<CChar>(CChar("__TEXT")!)
    
    var text_size:UInt64 = 0
    
    _image_visit_load_commands(mh, visitor: {(lc, stop) in
        print(lc.memory)
        if (lc.memory.cmdsize == 0) {
            return
        }
        if (Int32(lc.memory.cmd) == LC_SEGMENT) {
            var seg_cmd = UnsafeMutablePointer<segment_command>(lc) //Fundamentally unsafe, but should work
            if (strcmp(&seg_cmd.memory.segname.0, text_segment_name) == 0) {
				text_size = UInt64(seg_cmd.memory.vmsize)
				stop = true
				return
            }
        } else if (Int32(lc.memory.cmd) == LC_SEGMENT_64) {
            var seg_cmd = UnsafeMutablePointer<segment_command_64>(lc)
            if (strcmp(&seg_cmd.memory.segname.0, text_segment_name) == 0) {
				text_size = seg_cmd.memory.vmsize
				stop = true
				return
            }
        } else {
            //throw NSError(domain: "_image_text_segment_size, _image_visit_load_commands, load command is not a segment command", code: 0, userInfo: nil)
        }
    })
    
    return text_size;
}
