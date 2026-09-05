import Foundation

/// Reports the extension's physical memory footprint, the number iOS uses
/// when deciding to kill a packet tunnel extension (limit is about 50 MB).
enum MemoryMonitor {
    static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint)
    }

    static func footprintMB() -> Double {
        Double(footprintBytes()) / 1024 / 1024
    }
}
