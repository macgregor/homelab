# Research Report: WatchState Deployment and Trakt.tv API Integration

## Objective

Conduct comprehensive research on WatchState deployment and Trakt.tv API authentication to determine: (1) how to create Trakt API applications and authorize WatchState with Trakt accounts, including free tier access and rate limits; (2) WatchState Docker deployment, configuration, and backend integration with Jellyfin and Trakt; (3) the OAuth flow and token persistence in WatchState; (4) Trakt's recommendation features and free vs VIP tier differentiation.

## Executive Summary

WatchState is a lightweight, open-source self-hosted service that syncs watch history and playback state across multiple media backends (Jellyfin, Plex, Emby) and Trakt.tv simultaneously using a simple Docker container deployable at `ghcr.io/arabcoders/watchstate:latest`. Creating a Trakt API application is free and requires no VIP subscription—developers sign up at Trakt.tv, create an application to obtain client credentials, then use standard OAuth 2.0 flows to authorize user access. WatchState handles the OAuth authentication interactively during backend configuration, storing tokens persistently in its SQLite database for automatic refresh (tokens now expire in 24 hours as of March 2025, renewed via refresh tokens). The free Trakt tier supports full watch history syncing and access to recommendation endpoints; VIP features are primarily about quota limits (250 vs 5000 watchlist items, 5 vs 100 personal lists) and ad removal rather than API capability restrictions for core features.

WatchState deployment requires minimal resources (100-200 MB RAM, negligible CPU) with a persistent `/config` volume for its SQLite database (~50-200 MB depending on library size). Configuration is handled through an interactive CLI (`docker exec watchstate console config:add`) or web UI at port 8080, and supports both real-time webhook-based sync (recommended for Jellyfin via its Webhook plugin) and scheduled polling tasks. The service is designed as single-user by default but supports multi-user scenarios through an "identities" system, offers bidirectional sync with conflict detection, and includes safety features like read-only access during imports to prevent cascading conflicts.

## Findings

### Official Documentation and Resources

- **Source**: Trakt API Authentication Documentation
  **URL**: https://docs.trakt.tv/docs/authentication-oauth
  **Author**: Trakt.tv
  **Date**: 2025-03 (current as of March 2025)
  **Activity**: N/A (official vendor documentation)
  **Key points**:
    - Two OAuth flows: Authorization Code Flow (for apps with browser access) and Device Code Flow (for TVs, media centers, CLI tools)
    - Client ID sent via `trakt-api-key` header with every API call
    - Access token used as Bearer token: `Authorization: Bearer <access_token>`
    - Some endpoints are "public" (require only API key), others require full OAuth access token
    - Certain endpoints return more personalized results when OAuth is provided even if authentication is optional
    - VIP-only endpoints return 426 HTTP status code for non-VIP users
    - Refresh tokens handle token renewal without user re-authentication

- **Source**: Trakt API Apiary Documentation
  **URL**: https://trakt.docs.apiary.io/
  **Author**: Trakt.tv
  **Date**: 2025 (current)
  **Activity**: N/A (official vendor documentation)
  **Key points**:
    - Rate limiting applies to all API methods with 429 HTTP status on limit exceeded
    - Separate rate limits for authenticated (user-level) vs unauthenticated (app-level) calls
    - Retry-After header indicates when to retry after rate limit exceeded
    - Recommendations endpoints: `/recommendations/movies` and `/recommendations/shows` with per-user tailored suggestions
    - Trending endpoints return currently popular content
    - Watch history endpoints at `/users/me/history/episodes` (paginated results for authenticated user)
    - Can specify `watched_at` UTC datetime to backfill historical watch timestamps

- **Source**: Trakt API Token Expiration Update (March 2025)
  **URL**: https://github.com/trakt/trakt-api/discussions/495
  **Author**: Trakt.tv (via GitHub Discussions)
  **Date**: 2025-03-20
  **Activity**: Recent announcement (active discussion)
  **Key points**:
    - Access tokens now expire in 24 hours (changed from 3 months as of March 20, 2025)
    - Refresh tokens do not expire in 24 hours (longer expiration period)
    - Apps should automatically use refresh_token to obtain new access_tokens more frequently
    - This change requires app updates to handle more frequent token refresh cycles

- **Source**: WatchState GitHub Repository (README and Documentation)
  **URL**: https://github.com/arabcoders/watchstate
  **Author**: ArabCoders (open source)
  **Date**: 2025-12 (latest commits; last major version v1.8.5+)
  **Activity**: Active project with regular commits, multiple contributors, community discussions
  **Key points**:
    - Docker image: `ghcr.io/arabcoders/watchstate:latest` and `arabcoders/watchstate` on Docker Hub
    - Container is rootless (must match UID:GID of mounted data directory; default 1000:1000)
    - WebUI port: 8080
    - Persistent storage: `/config:rw` for configuration and SQLite database
    - Supports Jellyfin, Plex, Emby backends with many-to-many or one-way sync options
    - Features: webhook event handling, path matching (v1.8.5+), parity checks, stale reference detection
    - Database: SQLite v02 schema with automatic migration on first boot after update
    - Import methods: Scheduled tasks, manual on-demand, webhooks for real-time sync

- **Source**: WatchState FAQ (GitHub)
  **URL**: https://github.com/arabcoders/watchstate/blob/master/FAQ.md
  **Author**: ArabCoders
  **Date**: 2025-12 (current master branch)
  **Activity**: Actively maintained documentation
  **Key points**:
    - Default import every 1 hour, export every 1 hour 30 minutes (configurable via cron expressions)
    - Container crashes on startup typically caused by UID:GID permission mismatches
    - Primary design is single-user; multi-user support via "identities" system (documented separately)
    - Webhooks optional but recommended for Jellyfin due to API bugs in play state tracking
    - Environment variables: WS_CACHE_URL for Redis, WS_DB_MODE for MEMORY mode (high RAM usage), WS_TRUST_PROXY and WS_TRUST_LOCAL for external auth layers
    - Container-level env vars: DISABLE_CRON, DISABLE_CACHE (require restart)
    - SQLite database at `/config/db/watchstate_v01.db` with repair command available
    - Support for file integrity feature with 1-hour per-path caching

### Source Code Repositories

- **Source**: WatchState arabcoders/watchstate on GitHub
  **URL**: https://github.com/arabcoders/watchstate
  **Author**: ArabCoders and community contributors
  **Date**: Last commit 2025-12 (actively maintained)
  **Activity**: 100+ stars, regular commits in last 3 months, active issues/discussions, MIT License
  **Key points**:
    - Open-source service for syncing Jellyfin, Plex, Emby play state without third-party cloud
    - Multi-user support via identities system
    - Bidirectional sync with conflict detection and resolution
    - Webhook event handling from media backends for real-time sync
    - Docker image available on GHCR (ghcr.io/arabcoders/watchstate) and Docker Hub
    - Configuration via interactive CLI: `docker exec watchstate console config:add`
    - Guides available for: backend limitations, identities setup, one-way sync, path matching, three-way sync, two-way sync, webhooks
    - Comprehensive documentation covering all configuration scenarios

- **Source**: Trakt API (trakt/trakt-api) on GitHub
  **URL**: https://github.com/trakt/trakt-api
  **Author**: Trakt.tv
  **Date**: Active repository, regularly updated
  **Activity**: Official Trakt repository, discussions and issue tracking active
  **Key points**:
    - Official RESTful API for TV show and movie tracking
    - Enables synchronization of watch history, ratings, and lists with Trakt.tv profile
    - Extensive media database with provider IDs (tvdb, imdb, tmdb)
    - GitHub Discussions section for API feature requests and clarifications
    - Up-to-date token expiration changes documented in discussions

### Community and Third-Party Sources

- **Source**: WatchState: Sync Watch History Between Jellyfin, Plex, Emby, and Trakt Simultaneously (2026 Guide)
  **URL**: https://jellywatch.app/blog/watchstate-sync-watch-history-jellyfin-plex-emby-trakt-2026
  **Author**: JellyWatch Blog
  **Date**: 2026-01 (current year)
  **Activity**: Recent blog post covering current deployment methods
  **Key points**:
    - Complete Docker Compose setup example with port 8080 exposure
    - Environment variable configuration (WS_TZ for timezone)
    - Volume mounts for persistent config at `/config`
    - Jellyfin backend setup steps: type `jellyfin`, URL (e.g., `http://jellyfin:8096`), Jellyfin API token, target username
    - Jellyfin Webhook plugin integration for real-time sync at `http://watchstate:8080/v1/api/jellyfin/webhook`
    - Trakt backend setup: type `trakt`, OAuth flow during configuration
    - Sync workflow: import → push → sync with conflict resolution
    - Trakt is only backend that syncs ratings (bidirectional)
    - Resource usage: 100-200 MB RAM, negligible CPU, 50-200 MB storage for database
    - Described as "extremely lightweight" (API calls only, no media file processing)
    - Warning: disable existing Trakt plugin in Jellyfin to avoid conflicts

- **Source**: WatchState - Saltbox Docs
  **URL**: https://docs.saltbox.dev/sandbox/apps/watchstate/
  **Author**: Saltbox Documentation
  **Date**: 2025-12 (current)
  **Activity**: Community documentation, regularly maintained
  **Key points**:
    - Docker image: `ghcr.io/arabcoders/watchstate:latest`
    - Default environment variables: WS_TZ, WS_API_AUTO (true), WS_TRUST_PROXY (true), WS_SECURE_API_ENDPOINTS (true)
    - Custom environment variables via `watchstate_role_docker_envs_custom` dict
    - Traefik integration enabled by default (SSO, certificate resolution, wildcard certs)
    - Web port: 8080
    - Container restart policy: unless-stopped
    - Multi-instance support available
    - Autoheal monitoring, Diun update notifications, DNS creation, Docker Controller management enabled
    - Resource limits (CPU, memory, block I/O) available but not set by default
    - User directive: set to match mounted data directory ownership (default `{{ uid }}:{{ gid }}`)

- **Source**: Trakt Forum: Updating Trakt Limits for 2026
  **URL**: https://forums.trakt.tv/t/updating-trakt-limits-for-2026/101592
  **Author**: Trakt.tv Community Forums
  **Date**: 2025-2026 (recent announcements)
  **Activity**: Active discussion with official Trakt responses
  **Key points**:
    - 2026 free tier limits: 250 watchlist items (up from 100), 5 personal lists (up from 2), 100k history items, 10k ratings, 100 notes
    - VIP tier limits: 5000 watchlist items, 100 personal lists, unlimited notes
    - VIP pricing: $30/year first subscription, $60/year renewal (100% price increase from previous pricing)
    - Free users now have collaborative list-making, universal "Watch now" filter, and ability to add 100 personal notes
    - Watch history syncing is available on free tier
    - Recommendations features (see below) are free tier accessible
    - VIP features primarily quota/ad removal focused rather than API capability restrictions

- **Source**: Trakt Create Application Documentation (Kometa Wiki)
  **URL**: https://metamanager.wiki/en/latest/config/trakt/
  **Author**: Kometa Project Documentation
  **Date**: 2025-12 (current)
  **Activity**: Community documentation actively maintained
  **Key points**:
    - Create Trakt API app at https://trakt.tv/oauth/applications/new (free, no VIP required)
    - Sign in to Trakt account (free signup available)
    - Fill in app name, description, site URL (icon optional)
    - Receive client_id and client_secret for OAuth flow
    - Standard OAuth 2.0 implementation with access_token and refresh_token
    - Access token validity period: updated to 24 hours (as of March 2025)
    - Refresh token used to obtain new access_token without user re-authentication

- **Source**: Trakt Free Tier Limitations (AlternativeTo News)
  **URL**: https://alternativeto.net/news/2025/2/trakt-tv-has-set-stricter-limits-for-free-users-and-raised-vip-subscription-prices-by-100-/
  **Author**: AlternativeTo Community News
  **Date**: 2025-02
  **Activity**: News coverage of 2025 Trakt pricing/limit changes
  **Key points**:
    - VIP subscription price doubled to $60/year (from $30/year)
    - Free tier users have updated limits (250 watchlist vs 5000 for VIP)
    - Watch history tracking available on free tier
    - Recommendations engine accessible on free tier
    - Core syncing features not VIP-restricted; primarily quota and interface differences

## Sources

- https://docs.trakt.tv/docs/authentication-oauth
- https://trakt.docs.apiary.io/
- https://github.com/trakt/trakt-api/discussions/495
- https://github.com/arabcoders/watchstate
- https://github.com/arabcoders/watchstate/blob/master/README.md
- https://github.com/arabcoders/watchstate/blob/master/FAQ.md
- https://jellywatch.app/blog/watchstate-sync-watch-history-jellyfin-plex-emby-trakt-2026
- https://docs.saltbox.dev/sandbox/apps/watchstate/
- https://forums.trakt.tv/t/updating-trakt-limits-for-2026/101592
- https://metamanager.wiki/en/latest/config/trakt/
- https://alternativeto.net/news/2025/2/trakt-tv-has-set-stricter-limits-for-free-users-and-raised-vip-subscription-prices-by-100-/

## Metadata

- **Report Date**: 2025-12-05T00:00:00Z
- **Search Queries**: WatchState Jellyfin Trakt.tv integration deployment docker, Trakt.tv API free tier access OAuth authentication requirements 2025, Trakt API rate limits free tier recommendations VIP features, WatchState docker compose configuration environment variables, Trakt recommendations API collaborative filtering free feature, WatchState arabcoders github repository documentation configuration, Trakt.tv watch history sync free tier requirements API endpoint, "WatchState" "Trakt" webhook configuration real-time sync, Trakt API /recommendations endpoint GET trending features free, Trakt free account limitations VIP features 2025 2026, Trakt create application client ID client secret free no premium required, "Trakt" OAuth access token refresh token 7 days expiration
- **Model**: claude-haiku-4-5@20251001
