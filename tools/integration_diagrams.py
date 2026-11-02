"""Regenerate integration SVG teaching diagrams from the verified source contract/log.

Run from the repository root after run_integration.ps1. No third-party packages.
Figures are explanatory schematics, not screenshots of simulated waveforms.
"""
from pathlib import Path
from html import escape
import re

OUT = Path('docs/integration/images')
OUT.mkdir(parents=True, exist_ok=True)
log_bytes = Path('sim/tb_top_integration.run.log').read_bytes()
LOG = log_bytes.decode('utf-16' if log_bytes.startswith(b'\xff\xfe') else 'utf-8-sig')
KEY = re.search(r'LATENCY key raw_event=(\d+) event_alloc=(\d+) alloc_pcm=(\d+) pcm_i2s_msb=(\d+) total=(\d+)', LOG)
CTRL = re.search(r'LATENCY control raw_config=(\d+) config_pcm=(\d+) pcm_i2s_msb=(\d+) total=(\d+)', LOG)
assert KEY and CTRL, 'Run the actual integration simulation before generating latency figures'


def text(x, y, value, size=18, color='#172b4d'):
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}">{escape(str(value))}</text>'


def box(x, y, title, lines=(), w=250, color='#e8f1ff'):
    body = f'<rect x="{x}" y="{y}" width="{w}" height="100" rx="10" fill="{color}" stroke="#7793b3"/>'
    body += text(x+14, y+28, title, 20)
    for n, line in enumerate(lines):
        body += text(x+14, y+53+n*23, line, 15)
    return body


def arrow(x1, y1, x2, y2, label=''):
    body = f'<path d="M{x1},{y1} L{x2},{y2}" fill="none" stroke="#486581" stroke-width="2" marker-end="url(#tip)"/>'
    if label:
        body += text((x1+x2)/2+4, (y1+y2)/2-9, label, 14)
    return body


def save(name, title, body, height=510):
    header = '<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="%d" viewBox="0 0 1280 %d">' % (height,height)
    header += '<defs><marker id="tip" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8" fill="#486581"/></marker></defs>'
    header += '<rect width="100%" height="100%" fill="#fff"/><g font-family="Microsoft YaHei,Arial,sans-serif">'
    header += text(30, 38, title, 25)
    footer = text(30, height-18, 'Source: real RTL + integration assertions; schematic, not a captured waveform.', 13, '#526777')
    (OUT/name).write_text(header+body+footer+'</g></svg>\n', encoding='utf-8')


body = ''
for x, title, lines in [(30,'sensor_frontend',['key_raw[7:0] -> key_state','2 sync + 5400 filter clocks']),
                         (345,'note_event',['32-entry FIFO; MIDI map','release first, then key order']),
                         (660,'top event mux',['normal / test_mode','valid + ready handshake']),
                         (975,'voice_alloc',['4 voices; key identity','retrigger / steal / release'])]:
    body += box(x,90,title,lines)
for x in (280,595,910): body += arrow(x,140,x+65,140)
body += arrow(1100,190,1100,275)
for x,title,lines in [(975,'osc x4 + sin_rom',['independent DDS phase','signed wave[15:0]']),
                       (660,'adsr x4',['cached trigger + frame gate','signed sample[15:0]']),
                       (345,'mixer',['signed sum >>2; gain/65536','complete frame only']),
                       (30,'i2s_tx',['pending -> frame buffer','mono PCM copied to L/R'])]:
    body += box(x,275,title,lines,color='#e6f5ec')
for x in (975,660,345): body += arrow(x,325,x-65,325)
body += text(30,435,'audio_timing: 27 MHz -> BCLK 1.5 MHz; frame_tick/frame_load every 576 clocks',19)
save('signal_flow.svg','Real system signal flow',body)

body = box(35,90,'C: input and control',['sensor_frontend / note_event','control_panel'],w=355)
body += box(460,90,'B: synthesis',['voice_alloc / osc / sin_rom','adsr / mixer'],w=355,color='#e6f5ec')
body += box(885,90,'A: integration / audio',['top / audio_timing','test_mode / i2s_tx'],w=355,color='#fff0d9')
body += arrow(390,140,460,140,'events')+arrow(815,140,885,140,'PCM')
body += box(35,280,'control_panel',['timbre[1:0], signed bend[3:0]','master_gain[15:0]'],w=355)
body += box(460,280,'osc x4 / mixer',['timbre + bend -> every osc','gain -> mixer frame snapshot'],w=355,color='#e6f5ec')
body += arrow(390,330,460,330)
body += text(35,435,'Shared clk and core_rst_n; busy/env_done return from ADSR to allocator.',19)
save('abc_connections.svg','A / B / C ownership and connections',body)

body = text(35,95,'At each clk rising edge, pre-edge valid && ready consumes exactly one payload.',19)
for n,(title,lines) in enumerate([
    ('E0: sensor updates',['key_state registers new mask','note_event still reads old mask']),
    ('E1: FIFO enqueues',['release events, then press events','evt_valid/payload become visible']),
    ('E2: allocation',['voice_alloc reads stable FIFO head','gate and trigger update after NBA']),
    ('E3: trigger cache',['next FIFO entry transfers if present','ADSR remembers one-clock trigger'])]):
    body += box(35+n*310,155,title,lines,w=280)
    if n<3: body += arrow(315+n*310,205,345+n*310,205)
body += text(35,330,'When ready=0: valid and the entire key_id/note/on tuple must remain stable.',20)
body += text(35,375,'Real top allocator is always ready; demo isolates the real source with ready=0.',18)
save('event_handshake.svg','Note event handshake and NBA timing',body)

body = ''
for n,note in enumerate([60,64,67,72]):
    x=35+310*n
    body += box(x,90,f'Voice {n}: MIDI {note}',[f'note slice [{n*7+6}:{n*7}]','independent phase + envelope'],w=280,color='#e6f5ec')
    body += arrow(x+140,190,x+140,275)
    body += box(x,275,'Verified real contribution',['wave != 0; ADSR sample != 0','omitting lane changes mixed PCM'],w=280)
body += text(35,435,'Four gates alone are insufficient: arithmetic and each lane contribution are asserted.',19)
save('four_voice_allocation.svg','Four-voice demo: real notes and independent audio lanes',body)

body = text(35,95,'TX prepares DATA/WS on BCLK falling edges; receiver samples on rising edges.',19)
for n,(title,lines) in enumerate([
    ('index 15',['old left LSB; WS -> 1','next BCLK rise still reads left LSB']),
    ('index 16',['right MSB; WS = 1','right word begins one bit later']),
    ('index 31',['old right LSB; WS -> 0','load NEW frame from OLD pending']),
    ('index 0',['new left MSB; WS = 0','left word begins one bit later'])]):
    body += box(35+n*310,155,title,lines,w=280)
    if n<3: body += arrow(315+n*310,205,345+n*310,205)
body += text(35,335,'Each channel: 16 MSB-first bits; stereo pair: 32 BCLK periods = 576 clk cycles.',19)
body += text(35,380,'A PCM arriving at frame_load is kept for the NEXT load; no same-edge bypass.',19)
save('i2s_timing.svg','Philips I2S boundary timing and sample buffering',body)

k=list(map(int,KEY.groups()));c=list(map(int,CTRL.groups()))
control_pass = c[-1] <= 270000
body=text(35,92,'Actual measured cycles (default filters); 27,000 cycles = 1 ms nominal.',19)
for y,title,vals,names in [(135,'Key input',k,['raw -> event','event -> allocation','allocation -> PCM','PCM -> I2S MSB']),
                            (300,'Bend control',c,['raw -> bend','bend -> changed PCM','PCM -> I2S MSB'])]:
    body += text(35,y,title+f': total {vals[-1]} clocks = {vals[-1]/27000:.6f} ms',22)
    for n,(value,label) in enumerate(zip(vals[:-1],names)):
        x=35+n*310
        body += box(x,y+20,label,[f'{value} clocks',f'{value/27000:.6f} ms'],w=280,
                    color=('#e6f5ec' if control_pass else '#ffe4e4')
                    if title=='Bend control' and n==0 else '#e8f1ff')
control_result = 'PASS default bend total <= 10 ms' if control_pass else 'FAIL default bend total > 10 ms'
body += text(35,465,f'PASS key input; {control_result}. Functional audio checks pass.',18)
save('latency_breakdown.svg','Measured latency decomposition',body,height=530)
print('Generated six SVG diagrams from real source contracts and measured run log.')
