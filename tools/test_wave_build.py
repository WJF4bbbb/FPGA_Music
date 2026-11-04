import unittest
import tempfile
from pathlib import Path
from verify_waveform_build import parse_reports, verify_manifest

RESOURCE = '''
 Logic | 5558/20736 | 27%
 Register | 1749/15750 | 12%
 --Logic Register as Latch | 0/15552 | 0%
 --I/O Register as Latch | 0/198 | 0%
 BSRAM | 5/46 | 11%
 --SDPB | 1
'''
TIMING = '''
<Numbers of Setup Violated Endpoints>:0
<Numbers of Hold Violated Endpoints>:0
1 sys_clk Base 37.037 27.000MHz 0.000 18.519 clk
1 sys_clk 27.000(MHz) 28.261(MHz) 20 TOP
sys_clk setup 0.000 0
sys_clk hold 0.000 0
'''

class BuildGateTest(unittest.TestCase):
    def test_manifest_must_match_recorded_rtl_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'sources.f').write_text('rtl/a.v\nrtl/b.v\n')
            inputs = [{'Path': str(root / p)} for p in ['rtl/a.v', 'rtl/b.v', 'constraints/top.sdc']]
            self.assertEqual(len(verify_manifest(root, inputs)), 64)
            (root / 'sources.f').write_text('rtl/a.v\nrtl/new.v\n')
            with self.assertRaisesRegex(ValueError, 'manifest'):
                verify_manifest(root, inputs)

    def test_valid_real_report_shape(self):
        result = parse_reports(RESOURCE, TIMING)
        self.assertEqual(result['bsram'], 5)
        self.assertEqual(result['logic'], 5558)
        self.assertEqual(result['fmaxMHz'], 28.261)

    def test_reject_register_mapped_capture_even_if_timing_passes(self):
        with self.assertRaisesRegex(ValueError, 'RAM'):
            parse_reports(RESOURCE.replace('BSRAM | 5/', 'BSRAM | 4/').replace('--SDPB | 1', '--SDPB | 0'), TIMING)

    def test_reject_setup_hold_and_frequency_failures(self):
        for changed in [TIMING.replace('Setup Violated Endpoints>:0', 'Setup Violated Endpoints>:1'),
                        TIMING.replace('Hold Violated Endpoints>:0', 'Hold Violated Endpoints>:2'),
                        TIMING.replace('28.261(MHz)', '26.999(MHz)'),
                        TIMING.replace('sys_clk hold 0.000 0', 'sys_clk hold -0.001 1')]:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                parse_reports(RESOURCE, changed)

if __name__ == '__main__':
    unittest.main()
