"""multi-world prep: world_name on world_state, world_id on players

Revision ID: o1p2q3r4s5t6
Revises: n0o1p2q3r4s5
Create Date: 2026-03-07

"""
from alembic import op
import sqlalchemy as sa

revision = 'o1p2q3r4s5t6'
down_revision = 'n0o1p2q3r4s5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add world_name to world_state
    op.add_column('world_state',
        sa.Column('world_name', sa.String(64), nullable=False, server_default='Euterpe')
    )

    # Add world_id to players (nullable — existing players assigned to world 1 below)
    op.add_column('players',
        sa.Column('world_id', sa.Integer(), sa.ForeignKey('world_state.world_id', ondelete='SET NULL'), nullable=True)
    )
    op.create_index('ix_players_world_id', 'players', ['world_id'])

    # Assign all existing players to world 1
    op.execute("UPDATE players SET world_id = 1 WHERE world_id IS NULL")


def downgrade() -> None:
    op.drop_index('ix_players_world_id', table_name='players')
    op.drop_column('players', 'world_id')
    op.drop_column('world_state', 'world_name')
