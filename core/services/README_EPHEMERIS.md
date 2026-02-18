# Ephemeris System - Real-Time Orbital Positions

## Overview

The ephemeris system fetches real planetary positions from NASA JPL Horizons and maps them to game time. This provides scientifically accurate orbital positions for all celestial bodies.

## How It Works

### Time Mapping
- **1:1 Day Mapping**: Current real-world day-of-year maps to same day in 2112
- Example: February 18, 2026 (day 49) → February 18, 2112 (day 49)

### Data Fetching
1. System calculates current day-of-year **in UTC**
2. Fetches positions for **today** and **tomorrow** from JPL Horizons
3. Positions represent midnight (00:00 UTC) on each date
4. Data is cached for the entire day

**CRITICAL: UTC Timezone Alignment**
- JPL Horizons API uses UTC for all timestamps
- All system time calculations use UTC (not local time)
- This ensures accurate positions regardless of user's timezone
- Example: User in PST sees same planetary positions as user in JST

### Real-Time Interpolation
Throughout each 24-hour period, positions are interpolated:
```
current_position = position_today.lerp(position_tomorrow, fraction_of_day_elapsed)
```

Where `fraction_of_day_elapsed` is calculated from the current system time:
```
fraction = (hours * 3600 + minutes * 60 + seconds) / 86400
```

This means:
- At midnight UTC (00:00): fraction = 0.0 → shows today's JPL position
- At noon UTC (12:00): fraction = 0.5 → midpoint between today and tomorrow
- At 23:59:59 UTC: fraction ≈ 1.0 → shows tomorrow's JPL position

### Accuracy for Fast-Moving Objects

**Mercury** (fastest orbit: 88 Earth days):
- Moves ~4.09° per Earth day
- In 1 hour: ~0.17° (clearly visible on solar map)
- In 15 minutes: ~0.04° (subtle but detectable with zoom)

**Linear interpolation** provides excellent accuracy:
- JPL positions are exact at midnight UTC
- Positions at other times are linearly interpolated
- Error is negligible because:
  - Orbital motion is nearly linear over 24 hours
  - Planets are not accelerating significantly in a single day
  - Maximum error occurs at ~12 hours (midday)
  - For Mercury: max error < 0.001 AU (~150,000 km) at midday
  - This is visually imperceptible at solar system scale

**Verification**: Compare interpolated positions with JPL Horizons hourly data to confirm accuracy.

### Data Refresh
- At midnight each day, the system:
  1. Shifts "tomorrow" data to "today"
  2. Fetches new "tomorrow" data
  3. Continues seamless interpolation

## Architecture

### Components

**HTTPFetcher Service** (`core/services/http_fetcher.gd`)
- Autoload service for all HTTP requests
- Handles async requests, timeouts, retries
- Emits signals on completion/failure
- Can be replaced with server API calls

**EphemerisData** (`core/data/ephemeris_data.gd`)
- Pure data class (RefCounted)
- Server-compatible: static parsing methods have no Godot dependencies
- Fetches data via HTTPFetcher service
- Falls back to placeholder circular orbits if API unavailable

**CelestialData** Integration
- Checks `use_real_ephemeris` flag
- Falls back to simple orbital mechanics if disabled
- Allows testing both systems

### Server Compatibility

The system is designed for easy migration to a Linux server:

**Current (Godot Client)**:
```
EphemerisData → HTTPFetcher → JPL Horizons API
```

**Future (Linux Server)**:
```
Game Client → Server API → Cached Ephemeris Data
                          ↓
                    Linux Cron Job → JPL Horizons API
```

**Static Methods** (server-compatible):
- `EphemerisData._build_jpl_url()` - Constructs JPL API URLs
- `EphemerisData.parse_jpl_response()` - Parses JSON/CSV responses
- `EphemerisData.get_current_day_of_year()` - Date calculations
- `EphemerisData.get_fraction_of_day_elapsed()` - Time interpolation

These methods have no Godot dependencies and can run on any platform.

## JPL Horizons API

### Request Format
```
GET https://ssd.jpl.nasa.gov/api/horizons.api?
    format=json&
    COMMAND='499'&              # Mars = 499
    EPHEM_TYPE='VECTORS'&       # Position vectors
    CENTER='@0'&                # Solar System Barycenter
    START_TIME='2112-02-18'&    # Midnight UTC
    STOP_TIME='2112-02-18'&
    STEP_SIZE='1 d'&
    VEC_TABLE='2'&              # Positions only
    OUT_UNITS='AU-D'&           # Astronomical Units
    CSV_FORMAT='YES'
```

### Response Format
```json
{
  "result": "...CSV data...\n$$SOE\n2459689.5, 1.234, 5.678, 0.123, ...\n$$EOE\n..."
}
```

The CSV data between `$$SOE` (Start of Ephemeris) and `$$EOE` (End of Ephemeris) contains:
- Column 1: Julian Date
- Column 2: X coordinate (AU)
- Column 3: Y coordinate (AU)
- Column 4: Z coordinate (AU, ignored in 2D game)

### Body IDs
- Mercury: 199
- Venus: 299
- Earth: 399
- Mars: 499
- Jupiter: 599
- Saturn: 699
- Uranus: 799
- Neptune: 899

## Testing

### Enable Real Ephemeris
In `core/data/celestial_data.gd`:
```gdscript
static var use_real_ephemeris: bool = true
```

### Monitor Console Output
```
Fetching ephemeris data for day 49 of year 2112...
HTTP request started: https://ssd.jpl.nasa.gov/api/horizons.api?...
HTTP request completed: ... (code 200)
Parsed position for Mercury: (0.123, 0.456) AU
...
All ephemeris fetches complete
```

### Fallback Behavior
If JPL API is unavailable:
```
Failed to fetch Mercury: Request timeout after 15.0 seconds
Some or all JPL fetches failed - using placeholder data
```

System automatically falls back to circular orbit placeholders.

## Performance

- **Initial fetch**: 8 planets × 2 days = 16 HTTP requests
- **Caching**: Data cached for entire day (~24 hours)
- **Daily refresh**: Minimal - only fetches next day (8 requests)
- **Interpolation**: Real-time, no network calls

## Server Migration Guide

### Phase 1: Current (Client-side fetching)
- Game fetches directly from JPL Horizons
- Simple, no server required
- Higher latency (each client makes requests)

### Phase 2: Server-side caching
1. Set up Linux server with cron job
2. Cron fetches daily ephemeris at 00:00 UTC
3. Store in Redis/database with key `ephemeris:{year}:{day}`
4. Expose API endpoint: `GET /api/ephemeris?day=49&year=2112`
5. Game clients query server instead of JPL
6. Reduce JPL API load, improve response time

### Phase 3: Pre-computation
1. Pre-compute entire year of ephemeris data
2. Store in database/static files
3. Serve cached data (instant response)
4. Update yearly or when orbital calculations need refinement

## Troubleshooting

**"HTTPFetcher not available"**
- Check project.godot autoload registration
- Verify `HTTPFetcher="*res://core/services/http_fetcher.gd"`

**"Failed to parse JPL response"**
- Check internet connectivity
- Verify JPL Horizons API is online
- Check console for full error message
- Test URL manually in browser

**Planets in wrong positions**
- Verify system time/date is correct
- Check `current_day_of_year` calculation
- Enable debug logging to see fetched positions
- Compare with JPL Horizons web interface

**Positions not updating**
- Check `get_fraction_of_day_elapsed()` returns 0.0-1.0
- Verify interpolation is called each frame
- Check that midnight refresh is triggering
