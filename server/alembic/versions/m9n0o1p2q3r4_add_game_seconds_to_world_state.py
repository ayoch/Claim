"""add game_seconds to world_state

Revision ID: m9n0o1p2q3r4
Revises: l8m9n0o1p2q3
Create Date: 2026-03-07

game_seconds = elapsed game-seconds, incremented by TICK_INTERVAL per tick
regardless of speed multiplier. Unlike total_ticks (which = sum(speed*dt)),
game_seconds accurately tracks elapsed game time across speed changes and is
used by clients for orbital position calculations.

"""
from alembic import op
import sqlalchemy as sa

revision = 'm9n0o1p2q3r4'
down_revision = 'l8m9n0o1p2q3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('world_state',
        sa.Column('game_seconds', sa.Float(), nullable=False, server_default='0.0')
    )
    # Best-effort initialization: at 1x, total_ticks == game_seconds.
    # At other speeds this is approximate but will correct forward from here.
    op.execute("""
        UPDATE world_state
        SET game_seconds = CAST(total_ticks AS FLOAT) / NULLIF(speed_multiplier, 0)
    """)


def downgrade() -> None:
    op.drop_column('world_state', 'game_seconds')
