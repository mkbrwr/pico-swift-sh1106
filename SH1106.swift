struct SH1106<Channel: I2C>: ~Copyable {
    let height = 64
    let width = 128
    let i2cAddr: UInt8 = 0x3C
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
    var numPages: Int { height / pageHeight }
    var bufLen: Int { numPages * width }

    let writeMode = 0xFE
    let readMode = 0xFF

    let i2c: Channel

    init(_ i2c: Channel) {
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
        i2c.writeBlocking(address: i2cAddr, bytes: [0x80, command].span)
    }

    private func sendBuffer(_ buf: UnsafeBufferPointer<UInt8>) {
        let buf = [UInt8(0x40)] + buf
        i2c.writeBlocking(address: i2cAddr, bytes: buf.span)
    }

    func render(_ buf: consuming Span<UInt8>) {
        let columnOffset = 2

        for page in 0..<numPages {
            sendCommand(Command.setPageAddr.rawValue | UInt8(page))

            let colStart = UInt8(columnOffset)
            sendCommand(Command.setLowerColAddr.rawValue | (colStart & 0x0F))
            sendCommand(Command.setHigherColAddr.rawValue | ((colStart >> 4) & 0x0F))

            let pageOffset = page * width
            let pageLen = width

            buf.withUnsafeBufferPointer { buffer in
                sendBuffer(buffer.extracting(pageOffset..<pageOffset + pageLen))
            }
        }
    }
}
