# Research Report: Radarr Cam/Telesync/Telecine Prevention Strategies

## Objective

Determine best practices for preventing Radarr from grabbing low-quality cam, telesync, and telecine versions of movies before official release. Identify specific quality profile settings, TRaSH Guides custom formats, minimum availability configurations, and Prowlarr-level filtering strategies to block pre-release grabs.

## Executive Summary

Preventing Radarr from downloading cam/telesync/telecine releases requires a multi-layered approach combining quality profile configuration, custom format scoring, and minimum availability constraints. The most effective strategy is setting Minimum Availability to "Released" (paired with an Availability Delay of −14 to −21 days), which blocks Radarr from searching until a movie has an official digital or physical release date. This eliminates the window in which cam recordings appear while films are still in theaters.

Within quality profiles, users should explicitly uncheck the CAM, TELESYNC, TELECINE, REGIONAL, DVDSCR quality tiers to prevent them from being considered. However, unchecking alone is insufficient—TRaSH Guides documents that custom formats with strong negative scores (−10,000) provide the real guardrail. The recommended custom formats are LQ and LQ (Release Title) for low-quality groups, Line/Mic Dubbed for cam-style audio capture, and BR-DISK for uncompressed disc releases. These formats should be scored at −10,000 in the quality profile, ensuring that even if other positive-scoring formats match, the cumulative score will fall below the minimum custom format score (typically set to 0), causing Radarr to reject the release.

Prowlarr offers limited direct filtering for release types; the primary defense occurs in Radarr's quality profile and custom format engine. Configuration via Recyclarr or manual JSON import makes TRaSH custom formats maintainable and reusable across multiple instances. The key principle is that Radarr evaluates releases in order of quality first, then custom format score, so quality tier unchecking provides the first-line defense while custom formats act as a secondary gatekeeper.

## Findings

### Official Documentation and Resources

- **Source**: Radarr Settings — Servarr Wiki
  **URL**: https://wiki.servarr.com/radarr/settings
  **Author**: Servarr Community
  **Date**: 2025-12 (current version)
  **Activity**: N/A
  **Key points**:
    - Minimum Availability setting controls when Radarr considers a movie available for download
    - Four options: Announced, In Cinemas, Released, PreDB
    - Released setting is recommended for avoiding cam grabs; delays searching until official digital/physical release date
    - Can be combined with Availability Delay setting (−14 to −21 days) for additional buffer

- **Source**: How to set up Quality Profiles — TRaSH Guides
  **URL**: https://trash-guides.info/Radarr/radarr-setup-quality-profiles/
  **Author**: TRaSH Guides Community
  **Date**: 2025-11
  **Activity**: N/A
  **Key points**:
    - Quality Profiles consist of: quality definitions (allowed tiers), custom formats (scoring), and cutoff settings
    - Recommends unchecking CAM, TELESYNC, TELECINE, HARDCODED SUBTITLES in quality definitions
    - Minimum Custom Format Score should be set to 0, with unwanted formats scored at −10,000 to prevent downloads
    - Quality tier selection is the first decision gate; custom formats provide secondary filtering
    - "Quality trumps all" in Radarr's priority order: Quality > Custom Format Score > Protocol

- **Source**: Radarr Collection of Custom Formats — TRaSH Guides
  **URL**: https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/
  **Author**: TRaSH Guides Community
  **Date**: 2025-11
  **Activity**: N/A
  **Key points**:
    - LQ: Collection of known low-quality groups; score at −10,000
    - LQ (Release Title): Low-quality indicators in release title; score at −10,000
    - Line/Mic Dubbed: Audio captured via line-in or microphone (common in cam/telesync); score at −10,000
    - BR-DISK: Full Blu-ray uncompressed disc structures; score at −10,000
    - No-RlsGroup: Releases missing group tags (often low-quality); score at −10,000
    - Obfuscated: Deliberately obscured filenames (suspicious/low-quality); score at −10,000
    - x265 (no HDR/DV): x265 without HDR or Dolby Vision; score at −10,000
    - Upscaled: Content upscaled from lower resolution; score at −10,000

- **Source**: Radarr — Quality Definition Specifications (GitHub Wiki)
  **URL**: https://github.com/Radarr/Radarr/wiki/Built-In-Qualities
  **Author**: Radarr Project
  **Date**: 2025-06
  **Activity**: Active maintenance (referenced in current Radarr versions)
  **Key points**:
    - CAM: Theater rip with hand-held camera; poor picture/sound quality
    - TELESYNC: Same as CAM but uses external audio source (theater audio jack)
    - TELECINE: Film copied from reels via telecine machine; good picture/sound but uncommon
    - REGIONAL: Early region-specific releases from limited markets
    - DVDSCR: Screener copy from DVD promotional materials
    - All these can be unchecked/disabled in quality profiles

- **Source**: Minimum Availability — Radarr GitHub Wiki
  **URL**: https://github.com/Radarr/Radarr/wiki/Minimum-Availability
  **Author**: Radarr Project
  **Date**: 2025-06
  **Activity**: N/A
  **Key points**:
    - Announced: Searches immediately when movie added; no protection against cams
    - In Cinemas: Searches on theatrical date; inadequate protection (cams appear during theatrical run)
    - Released: Waits for official digital/physical release date; BEST option for preventing cams
    - PreDB: Waits for scene release in PreDB database; moderate protection but less reliable than Released
    - Released + Availability Delay (−14 to −21 days) is the recommended configuration for cam prevention

### Source Code Repositories

- **Source**: TRaSH-Guides/Guides — Radarr Collection of Custom Formats
  **URL**: https://github.com/TRaSH-Guides/Guides/blob/master/docs/Radarr/Radarr-collection-of-custom-formats.md
  **Author**: TRaSH-Guides Community
  **Date**: 2025-11 (last commit)
  **Activity**: Active (regular updates for new custom formats and indexer changes)
  **Key points**:
    - Canonical source for TRaSH custom format definitions in JSON format
    - Custom formats organized by category: Unwanted, Streaming Services, Audio, Video, Source, Release Type
    - Contains JSON templates for automated import via Recyclarr or manual Radarr import
    - LQ and LQ (Release Title) formats specifically target low-quality group releases
    - All unwanted formats indexed with score recommendations (typically −10,000)

- **Source**: TRaSH-Guides/Guides — How to set up Quality Profiles (GitHub)
  **URL**: https://github.com/TRaSH-Guides/Guides/blob/master/docs/Radarr/radarr-setup-quality-profiles.md
  **Author**: TRaSH-Guides Community
  **Date**: 2025-11 (last commit)
  **Activity**: Active (regularly synchronized with web version)
  **Key points**:
    - Complete reference for quality profile configuration including SQP-1 (2160p) and SQP-2 (1080p) variants
    - Score hierarchy: Remux tiers (+1950/+1900/+1850), HD Bluray (+1800/+1750/+1700), WEB tiers (+1700/+1650/+1600)
    - Unwanted content (LQ, BR-DISK, x265 HD) all scored at −10,000 for universal rejection
    - Custom format scoring is cumulative; minimum score of 0 blocks any release where unwanted formats outnumber preferred ones
    - Provides context-specific score sets for anime, French multi-language, and standard English profiles

- **Source**: Radarr/Radarr — GitHub Issues & Feature Requests
  **URL**: https://github.com/Radarr/Radarr/issues/1157
  **Author**: Radarr Community (Open Source)
  **Date**: 2025-01 (recent discussion)
  **Activity**: Active discussion (feature request: allow hiding unwanted quality definitions in UI)
  **Key points**:
    - Users report that unchecking CAM and TELESYNC alone does NOT prevent downloads
    - Position in quality tier hierarchy still affects release selection even when unchecked
    - Custom formats are the recommended approach rather than quality tier unchecking alone
    - Feature request ongoing to hide CAM, TELESYNC from searches unless explicitly needed

### Community and Third-Party Sources

- **Source**: Sonarr and Radarr Quality Settings Guide (Including 4K) — Evoseedbox Wiki
  **URL**: https://evoseedbox.com/wiki/sonarr-radarr-quality-settings-4k/
  **Author**: Evoseedbox Community
  **Date**: 2025-09
  **Activity**: Actively maintained for seedbox users
  **Key points**:
    - Explicit guidance: Avoid CAM recordings, Telecine, Telesync, hardcoded subtitles
    - Recommended 1080p profile hierarchy: Bluray-1080p > WEB-DL 1080p > HDTV-1080p > Bluray-720p > WEB-DL 720p
    - 4K profile hierarchy: Bluray-2160p Remux > Bluray-2160p > WEB-DL 2160p
    - Recommends custom formats for x265/HEVC preference control and unwanted source filtering
    - Practical examples with file size ranges for each quality tier

- **Source**: TRaSH Guides and Recyclarr: Automate Perfect Quality Profiles for Radarr and Sonarr — JellyWatch Blog
  **URL**: https://jellywatch.app/blog/trash-guides-recyclarr-radarr-sonarr-quality-profiles-jellyfin-2026
  **Author**: JellyWatch Community
  **Date**: 2026-01
  **Activity**: Recent (2026)
  **Key points**:
    - Recyclarr tool automates TRaSH custom format and quality profile sync to Radarr/Sonarr instances
    - Eliminates manual JSON import and profile setup
    - Allows templating multiple profiles with context-specific score sets (anime, french, standard)
    - Describes the cumulative scoring model: matched custom formats sum together to determine if release meets minimum score threshold
    - Guide sync prevents manual setup errors and keeps profiles current with TRaSH recommendations

- **Source**: Radarr Setup & Configuration Guide (qBittorrent, Plex) — Rapid Seedbox
  **URL**: https://www.rapidseedbox.com/blog/guide-to-radarr
  **Author**: Rapid Seedbox Community
  **Date**: 2025-11
  **Activity**: Regularly updated for production seedbox deployments
  **Key points**:
    - Availability Delay recommendation: Use "Released" + −14 to −21 day delay to allow quality releases before Radarr searches
    - Delay timer starts from release upload time, not detection time
    - Allows multiple release versions to appear before Radarr grabs the single best match
    - Prevents problematic early releases (cams, screeners, poor encodes)
    - Practical guide for seedbox users balancing automation with quality control

- **Source**: Recyclarr Quality Profiles Reference — Recyclarr Documentation
  **URL**: https://recyclarr.dev/reference/configuration/quality-profiles/
  **Author**: Recyclarr Project
  **Date**: 2025-11
  **Activity**: Active (used by hundreds of Arr deployment instances)
  **Key points**:
    - `min_format_score` property maps to Radarr's "Minimum Custom Format Score" setting (default: 0)
    - `min_upgrade_format_score` controls whether to upgrade an already-downloaded release based on custom format score
    - When using `trash_id`, Recyclarr automatically syncs quality tiers and custom format scores from TRaSH Guides
    - Can override guide values with explicit properties (e.g., change a custom format score locally)
    - `reset_unmatched_scores` zeros out CF scores not managed by Recyclarr, preventing score drift

- **Source**: Optimizing Movie Quality in Radarr using TRaSH Guides Custom Formats — ElfHosted Documentation
  **URL**: https://docs.elfhosted.com/guides/media/optimize-movie-quality-with-trash-custom-formats/
  **Author**: ElfHosted (Hosted Arr Platform)
  **Date**: 2025-10
  **Activity**: Actively maintained for platform users
  **Key points**:
    - Step-by-step guide for importing TRaSH custom formats into Radarr
    - Emphasizes that custom formats are fine-tuning tools, not primary filters
    - Primary decision gate is quality tier selection
    - Recommends copying JSON from TRaSH Collection, pasting into Radarr's Custom Format JSON box, and importing
    - Warns against adding all available formats—add only those relevant to your library and rejection criteria

## Sources

- https://wiki.servarr.com/radarr/settings
- https://trash-guides.info/Radarr/radarr-setup-quality-profiles/
- https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/
- https://github.com/Radarr/Radarr/wiki/Built-In-Qualities
- https://github.com/Radarr/Radarr/wiki/Minimum-Availability
- https://github.com/TRaSH-Guides/Guides/blob/master/docs/Radarr/Radarr-collection-of-custom-formats.md
- https://github.com/TRaSH-Guides/Guides/blob/master/docs/Radarr/radarr-setup-quality-profiles.md
- https://github.com/Radarr/Radarr/issues/1157
- https://evoseedbox.com/wiki/sonarr-radarr-quality-settings-4k/
- https://jellywatch.app/blog/trash-guides-recyclarr-radarr-sonarr-quality-profiles-jellyfin-2026
- https://www.rapidseedbox.com/blog/guide-to-radarr
- https://recyclarr.dev/reference/configuration/quality-profiles/
- https://docs.elfhosted.com/guides/media/optimize-movie-quality-with-trash-custom-formats/

## Metadata

- **Report Date**: 2026-07-07T10:50:00Z
- **Search Queries**: Radarr quality profiles cam telesync telecine prevention, TRaSH Guides Radarr custom formats cam TS TC blocking, Radarr minimum availability announced in-cinemas released preDB, site:trash-guides.info Radarr custom formats unwanted, Radarr minimum custom format score quality profile gatekeeper, Prowlarr filter cam telesync telecine release type indexer settings, "Radarr" "quality definition" cam telesync telecine disable, Radarr settings quality definition minimum availability released, TRaSH Guides Radarr "Unwanted" custom format JSON cam, Radarr "quality profile" "LQ" "-10000" custom format score, site:github.com Radarr wiki "quality definition" cam telesync disabled, Radarr "availability delay" days released cinematic prevent cam, Radarr "Settings" "Quality" "CAM" "TELESYNC" unchecked disabled default
- **Model**: claude-haiku-4-5@20251001
