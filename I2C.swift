protocol I2C {
    func writeBlocking(address: UInt8, bytes: Span<UInt8>)
}
