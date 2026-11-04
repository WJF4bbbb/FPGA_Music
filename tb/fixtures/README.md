# Pre-waveform audio comparison fixtures

These are the original `release/prelim-1104` top and telemetry sources from the supplied archive, before the waveform feature. Only module names and the top's telemetry module reference are renamed, so they can be simulated beside the modified system.

`tb_wave_audio_equivalence` drives both tops through independent external TTP229 pin models and checks every I2S/control output clock and every PCM sample. The external pin models have explicitly shortened propagation/timeout to match the accelerated test SCL; production source timings stay unchanged. Telemetry cadence/baud are accelerated identically in both instances. Audio clocks and the 576-system-clock sample period remain identical.

These files are simulation fixtures only; they are absent from `sources.f` and both Gowin projects.
