---
name: media-playback-hardware
description: >
  Load when troubleshooting audio/video playback issues, configuring Jellyfin
  client settings, or working with Shield TV, Samsung TV, or soundbar integration.
  Covers hardware capabilities, connection topology, and optimal settings.
categories: [media, hardware]
tags: [jellyfin, shield, samsung, soundbar, audio, hdmi, arc]
related_docs:
  - docs/appendix/media-services.md
complexity: intermediate
---

# Media Playback Hardware

Reference for the media playback chain: Nvidia Shield TV (client) -> Samsung Q90T (display) -> Samsung HW-B750F (audio). Covers hardware capabilities, connection topology, and configuration that affects media acquisition decisions in Radarr/Sonarr.

## Hardware

| Device | Model | Key Capabilities |
|--------|-------|-----------------|
| Media client | Nvidia Shield TV 2019 | HDMI 2.0b, 4K@60Hz, HDR10, can output all audio formats |
| TV | Samsung Q90T (2020) | 4K QLED, 120 local dimming zones, HDMI eARC on port 3, no Dolby Vision |
| Soundbar | Samsung HW-B750F (2025) | 5.1 channel, ARC only (not eARC), HDMI IN + HDMI OUT (ARC) |

## Audio Format Support

The soundbar is the limiting factor in the audio chain. It determines what formats are usable end-to-end.

| Format | Soundbar Support | Notes |
|--------|-----------------|-------|
| Dolby Digital (AC3) 5.1 | Yes | Primary surround format |
| DTS 5.1 | Yes | Secondary surround format |
| PCM Stereo | Yes | Fallback for all content |
| Dolby Digital Plus (E-AC3) | No | |
| Dolby TrueHD | No | Common on Blu-ray rips; often carries 7.1/Atmos |
| Dolby Atmos | No | Requires Q-series or higher Samsung soundbar |
| DTS-HD Master Audio | No | |
| DTS:X | No | |

### Implications for media acquisition

Files with **only** advanced audio formats (TrueHD 7.1, DTS-HD MA, DTS:X) will produce **no audio** if the Shield attempts to passthrough the raw bitstream. The Shield must be configured to decode these formats internally and re-encode as DD 5.1. See [Shield audio configuration](#nvidia-shield-tv-2019-audio-settings) below.

Files that include both an advanced track (e.g., TrueHD 7.1 Atmos) and a compatibility track (e.g., DD 5.1 or DTS 5.1) work fine -- the player selects the compatible track.

Radarr/Sonarr custom formats cannot distinguish releases with 7.1-only audio from those with 7.1 + 5.1 compatibility tracks, since release names only mention the primary audio format. The fix lives at the playback layer, not the acquisition layer.

## Connection Topology

The recommended topology routes audio directly through the soundbar, bypassing Samsung's problematic audio passthrough:

```
Shield (HDMI OUT) --> Soundbar (HDMI IN) --> TV (HDMI 3 / ARC)
```

This ensures the Shield delivers audio directly to the soundbar without Samsung TV processing. Video passes through the soundbar to the TV.

### Why not Shield -> TV -> Soundbar?

- Samsung TVs do **not** reliably passthrough DTS audio formats via ARC
- The HW-B750F lacks eARC, so the TV's eARC capability provides no benefit
- Routing through the TV adds processing latency (~200ms) without quality improvement

### Alternative: TV-centric setup

If you prefer single-point input switching or Q-Symphony (synchronized TV + soundbar speakers):

- Connect Shield to Q90T HDMI port 1, 2, or 4
- Connect soundbar to HDMI 3 via ARC
- Accept that DTS content will not pass through (Samsung limitation) -- only Dolby Digital works reliably

## Device Configuration

### Jellyfin Client Settings (Shield TV)

**Playback Settings > Audio**

| Setting | Value | Reason |
|---------|-------|--------|
| Bitstream Dolby Digital audio | Enabled | Passes DD bitstream to soundbar for decoding |
| Audio output | Direct | Sends audio to Android audio HAL |

Only DD bitstream is enabled. When the client encounters a format it can't bitstream (TrueHD, DTS-HD MA, etc.), it either decodes the audio client-side to PCM or requests server-side transcoding to a compatible format.

### Jellyfin Server Transcoding

Transcoding is enabled on the server with Raspberry Pi V4L2 hardware acceleration. The transcode cache lives on node-local storage (not NFS) for performance. Configuration is in `/config/encoding.xml` inside the Jellyfin pod.

| Setting | Value |
|---------|-------|
| Hardware acceleration | v4l2m2m (Raspberry Pi V4L2) |
| Hardware encoding | Enabled |
| HW decoding codecs | H.264, VC1 |
| Transcode path | `/node-local/transcode` |
| Encoding threads | -1 (auto) |

When the Shield client can't direct-play an audio format (e.g., TrueHD 7.1), the server transcodes just the audio to a compatible format while direct-streaming the video. This avoids expensive video transcoding while ensuring audio compatibility.

### Nvidia Shield TV 2019 Audio Settings

**Settings > Device Preferences > Display & Sound > Advanced sound settings**

Set **Available formats** to **Manual** and configure:

| Format | Setting | Reason |
|--------|---------|--------|
| AC3 (Dolby Digital) | Enable | Soundbar supports DD 5.1 |
| DTS | Enable | Soundbar supports DTS 5.1 |
| E-AC3 (Dolby Digital+) | Disable | Soundbar cannot decode |
| Dolby Atmos | Disable | Soundbar cannot decode |
| Dolby MAT | Disable | Soundbar cannot decode |
| Dolby TrueHD | Disable | Soundbar cannot decode |

Additional settings:

| Setting | Value | Reason |
|---------|-------|--------|
| Dolby Audio Processing | Off | Unnecessary transcoding; can cause sync issues |
| Surround Sound | Auto or Always | |
| HDMI Fixed Volume | On | Lets soundbar control volume |

With only AC3 and DTS enabled, the Shield decodes all advanced formats internally (TrueHD 7.1, Atmos, DTS-HD MA, DTS:X) and re-encodes as DD 5.1 before sending to the soundbar. This solves the 7.1-only audio problem at the playback layer.

### Nvidia Shield TV 2019 Display Settings

**Settings > Device Preferences > Display & Sound**

| Setting | Value | Notes |
|---------|-------|-------|
| Resolution | 4K 59.940 Hz HDR10 Ready | 59.940 Hz for proper 24p movie pulldown |
| Match Content Color Space | On | Proper SDR/HDR color switching |
| Match Content Dynamic Range | On | Automatic SDR/HDR switching |
| Color Space | Auto | Shield selects optimal color space per content |
| AI Upscaling | Personal preference | Test with split-screen comparison |

### Samsung Q90T Audio Settings

**Settings > Sound > Expert Settings**

| Setting | Value | Reason |
|---------|-------|--------|
| HDMI eARC Mode | Auto | Enables ARC/eARC detection |
| Digital Output Audio Format | Auto or Passthrough | Passthrough reduces ~200ms latency |
| HDMI Input Audio Format | Bitstream | Sends multi-channel audio to soundbar |
| Dolby Atmos Compatibility | On | Allows Dolby processing chain |
| Digital Output Audio Delay | 0 | Adjust if lip sync issues occur |
| Auto Volume | Off | Prevents volume fluctuations |

**Settings > General > External Device Manager**

| Setting | Value | Reason |
|---------|-------|--------|
| Anynet+ (HDMI-CEC) | On | Required for ARC to function |

**Settings > Sound > Sound Output**: Select soundbar when detected.

### Samsung Q90T Picture Settings

See `docs/appendix/media-playback-hardware-video.md` (TODO) or reference the detailed settings below.

**SDR (Movie/Filmmaker mode):** Backlight 35, Contrast 45, Local Dimming Standard, Contrast Enhancer Off, Gamma 2.2, Color Tone Warm2. Disable all Eco settings and Adaptive Picture/Intelligent Mode.

**HDR (Movie/Filmmaker mode):** Backlight 50 (required), Contrast 50, Local Dimming High, ST.2084 +1, Shadow Detail +1, Contrast Enhancer Low, Color Tone Warm2.

**Key trade-off:** Local Dimming High causes subtitle-triggered dimming. Drop to Standard or Low if subtitles dim the screen.

## Firmware

| Device | Check via | Notes |
|--------|-----------|-------|
| Samsung Q90T | Settings > Support > Software Update | Updates fix audio routing bugs where TV reverts to internal speakers |
| Samsung HW-B750F | SmartThings app or USB update | |
| Nvidia Shield | Settings > Device Preferences > About > System Upgrade | Version 9.1.1+ fixed CEC volume and audio dropout issues |

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No audio from soundbar | Anynet+ disabled, or soundbar not on TV ARC input | Enable Anynet+ on both; verify soundbar shows "TV ARC" |
| No audio on 7.1/Atmos content | Shield passing through format soundbar can't decode | Set Shield audio formats to Manual; enable only AC3 + DTS |
| Audio drops or crackles | Bad HDMI cable or handshake issue | Replace cable; power cycle TV first, then soundbar, then Shield |
| Lip sync delay | Processing latency | Adjust Shield Audio Video Sync slider; or TV Digital Output Audio Delay |
| TV reverts to internal speakers | Known Samsung bug | Hard power cycle TV (unplug, not standby); reselect soundbar |
| HDR content looks dark | Backlight not maxed for HDR | Set Backlight to 50; enable ST.2084 +1; check Eco settings are off |
| Subtitles dim the screen | Local Dimming on High | Drop Local Dimming to Standard or Low |
