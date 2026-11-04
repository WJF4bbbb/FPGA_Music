import http.client
import threading
import importlib.util
import json
import pathlib
import struct
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.find_spec('wave_protocol')
wave_protocol = __import__('wave_protocol') if spec else None
import bt_bridge


def chunks(capture_id=7, flags=1):
    return [bytearray(struct.pack('<BBHHHI', 1, flags, capture_id, 512, offset, 46875) + b''.join(struct.pack('<h', [-32768,-1,0,32767][i % 4]) for i in range(offset,min(offset+120,512)))) for offset in [0,120,240,360,480]]


def frame(ftype, payload):
    body = bytes([ftype,len(payload)]) + payload
    return b'\xaa\x55' + body + bytes([bt_bridge.crc8(body)])


class WaveTests(unittest.TestCase):
    def test_api(self):
        self.assertIsNotNone(wave_protocol, 'wave_protocol module must exist')

    def test_signed_complete_wrap_and_reset(self):
        a=wave_protocol.WaveAssembler()
        for ident in [65535,0]:
            ps=chunks(ident)
            for p in ps[:-1]: self.assertIsNone(a.push(p))
            result=a.push(ps[-1])
            self.assertEqual(result,dict(captureId=ident,sampleRate=46875,triggered=True,samples=[-32768,-1,0,32767]*128))
        a.push(chunks()[0]);a.reset()
        for p in chunks()[1:]: self.assertIsNone(a.push(p))

    def test_invalid_capture_recovers(self):
        for order in [[0,2,3,4],[0,1,1,2,3,4],[0,2,1,3,4]]:
            a=wave_protocol.WaveAssembler();ps=chunks()
            for n in order: self.assertIsNone(a.push(ps[n]))
            for p in ps: result=a.push(p)
            self.assertEqual(len(result['samples']),512)
        for index,value in [(0,2),(1,2),(2,8),(4,1),(6,121),(8,0),(1,0)]:
            a=wave_protocol.WaveAssembler();ps=chunks();a.push(ps[0]);ps[1][index]=value
            for p in ps[1:]:self.assertIsNone(a.push(p))
        for p in [b'',chunks()[0][:-1],bytes(254)]:self.assertIsNone(wave_protocol.WaveAssembler().push(p))

    def test_bridge_stream_crc_reset_status_and_wave_sse(self):
        shared=bt_bridge.Shared()
        parser=bt_bridge.BridgeParser(shared)
        bad=bytearray(frame(1,bytes(15)));bad[-1]^=1
        stream=frame(16,chunks()[0])+bad+b''.join(frame(16,p) for p in chunks()[1:])
        for i in range(0,len(stream),7):parser.push(stream[i:i+7])
        self.assertIsNone(shared.wave);self.assertEqual(shared.bad,1)
        stream=b''.join(frame(16,p) for p in chunks(0))+frame(1,bytes(15))
        for byte in stream:parser.push(bytes([byte]))
        self.assertEqual(shared.wave['captureId'],0);self.assertEqual(shared.seq,1)
        self.assertEqual(shared.status['notes'],[0,0,0,0])
        self.assertTrue(bt_bridge.sse_event(shared.wave,'wave').startswith(b'event: wave\ndata: '))
        self.assertTrue(bt_bridge.sse_event(shared.status).startswith(b'data: '))
        parser.push(frame(16,chunks()[0]));parser.reset()
        for p in chunks()[1:]:parser.push(frame(16,p))
        self.assertIsNone(shared.wave)


    def test_http_sse_named_wave_and_reconnect_waits_for_new_capture(self):
        previous=bt_bridge.S
        shared=bt_bridge.Shared();bt_bridge.S=shared
        parser=bt_bridge.BridgeParser(shared)
        for p in chunks(7):parser.push(frame(16,p))
        parser.push(frame(1,bytes(15)))
        server=bt_bridge.ThreadingHTTPServer(('127.0.0.1',0),bt_bridge.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        clients=[]
        def event(response):
            lines=[]
            while True:
                line=response.readline()
                if line==b'\n':return b''.join(lines)
                if not line:raise AssertionError('SSE ended early')
                lines.append(line)
        try:
            for ident in [8,9]:
                connection=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=3)
                clients.append(connection);connection.request('GET','/events')
                response=connection.getresponse()
                self.assertEqual(response.status,200)
                self.assertTrue(event(response).startswith(b'data: '))
                for p in chunks(ident):parser.push(frame(16,p))
                actual=event(response)
                self.assertTrue(actual.startswith(b'event: wave\ndata: '))
                capture=json.loads(actual.split(b'data: ',1)[1])
                self.assertEqual(capture['captureId'],ident)
                self.assertEqual(capture['samples'][:4],[-32768,-1,0,32767])
                response.close();connection.close()
        finally:
            for client in clients:client.close()
            server.shutdown();server.server_close();thread.join(timeout=3)
            bt_bridge.S=previous

    def test_optional_physical_uart_fixture(self):
        fixture=ROOT.parent/'sim'/'waveform_uart.hex'
        if not fixture.exists():self.skipTest('physical UART fixture not generated yet')
        waves=[];assembler=wave_protocol.WaveAssembler()
        def received(ftype,payload):
            if ftype==16:
                capture=assembler.push(payload)
                if capture is not None:waves.append(capture)
        decoder=wave_protocol.FrameDecoder(received,assembler.reset)
        data=bytes(int(value,16) for value in fixture.read_text().split())
        for start in range(0,len(data),17):decoder.push(data[start:start+17])
        self.assertEqual([wave['captureId'] for wave in waves],[0,1])
        pattern=[0,32767,-32768,-1,1,-21931,1234,-1234]
        for wave in waves:
            self.assertEqual(wave['sampleRate'],46875);self.assertTrue(wave['triggered'])
            self.assertEqual(wave['samples'],pattern*64)

if __name__=='__main__':unittest.main()
