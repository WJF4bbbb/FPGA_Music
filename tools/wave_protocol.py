"""Dependency-free FPGA waveform capture and outer-frame decoders."""
import struct


def crc8(data):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ 7 if crc & 128 else crc << 1) & 255
    return crc


class WaveAssembler:
    def __init__(self):
        self.reset()

    def reset(self):
        self.capture = None

    def push(self, payload):
        if len(payload) < 14 or len(payload) > 252 or len(payload) % 2:
            self.reset()
            return None
        version, flags, ident, total, offset, rate = struct.unpack_from('<BBHHHI', payload)
        count = (len(payload) - 12) // 2
        if (version != 1 or flags > 1 or total != 512 or rate != 46875 or
                offset >= total or offset % 120 or count != min(120, total - offset)):
            self.reset()
            return None
        if offset == 0:
            self.capture = dict(captureId=ident, sampleRate=rate, triggered=bool(flags), samples=[])
        capture = self.capture
        if (capture is None or capture['captureId'] != ident or capture['sampleRate'] != rate or
                capture['triggered'] != bool(flags) or len(capture['samples']) != offset):
            self.reset()
            return None
        capture['samples'].extend(struct.unpack_from('<%dh' % count, payload, 12))
        if len(capture['samples']) != total:
            return None
        self.reset()
        return capture


class FrameDecoder:
    def __init__(self, on_frame, on_error=None):
        self.on_frame = on_frame
        self.on_error = on_error or (lambda: None)
        self.reset()

    def reset(self):
        self.state, self.ftype, self.length, self.data = 0, 0, 0, bytearray()

    def push(self, data):
        for byte in data:
            if self.state == 0:
                if byte == 170:
                    self.state = 1
            elif self.state == 1:
                if byte == 85:
                    self.state = 2
                elif byte != 170:
                    self.state = 0
            elif self.state == 2:
                self.ftype, self.state = byte, 3
            elif self.state == 3:
                self.length, self.data = byte, bytearray()
                self.state = 4 if byte else 5
            elif self.state == 4:
                self.data.append(byte)
                if len(self.data) == self.length:
                    self.state = 5
            elif self.state == 5:
                ftype, payload = self.ftype, self.data
                valid = crc8(bytes([ftype, self.length]) + payload) == byte
                self.reset()
                if valid:
                    self.on_frame(ftype, payload)
                else:
                    self.on_error()
