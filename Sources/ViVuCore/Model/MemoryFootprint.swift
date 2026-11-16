import Darwin

/// Current physical footprint of this process, the number Activity Monitor shows as "Memory".
public enum MemoryFootprint {
    public static func current() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    public static func megabytes(_ bytes: Int) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
