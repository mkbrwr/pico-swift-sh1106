@_cdecl("posix_memalign")
public func posix_memalign(
    _ ptr: UnsafeMutablePointer<UnsafeMutableRawPointer?>, _ alignment: Int, _ size: Int
) -> CInt {
    // Check if alignment is a power of 2 and at least sizeof(void*)
    guard
        alignment > 0 && (alignment & (alignment - 1)) == 0
            && alignment >= MemoryLayout<UnsafeMutableRawPointer?>.size
    else {
        return 22  // EINVAL
    }

    // Check if size is 0
    guard size > 0 else {
        ptr.pointee = nil
        return 0
    }

    // Allocate aligned memory using malloc and manual alignment
    let rawPtr = malloc(size + alignment - 1)
    guard let rawPtr = rawPtr else {
        return 12  // ENOMEM
    }

    // Calculate aligned address
    let addr = UInt(bitPattern: rawPtr)
    let alignedAddr = (addr + UInt(alignment - 1)) & ~UInt(alignment - 1)
    let alignedPtr = UnsafeMutableRawPointer(bitPattern: alignedAddr)

    ptr.pointee = alignedPtr
    return 0
}
