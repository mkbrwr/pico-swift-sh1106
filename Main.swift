struct FrameBuffer: ~Copyable {
    private let storage = UnsafeMutableRawBufferPointer.allocate(byteCount: 128 * 8, alignment: 8)

    func draw(_ char: FontCharacter, at origin: (x: Int, y: Int)) {
        storage[origin.y * 128 + origin.x + 0] = char.bitmap.0
        storage[origin.y * 128 + origin.x + 1] = char.bitmap.1
        storage[origin.y * 128 + origin.x + 2] = char.bitmap.2
        storage[origin.y * 128 + origin.x + 3] = char.bitmap.3
        storage[origin.y * 128 + origin.x + 4] = char.bitmap.4
        storage[origin.y * 128 + origin.x + 5] = char.bitmap.5
        storage[origin.y * 128 + origin.x + 6] = char.bitmap.6
        storage[origin.y * 128 + origin.x + 7] = char.bitmap.7
    }

    func setPixel(x: Int, y: Int, on: Bool) {
        let bytesPerRow = 128
        let byteIdx = (y / 8) * bytesPerRow + x
        var byte = storage[byteIdx]

        if on {
            byte |= 1 << (y % 8)
        } else {
            byte &= ~(1 << (y % 8))
        }

        storage[byteIdx] = byte
    }

    func render<Channel>(onto display: borrowing SH1106<Channel>) where Channel: I2C {
        storage.withMemoryRebound(
            to: UInt8.self,
            { buffer in
                display.render(buffer.span)
            })
    }
}

struct PicoI2CDevice: I2C {
    private let i2c: UnsafeMutablePointer<i2c_inst_t>!
    init(_ i2cInstance: UnsafeMutablePointer<i2c_inst_t>!) {
        i2c = i2cInstance
    }

    func writeBlocking(address: UInt8, bytes: Span<UInt8>) {
        _ = bytes.withUnsafeBufferPointer { buffer in
            i2c_write_blocking(i2c, address, buffer.baseAddress!, buffer.count, false)
        }
    }
}

@main
struct Main {
    static func main() {
        stdio_init_all()
        var i2c = i2c0_inst
        i2c_init(&i2c, UInt32(400 * 1000))
        gpio_set_function(UInt32(PICO_DEFAULT_I2C_SDA_PIN), GPIO_FUNC_I2C)
        gpio_set_function(UInt32(PICO_DEFAULT_I2C_SCL_PIN), GPIO_FUNC_I2C)
        gpio_pull_up(UInt32(PICO_DEFAULT_I2C_SDA_PIN))
        gpio_pull_up(UInt32(PICO_DEFAULT_I2C_SCL_PIN))

        let i2cDevice = PicoI2CDevice(&i2c)
        let display = SH1106(i2cDevice)
        let buffer = FrameBuffer()

        for y in 0..<64 {
            for x in 0..<128 {
                buffer.setPixel(x: x, y: y, on: false)
            }
        }
        buffer.render(onto: display)
        while true {
            buffer.draw(.h, at: (0, 0))
            buffer.draw(.e, at: (8, 0))
            buffer.draw(.l, at: (16, 0))
            buffer.draw(.l, at: (24, 0))
            buffer.draw(.o, at: (32, 0))
            buffer.draw(.w, at: (48, 0))
            buffer.draw(.o, at: (56, 0))
            buffer.draw(.r, at: (64, 0))
            buffer.draw(.l, at: (72, 0))
            buffer.draw(.d, at: (80, 0))
            buffer.draw(.exclamation, at: (88, 0))
            buffer.render(onto: display)
        }
    }
}
