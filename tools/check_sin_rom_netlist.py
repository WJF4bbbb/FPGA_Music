"""Audit Gowin's mapped sine tables; generate a primitive sweep in ignored sim/.

Run from the repository root after run_gowin_synthesis.ps1. This inspects the
actual generated netlist; it never changes RTL or a synthesis option.
"""
import argparse
import math
from pathlib import Path
import re


def audit(netlist, expected_count, out):
    rtl = Path('rtl/sin_rom.v').read_text(encoding='utf-8')
    table = {int(a): int(v, 16) for a, v in re.findall(
        r"8'd(\d+):\s*dout\s*=\s*16'sh([0-9A-Fa-f]+)", rtl)}
    assert set(table) == set(range(256)), 'RTL table must cover all 256 addresses'
    assert all(table[a] == (round(32767 * math.sin(2 * math.pi * a / 256)) & 65535)
               for a in range(256)), 'RTL table differs from rounded sine'
    text = netlist.read_text(encoding='utf-8-sig')
    blocks = re.findall(r'\bpROM\s+(\S+)\s*\((.*?)\);', text, re.S)
    assert len(blocks) == expected_count, (netlist, 'pROM count', len(blocks))
    out.mkdir(parents=True, exist_ok=True)
    body = ['`timescale 1ns/1ps', 'module tb_sin_rom_mapped;',
            'reg clk=0; always #5 clk=~clk;', 'reg [7:0] addr=0;',
            'reg [15:0] expected [0:255]; integer a;']
    for lane, (name, ports) in enumerate(blocks):
        params = dict(re.findall(r'defparam\s+' + re.escape(name) +
                                r'\s*\.([A-Z0-9_]+)\s*=\s*([^;]+);', text))
        assert params['BIT_WIDTH'] == '16'
        assert params['READ_MODE'] == "1'b0"
        assert params['RESET_MODE'] == '"SYNC"'
        assert re.search(r'\.AD\(\{GND,GND,phase\[31:24\],GND,GND,VCC,VCC\}\)',
                         ports), 'Unexpected mapped address wiring'
        for pin, value in [('CLK', 'clk_d'), ('CE', 'VCC'), ('OCE', 'GND'), ('RESET', 'GND')]:
            assert f'.{pin}({value})' in ports, ('unexpected primitive wiring', pin)
        image = [0] * 1024
        for bank in range(64):
            value = params.get(f'INIT_RAM_{bank:02X}', "256'h0")
            bits = int(value.split("'h")[1], 16)
            image[bank*16:bank*16+16] = [(bits >> (16*i)) & 65535 for i in range(16)]
        assert image[:256] == [table[a] for a in range(256)], ('ROM mismatch', lane)
        print(f'PASS {netlist}: {name} 256/256 words, BIT_WIDTH=16 READ_MODE=0; phase[31:24] address')
        body += [f'wire [31:0] data{lane};', f'pROM #(\n' + ',\n'.join(
            f'  .{key}({value})' for key, value in params.items()) +
            f'\n) rom{lane} (.DO(data{lane}), .AD({{2\'b00,addr,4\'b0011}}),'
            ' .CLK(clk), .CE(1\'b1), .OCE(1\'b0), .RESET(1\'b0));']
    (out/'sine.hex').write_text(''.join(f'{table[a]:04x}\n' for a in range(256)), encoding='ascii')
    body += ['initial begin', f'  $readmemh("{out.as_posix()}/sine.hex",expected);',
             '  for(a=0;a<256;a=a+1) begin',
             '    @(negedge clk); addr=a; @(posedge clk); #1;']
    for lane in range(len(blocks)):
        body += [f'    if(data{lane}[15:0] !== expected[a])',
                 f'      $fatal(1,"FAIL mapped ROM lane={lane} addr=%0d actual=%h expected=%h",a,data{lane}[15:0],expected[a]);']
    body += ['  end', f'  $display("PASS: mapped pROM sweep {len(blocks)*256} words, official Gowin model");',
             '  $finish;', 'end', 'endmodule']
    (out/'tb_sin_rom_mapped.v').write_text('\n'.join(body)+'\n', encoding='ascii')
    print('PASS: four quadrant values 0000/7fff/0000/8001; independent mathematical sine matches')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlist', nargs='?', type=Path, default=Path('sim/gowin_top.tmp/top.edf'))
    parser.add_argument('--count', type=int, default=4)
    parser.add_argument('--out', type=Path, default=Path('sim/sin_rom_diagnostic.tmp/rom_sweep'))
    args = parser.parse_args()
    audit(args.netlist, args.count, args.out)
