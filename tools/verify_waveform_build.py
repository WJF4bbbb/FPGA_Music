"""Fail closed before publishing a waveform bitstream; standard library only."""
import argparse
import hashlib
import json
from pathlib import Path
import re

def verify_manifest(release_root, inputs):
    manifest = Path(release_root) / 'sources.f'
    content = manifest.read_bytes()
    expected = [(Path(release_root) / line.strip()).resolve().as_posix().casefold()
                for line in content.decode('utf-8-sig').splitlines() if line.strip()]
    actual = [Path(entry['Path']).resolve().as_posix().casefold()
              for entry in inputs if entry['Path'].lower().endswith('.v')]
    if expected != actual:
        raise ValueError('Source manifest differs from the recorded build inputs')
    return hashlib.sha256(content).hexdigest()

def parse_reports(resource_text, timing_text):
    def number(pattern, text):
        found = re.search(pattern, text, re.MULTILINE)
        if not found:
            raise ValueError('Required report field missing: ' + pattern)
        return int(found.group(1))

    result = {name: number(r'^\s*' + label + r'\s*\|\s*(\d+)/', resource_text)
              for name, label in [('logic', 'Logic'), ('registers', 'Register'), ('bsram', 'BSRAM')]}
    ram_count = number(r'^\s*--SDPB\s*\|\s*(\d+)', resource_text)
    if result['bsram'] < 5 or ram_count < 1:
        raise ValueError('Capture must use block RAM, not thousands of register bits')
    for label in ['Logic Register as Latch', 'I/O Register as Latch']:
        if number(r'^\s*--' + re.escape(label) + r'\s*\|\s*(\d+)/', resource_text):
            raise ValueError('Latch inferred: ' + label)
    for analysis in ['Setup', 'Hold']:
        if number(r'<Numbers of ' + analysis + r' Violated Endpoints>:\s*(\d+)', timing_text):
            raise ValueError(analysis + ' timing violations')
    fmax = re.search(r'sys_clk\s+27\.000\(MHz\)\s+([\d.]+)\(MHz\)', timing_text)
    if not fmax or float(fmax.group(1)) < 27:
        raise ValueError('27 MHz frequency constraint not met or missing')
    for analysis in ['setup', 'hold']:
        row = re.search(r'^\s*sys_clk\s+' + analysis + r'\s+(-?[\d.]+)\s+(\d+)\s*$', timing_text, re.MULTILINE)
        if not row or float(row.group(1)) != 0 or int(row.group(2)) != 0:
            raise ValueError(analysis + ' TNS is nonzero or missing')
    result.update(fmaxMHz=float(fmax.group(1)), setupViolations=0, holdViolations=0,
                  captureRAM='SDPB', scope='Offline FPGA clock-domain STA; physical-board tests not performed')
    return result

def verify_directory(directory, target):
    root = Path(directory)
    result = json.loads((root / 'result.json').read_text(encoding='utf-8-sig'))
    if result['ExitCode'] != 0 or result['Target'] != target:
        raise ValueError('Build failed or target mismatched')
    hashes = json.loads((root / 'source-hashes.json').read_text(encoding='utf-8-sig'))
    if not isinstance(hashes, list) or len(hashes) < 20:
        raise ValueError('Source provenance is incomplete')
    for entry in hashes:
        data = Path(entry['Path']).read_bytes()
        if hashlib.sha256(data).hexdigest().upper() != entry['Hash'].upper():
            raise ValueError('Source changed after build: ' + entry['Path'])
    release_root = Path(hashes[0]['Path']).parent.parent
    manifest_hash = verify_manifest(release_root, hashes)
    project = 'MusicSynth_Waveform_' + target
    pnr = root / project / 'impl/pnr'
    report = parse_reports((pnr / (project + '.rpt.txt')).read_text(encoding='utf-8-sig'),
                           (pnr / (project + '.tr')).read_text(encoding='utf-8-sig'))
    bitstream = pnr / (project + '.fs')
    if bitstream.stat().st_size < 100000:
        raise ValueError('Missing or unexpectedly small bitstream')
    report.update(target=target, bitstream=str(bitstream.resolve()),
                  sha256=hashlib.sha256(bitstream.read_bytes()).hexdigest(),
                  sourceManifestSha256=manifest_hash,
                  sourceFilesVerified=len(hashes), sourceHashFile=str((root / 'source-hashes.json').resolve()))
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    parser.add_argument('--target', choices=['wired', 'wireless'], required=True)
    parser.add_argument('--output')
    args = parser.parse_args()
    report = verify_directory(args.directory, args.target)
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(text + '\n', encoding='utf-8')
    print(text)
