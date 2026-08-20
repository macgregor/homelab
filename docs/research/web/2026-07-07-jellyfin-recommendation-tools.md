# Research Report: Media Recommendation Tools for Jellyfin Homelab

## Objective

Research self-hosted and online media discovery/recommendation tools that provide personalized TV show and movie recommendations based on watch history. The user runs a Jellyfin homelab with Sonarr, Radarr, and Jellyseerr, and seeks alternatives to Jellyseerr's trending/popular content discovery that are tailored to personal viewing patterns. Focus on integration with Jellyfin, watch history sync mechanisms, and quality of personalization.

## Executive Summary

The Jellyfin ecosystem offers a diverse range of recommendation approaches spanning fully self-hosted ML-based solutions, cloud-integrated services, and hybrid models. LocalRecs emerges as the most compelling self-hosted option, using TF-IDF embeddings to generate personalized per-user recommendations entirely locally with zero external API calls—requiring only 10+ watched items and consuming minimal resources (~50-100 MB RAM). For users willing to leverage external services, JellyNext bridges Jellyfin and Trakt by creating per-user virtual libraries of Trakt recommendations that integrate seamlessly with Radarr/Sonarr for one-click downloads, while SuggestArr provides AI-powered recommendations via any OpenAI-compatible LLM (including local Ollama instances) plus TMDb similarity matching, with automatic submission to Jellyseerr/Overseerr. Beyond Jellyfin-specific tools, Trakt.tv serves as the most capable standalone recommendation platform with collaborative filtering trained on 4.2 million users, bidirectional watch history sync via WatchState, and export capabilities for AI-powered custom analysis. MovieLens, Letterboxd, and Taste.io each excel in different discovery paradigms—MovieLens for research-grade algorithmic recommendations, Letterboxd for community-curated discovery, and Taste.io for collaborative filtering—though each requires manual watch logging outside the Jellyfin ecosystem.

## Findings

### Official Documentation and Resources

- **Source**: Jellyfin Plugins Directory
  **URL**: https://jellyfin.org/docs/general/server/plugins/
  **Author**: Jellyfin Project
  **Date**: 2025-12
  **Activity**: N/A
  **Key points**:
    - Official registry for Jellyfin plugins available for installation
    - LocalRecs, JellyNext, and other community recommendation tools available through standard plugin installation
    - Plugins include metadata about supported versions and community ratings

- **Source**: Trakt.tv Integration with AI and Collaborative Filtering
  **URL**: https://blog.pmurphs.com/posts/2025/01/streamlining-entertainment-recommendations-with-trakt.tv-and-ai/
  **Author**: PMURPHS
  **Date**: 2025-01
  **Activity**: N/A
  **Key points**:
    - Trakt's recommendation engine uses collaborative filtering with temporal decay weighting
    - Trained on 4.2 million active users with research-grade methodology
    - Supports data export (premium feature) for feeding ratings/reviews into AI tools for custom recommendations
    - Privacy-preserving approach using only authenticated scrobbles, no behavioral advertising signals

- **Source**: Best Movie Tracking Apps in 2026 Comparison
  **URL**: https://www.achriom.com/blog/best-movie-tracking-apps/
  **Author**: Achriom
  **Date**: 2026-01
  **Activity**: N/A
  **Key points**:
    - MovieLens offers research-grade recommendation engine (free, ad-free, since 1997)
    - Letterboxd excels at community-driven discovery through lists and social following
    - Trakt lacks built-in AI but tracks consumption; MovieLens leads pure recommendation quality
    - Achriom (AI librarian with cross-media pattern recognition) and Taste.io (collaborative filtering) noted as specialized alternatives

### Source Code Repositories

- **Source**: LocalRecs — Privacy-First Personalized Recommendations Plugin
  **URL**: https://github.com/rdpharr/jellyfin-plugin-localrecs
  **Author**: rdpharr
  **Date**: 2025-12 (active development)
  **Activity**: Recent commits, starred repository
  **Key points**:
    - Fully local ML-based recommendation using TF-IDF embeddings (~1200-1500 dimensions)
    - Per-user taste profiles built from watch history weighted by recency (365-day half-life)
    - Minimum 10 watched items; quality significantly improves after 30+ items
    - Initial model build: 2-5 minutes; daily refresh: <1 minute; RAM usage: 50-100 MB
    - Virtual libraries created via symlinks (admin creates libraries, sets permissions manually)
    - Works across all Jellyfin clients (web, mobile, Roku, smart TV)
    - Partially watched items may create duplicate "Continue Watching" entries until next refresh
    - GPL-3.0 licensed, C# implementation with HTML UI
    - TV show support noted as "basic" compared to movies

- **Source**: JellyDiscover — Standalone Python Recommendation Engine
  **URL**: https://github.com/AHouseOfBards/JellyDiscover
  **Author**: AHouseOfBards
  **Date**: 2025-12 (active)
  **Activity**: Ongoing commits, community contributions
  **Key points**:
    - Calculates recommendation scores based on Genres, Actors, and Directors
    - Creates virtual libraries using `.strm` files and symlinks (zero-copy, no storage overhead)
    - Self-healing refresh cycle with automatic cleanup of stale entries
    - Adjustable parameters: Seen Penalty (downrank watched content), Collection Boost (favor sequels/franchises), Min Score threshold
    - Web dashboard for settings, scheduling, path configuration
    - Deployment: Windows installer, Docker Compose, native Linux with systemd
    - Cross-platform support (Windows, Linux, Docker)
    - MIT licensed; Python (77.7%) + HTML dashboard (20.9%)

- **Source**: JellyNext — Trakt-Powered Per-User Virtual Libraries Plugin
  **URL**: https://github.com/luall0/jellynext
  **Author**: luall0
  **Date**: 2025-12 (active development)
  **Activity**: Recent commits, maintained with issue responses
  **Key points**:
    - Links each Jellyfin user to personal Trakt account via OAuth 2.0 device flow
    - Creates three types of per-user virtual libraries: Movie Recommendations, Show Recommendations (configurable 1-10 seasons), Next Seasons
    - Background sync every 6 hours (default); smart caching reduces API calls
    - Three download integration modes: Native (direct Radarr/Sonarr API), Jellyseerr (for approval workflows), Webhook (custom HTTP endpoints)
    - Anime detection via Trakt genre; separate folder/quality profile support
    - Watchlist Sync: auto-monitor Trakt watchlist hourly, send new items to download backend
    - `.strm` stub files with `[tmdbid-X]` naming allow Jellyfin metadata providers to fetch artwork without additional keys
    - Automatic token refresh with 75% safety buffer; Trakt tokens rotate with each use

- **Source**: SuggestArr — AI-Powered Media Recommendation and Automation
  **URL**: https://github.com/giuseppe99barchetta/SuggestArr
  **Author**: giuseppe99barchetta
  **Date**: 2025-12 (actively maintained)
  **Activity**: Regular commits, community issues engagement
  **Key points**:
    - Connects Jellyfin/Plex/Emby to Jellyseerr/Overseerr for automated download requests
    - Two-stage pipeline: retrieve watch history + Trakt watches, then match via TMDb similarity or LLM analysis
    - LLM support: any OpenAI-compatible API (OpenAI, Ollama local, OpenRouter, LiteLLM Proxy)
    - Ollama integration: pull model locally, leave API key blank, SuggestArr uses placeholder automatically
    - Falls back to TMDb matching if LLM unavailable (graceful degradation)
    - AI Search (beta): natural-language queries ("psychological thriller 90s with twist") → structured TMDb filters → ranked by watch history
    - Per-user Trakt account linking for enriched watch history
    - Cron job scheduling via web UI; can pause if Seer has pending requests
    - Automatic cleanup of old requests when content not favorited after download
    - External database support (PostgreSQL, MySQL) alongside SQLite
    - MIT licensed; Python (60.4%) + Vue (28.6%)

- **Source**: Recommendarr in media-stack — LLM-Powered Recommendations
  **URL**: https://github.com/navilg/media-stack
  **Author**: navilg
  **Date**: 2025-12 (active stack maintenance)
  **Activity**: Ongoing updates and community contributions
  **Key points**:
    - Recommendarr is an optional Docker Compose profile providing "AI-driven recommendations based on Sonarr/Radarr media"
    - Connects to Sonarr library (TV shows), Radarr library (movies), Jellyfin watchlist/library, optionally Trakt watchlist
    - Uses any OpenAI-compatible LLM via API (hosted service or self-hosted Ollama/LM Studio)
    - Configuration: AI service URL + API key + model selection, then connect Sonarr/Radarr/Jellyfin with service URLs and API keys
    - Recommendation generation: select model, enable Jellyfin watch history toggle, choose language/genres, hit discover
    - Supports VPN or no-VPN deployment modes
    - Integrated with broader *arr stack (Sonarr, Radarr, qBittorrent, Prowlarr, Jellyfin, Seerr)

- **Source**: WatchState — Bidirectional Watch History Sync
  **URL**: https://jellywatch.app/blog/watchstate-sync-watch-history-jellyfin-plex-emby-trakt-2026
  **Author**: WatchState/JellyWatch
  **Date**: 2025-12
  **Activity**: Active self-hosted open-source project
  **Key points**:
    - Bidirectional sync of watched/unwatched status, resume position, play date/time across Jellyfin, Plex, Emby, Trakt
    - Matches content via provider IDs (TMDB, TVDB, IMDB), falls back to title/year or file paths
    - Real-time webhook sync available (no polling delay) plus scheduled sync via cron
    - Conflict resolution: "newest wins" by default, manual overrides via web UI
    - Multi-user support with independent sync profiles per user
    - Lightweight: ~100-200 MB RAM
    - Web UI for monitoring, conflict resolution, configuration
    - Trakt integration serves as "permanent backup"; rebuild server, restore from Trakt export
    - Ratings sync exclusive to Trakt (other platforms have incompatible rating systems)

### Community and Third-Party Sources

- **Source**: Jellyfin AI Recommendations in 2026: LocalRecs, Smart Collections & Privacy-First Discovery
  **URL**: https://jellywatch.app/blog/jellyfin-ai-recommendations-local-privacy-first-2026
  **Author**: JellyWatch Blog
  **Date**: 2025-12
  **Activity**: N/A
  **Key points**:
    - Comprehensive comparison of four recommendation approaches for Jellyfin
    - LocalRecs: TF-IDF ML plugin, fully local, per-user, needs 10+ items, "most exciting plugin of 2026"
    - JellyNext: Trakt-powered, per-user, recommends outside library, requires Trakt account + external API calls
    - Smart Collections (jellyfin-smartlists-plugin): rule-based dynamic lists, fully local, not personalized, simple admin configuration
    - Kometa (formerly Plex Meta Manager): syncs external curated lists (IMDb Top 250, Trakt Trending, Letterboxd), auto-updates, not personalized
    - Recommended layered approach: LocalRecs (personalized) + Smart Collections (dynamic filtering) + Kometa (cultural trends) + Editors Choice (manual curation)
    - TV show support stronger in JellyNext/Kometa than LocalRecs

- **Source**: Slant Comparison: MovieLens vs Letterboxd vs Taste.io
  **URL**: https://www.slant.co/versus/21708/33805/~movielens_vs_letterboxd
  **Author**: Slant Community
  **Date**: 2025-11
  **Activity**: N/A
  **Key points**:
    - MovieLens: research-grade recommendation engine, ad-free, free, no social features, genuine recommendation focus
    - Letterboxd: 14+ million members, beautiful UI, engaged community, excellent discovery through lists/reviews, film-only (no TV/books/music)
    - Trakt ranked higher (2nd) for movie recommendations than Letterboxd (8th) in community voting
    - MovieLens predates all competitors (since 1997), still genuinely competitive on recommendation quality

- **Source**: Taste.io — Collaborative Filtering for Movies & TV
  **URL**: https://www.taste.io/
  **Author**: Taste.io
  **Date**: 2026-01
  **Activity**: N/A
  **Key points**:
    - Describes itself as "personalized movie recommendation app with no commercial bias"
    - Uses collaborative filtering: recommends items based on similarities between users with matching taste profiles
    - Infers interest from watch history; users who agreed in past likely to agree again
    - Designed to match users with like-minded people and recommend based on viewing patterns

- **Source**: Ollama — Local Self-Hosted LLM Integration
  **URL**: https://whatllm.org/best-open-source-llm-2026-ranking
  **Author**: WhatLLM
  **Date**: 2025-12
  **Activity**: N/A
  **Key points**:
    - Ollama is an open-source tool for running LLMs locally without cloud subscription or internet dependency
    - Exposes REST API on port 11434 fully compatible with OpenAI API format
    - Enables apps like SuggestArr to use local models (Mistral, Llama 3, etc.) for recommendation generation
    - Models can be pulled with single command; API key can be omitted for local instances
    - If LLM unavailable, SuggestArr falls back to TMDb-based matching transparently

- **Source**: GitHub Awesome Jellyfin — Plugins and Tools Compilation
  **URL**: https://github.com/awesome-jellyfin/awesome-jellyfin
  **Author**: Awesome Jellyfin Community
  **Date**: 2025-12 (maintained)
  **Activity**: Community contributions, regular updates
  **Key points**:
    - Comprehensive curated list of Jellyfin plugins, themes, and guides
    - References LocalRecs, JellyDiscover, JellyNext, SuggestArr, and other recommendation tools
    - Acts as discovery hub for Jellyfin ecosystem solutions

## Sources

- https://github.com/rdpharr/jellyfin-plugin-localrecs
- https://jellywatch.app/blog/jellyfin-ai-recommendations-local-privacy-first-2026
- https://github.com/AHouseOfBards/JellyDiscover
- https://github.com/awesome-jellyfin/awesome-jellyfin
- https://gzuo.me/blog/jellyrec/
- https://magazine.ediary.site/blog/jellyfin-ai-recommendations-streamystats-and
- https://features.jellyfin.org/posts/2737/local-recommendation-engine-for-jellyfin
- https://github.com/giuseppe99barchetta/SuggestArr
- https://github.com/luall0/jellynext
- https://github.com/navilg/media-stack
- https://news.ycombinator.com/item?id=43230790
- https://jellywatch.app/blog/watchstate-sync-watch-history-jellyfin-plex-emby-trakt-2026
- https://github.com/jellyfin/jellyfin-plugin-trakt
- https://blog.pmurphs.com/posts/2025/01/streamlining-entertainment-recommendations-with-trakt.tv-and-ai/
- https://www.slant.co/versus/21708/33805/~movielens_vs_letterboxd
- https://www.achriom.com/blog/best-movie-tracking-apps/
- https://www.saashub.com/compare-letterboxd-vs-tv-time
- https://alternativeto.net/software/movielens/
- https://www.saashub.com/compare-movielens-vs-letterboxd
- https://www.taste.io/
- https://whatllm.org/best-open-source-llm-2026-ranking
- https://jellyfin.org/docs/general/server/plugins/
- https://giuseppe99barchetta.github.io/SuggestArr/
- https://localtonet.com/blog/how-to-self-host-ollama
- https://daily.dev/blog/running-llms-locally-ollama-llama-cpp-self-hosted-ai-developers/

## Metadata

- **Report Date**: 2026-07-07T14:35:00Z
- **Search Queries**: Jellyfin recommendation engine plugin watch history, self-hosted media recommendation system Sonarr Radarr, Trakt.tv integration Jellyfin watch history sync, Trakt recommendation features personalized discovery, Letterboxd Movielens TV Time media recommendation comparison, Taste.io recommendation engine collaborative filtering watch history, SuggestArr Jellyfin recommendation AI watch history, Jellynext Trakt personalized recommendations virtual libraries 2026, media recommendation comparison Taste.io Trakt Letterboxd MovieLens, JellyWatch blog Jellyfin recommendation AI 2026, Ollama local LLM Jellyfin SuggestArr recommendation self-hosted
- **Model**: claude-haiku-4-5@20251001
