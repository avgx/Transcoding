bash-3.2$ ./mp4info h265-stream-start.bin
File:
  major brand:      mp42
  minor version:    0
  compatible brand: mp42
  compatible brand: mp41
  compatible brand: isom
  compatible brand: iso2
  fast start:       yes

Movie:
  duration:   0 (movie timescale units)
  duration:   0 (ms)
  time scale: 3000
  fragments:  yes

Found 2 Tracks
Track 1:
  flags:        7 ENABLED IN-MOVIE IN-PREVIEW
  id:           1
  type:         Video
  duration: 0 ms
  language: und
  media:
    sample count: 0
    timescale:    3000
    duration:     0 (media timescale units)
    duration:     0 (ms)
    bitrate (computed): 0.000 Kbps
    sample count with fragments: 0
    duration with fragments:     0
    duration with fragments:     0 (ms)
  display width:  704.000000
  display height: 480.000000
  Sample Description 0
    Coding:       hvc1 (H.265)
    Codec String: hvc1.1.6.L90.b0
    HEVC Profile Space:       0
    HEVC Profile:             1 (Main)
    HEVC Profile Compat:      60000000
    HEVC Level:               3.0
    HEVC Tier:                0
    HEVC Chroma Format:       1 (4:2:0)
    HEVC Chroma Bit Depth:    8
    HEVC Luma Bit Depth:      8
    HEVC Average Frame Rate:  0
    HEVC Constant Frame Rate: 0
    HEVC NALU Length Size:    4
    HEVC Sequences:
      {
        Array Completeness=0
        Type=32 (VPS_NUT - Video parameter set)
        40010c01ffff016000000300b0000003000003005aac0c0000030004000003007aa8
      }
      {
        Array Completeness=0
        Type=33 (SPS_NUT - Sequence parameter set)
        420101016000000300b0000003000003005aa0058201e1636b92452fcdc14181410000030001000003001ea1
      }
      {
        Array Completeness=0
        Type=34 (PPS_NUT - Picture parameter set)
        4401c0f2c68d03b240
      }
    Width:       704
    Height:      480
    Depth:       24
Track 2:
  flags:        7 ENABLED IN-MOVIE IN-PREVIEW
  id:           2
  type:         Audio
  duration: 0 ms
  language: und
  media:
    sample count: 0
    timescale:    8000
    duration:     0 (media timescale units)
    duration:     0 (ms)
    bitrate (computed): 0.000 Kbps
    sample count with fragments: 0
    duration with fragments:     0
    duration with fragments:     0 (ms)
  Sample Description 0
    Coding:       mp4a (MPEG-4 Audio)
    Codec String: mp4a.40.2
    Stream Type: Audio
    Object Type: MPEG-4 Audio
    Max Bitrate: 0
    Avg Bitrate: 0
    Buffer Size: 0
    MPEG-4 Audio Object Type: 2 (AAC Low Complexity)
    MPEG-4 Audio Decoder Config:
      Sampling Frequency: 8000
      Channels: 1
    Sample Rate: 8000
    Sample Size: 16
    Channels:    1
