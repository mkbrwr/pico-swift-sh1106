struct SH1106 {
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

    func sendCommandList(_ commands: [UInt8]) {
        for command in commands {
            sendCommand(command)
        }
    }

    func sendCommand(_ command: UInt8) {
        var buf: (UInt8, UInt8) = (0x80, command)
        i2c_write_blocking(i2c, Self.i2cAddr, &buf, 2, false)
    }

    func sendBuffer(_ buf: [UInt8]) {
        var buf = [0x40] + buf
        i2c_write_blocking(i2c, Self.i2cAddr, &buf, buf.count, false)
    }

    func render(_ buf: [UInt8]) {
        // SH1106 uses page addressing mode only
        // We need to send each page separately with proper column addressing

        let columnOffset = 2  // SH1106 column offset

        for page in 0..<numPages {
            // Set page address
            sendCommand(Command.setPageAddr.rawValue | UInt8(page))

            // Set column address (with offset for SH1106)
            let colStart = UInt8(columnOffset)
            sendCommand(Command.setLowerColAddr.rawValue | (colStart & 0x0F))
            sendCommand(Command.setHigherColAddr.rawValue | ((colStart >> 4) & 0x0F))

            // Calculate the offset in the buffer for this page
            let pageOffset = page * Self.width
            let pageLen = Self.width

            // Send the data for this page
            let pageData = Array(buf[pageOffset..<pageOffset + pageLen])
            sendBuffer(pageData)
        }
    }
    static func setPixel(buf: inout [UInt8], x: Int, y: Int, on: Bool) {
        let bytesPerRow = Self.width

        let byteIdx = (y / 8) * bytesPerRow + x
        var byte = buf[byteIdx]

        if on {
            byte |= 1 << (y % 8)
        } else {
            byte &= ~(1 << (y % 8))
        }

        buf[byteIdx] = byte
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
        while true {
            var buffer = Array(repeating: UInt8(0), count: display.bufLen)

            for y in 0..<SH1106.height {
                for x in 0..<SH1106.width {
                    SH1106.setPixel(buf: &buffer, x: x, y: y, on: true)
                    display.render(buffer)
                    sleep_ms(1)
                }
            }
        }
    }
}
