"""add performance indexes

Revision ID: perf_indexes_001
Revises: j6k7l8m9n0o1
Create Date: 2026-03-04

"""
from alembic import op

# revision identifiers, used by Alembic.
revision = 'perf_indexes_001'
down_revision = 'j6k7l8m9n0o1'
branch_labels = None
depends_on = None


def upgrade():
    # Mission query optimization (player_id + status)
    op.create_index('idx_mission_player_status', 'mission', ['player_id', 'status'])

    # Worker query optimization (player_id)
    op.create_index('idx_worker_player', 'worker', ['player_id'])

    # Stockpile query optimization (player_id + asteroid_id)
    op.create_index('idx_stockpile_player_asteroid', 'stockpile', ['player_id', 'asteroid_id'])

    # Ship query optimization (player_id)
    op.create_index('idx_ship_player', 'ship', ['player_id'])


def downgrade():
    op.drop_index('idx_ship_player', table_name='ship')
    op.drop_index('idx_stockpile_player_asteroid', table_name='stockpile')
    op.drop_index('idx_worker_player', table_name='worker')
    op.drop_index('idx_mission_player_status', table_name='mission')
