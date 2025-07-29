struct SH1106: ~Copyable {
    static let height = 64
    static let width = 128
    static let i2cAddr: UInt8 = 0x3C
    static let i2cClk = 400
    enum Command: UInt8 {
        case setLowerColAddr = 0x00
        case setHigherColAddr = 0x10
        case setPumpVoltage = 0x30
        case setDispStartLine = 0x40
        case setContrast = 0x81
        case setSegRemap = 0xA0
        case setEntireOn = 0xA4
        case setAllOn = 0xA5
        case setNormDisp = 0xA6
        case setInvDisp = 0xA7
        case setMuxRatio = 0xA8
        case setDisp = 0xAE
        case setPageAddr = 0xB0
        case setComOutDir = 0xC0
        case setDispOffset = 0xD3
        case setDispClkDiv = 0xD5
        case setPrecharge = 0xD9
        case setComPinCfg = 0xDA
        case setVcomDesel = 0xDB
    }
    let pageHeight = 8
    var numPages: Int { Self.height / pageHeight }
    var bufLen: Int { numPages * Self.width }

    let writeMode = 0xFE
    let readMode = 0xFF

    let i2c: UnsafeMutablePointer<i2c_inst_t>

    init(_ i2c: UnsafeMutablePointer<i2c_inst_t>!) {
        self.i2c = i2c
        let cmds: [UInt8] = [
            Command.setDisp.rawValue,
            Command.setDispStartLine.rawValue,
            Command.setSegRemap.rawValue | 0x01,
            Command.setMuxRatio.rawValue,
            63,
            Command.setComOutDir.rawValue | 0x08,
            Command.setDispOffset.rawValue,
            0x00,
            Command.setComPinCfg.rawValue,
            0x12,
            // timing and driving scheme
            Command.setDispClkDiv.rawValue,  // set display clock divide ratio
            0x80,  // div ratio of 1, standard freq
            Command.setPrecharge.rawValue,  // set pre-charge period
            0xF1,  // Vcc internally generated on our board
            Command.setVcomDesel.rawValue,  // set VCOMH deselect level
            0x35,  // 0.77xVcc
            // display
            Command.setContrast.rawValue,  // set contrast control
            0xFF,
            Command.setEntireOn.rawValue,  // set entire display on to follow RAM content
            Command.setNormDisp.rawValue,  // set normal (not inverted) display
            Command.setPumpVoltage.rawValue | 0x02,  // 8.0V pump voltage
            Command.setDisp.rawValue | 0x01,  // turn display on
        ]
        sendCommandList(cmds)
    }

    private func sendCommandList(_ commands: [UInt8]) {
        for command in commands {
            sendCommand(command)
        }
    }

    private func sendCommand(_ command: UInt8) {
        var buf: (UInt8, UInt8) = (0x80, command)
        i2c_write_blocking(i2c, Self.i2cAddr, &buf, 2, false)
    }

    private func sendBuffer(_ buf: UnsafeBufferPointer<UInt8>) {
        var buf = [UInt8(0x40)] + buf
        i2c_write_blocking(i2c, Self.i2cAddr, &buf, buf.count, false)
    }

    func render(_ buf: consuming Span<UInt8>) {
        let columnOffset = 2

        for page in 0..<numPages {
            sendCommand(Command.setPageAddr.rawValue | UInt8(page))

            let colStart = UInt8(columnOffset)
            sendCommand(Command.setLowerColAddr.rawValue | (colStart & 0x0F))
            sendCommand(Command.setHigherColAddr.rawValue | ((colStart >> 4) & 0x0F))

            let pageOffset = page * Self.width
            let pageLen = Self.width

            buf.withUnsafeBufferPointer { buffer in
                sendBuffer(buffer.extracting(pageOffset..<pageOffset + pageLen))
            }
        }
    }
}

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

    func render(onto display: borrowing SH1106) {
        storage.withMemoryRebound(
            to: UInt8.self,
            { buffer in
                display.render(buffer.span)
            })
    }
}

@main
struct Main {
    static func main() {
        stdio_init_all()
        var i2c = i2c0_inst
        i2c_init(&i2c, UInt32(SH1106.i2cClk * 1000))
        gpio_set_function(UInt32(PICO_DEFAULT_I2C_SDA_PIN), GPIO_FUNC_I2C)
        gpio_set_function(UInt32(PICO_DEFAULT_I2C_SCL_PIN), GPIO_FUNC_I2C)
        gpio_pull_up(UInt32(PICO_DEFAULT_I2C_SDA_PIN))
        gpio_pull_up(UInt32(PICO_DEFAULT_I2C_SCL_PIN))

        let display = SH1106(&i2c)
        let buffer = FrameBuffer()

        for y in 0..<SH1106.height {
            for x in 0..<SH1106.width {
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
