-- Performance indexes for common query patterns
-- Apply with: psql -U claim -d claim_dev -f migrations_001_performance_indexes.sql

-- Missions - frequently queried by player and status
CREATE INDEX IF NOT EXISTS ix_missions_player_status
    ON missions(player_id, status);

CREATE INDEX IF NOT EXISTS ix_missions_ship
    ON missions(ship_id);

-- Ships - queried by player, often filtered by stationed/derelict
CREATE INDEX IF NOT EXISTS ix_ships_player_stationed
    ON ships(player_id, is_stationed);

CREATE INDEX IF NOT EXISTS ix_ships_player_derelict
    ON ships(player_id, is_derelict);

-- Workers - queried by player and availability
CREATE INDEX IF NOT EXISTS ix_workers_player_available
    ON workers(player_id, is_available);

CREATE INDEX IF NOT EXISTS ix_workers_ship
    ON workers(assigned_ship_id);

-- Asteroids - spatial queries (if adding proximity search later)
CREATE INDEX IF NOT EXISTS ix_asteroids_position
    ON asteroids(semi_major_axis, eccentricity);

-- Add EXPLAIN ANALYZE examples
COMMENT ON INDEX ix_missions_player_status IS 'Optimizes: SELECT * FROM missions WHERE player_id = ? AND status IN (?)';
COMMENT ON INDEX ix_ships_player_stationed IS 'Optimizes: SELECT * FROM ships WHERE player_id = ? AND is_stationed = ?';
COMMENT ON INDEX ix_workers_player_available IS 'Optimizes: SELECT * FROM workers WHERE player_id = ? AND is_available = ?';
