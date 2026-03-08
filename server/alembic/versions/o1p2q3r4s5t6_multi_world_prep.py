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

    # Add world_id to players (nullable, no FK constraint at migration time —
    # world_state may be empty when migrations run; FK is logical/ORM-level only)
    op.add_column('players',
        sa.Column('world_id', sa.Integer(), nullable=True)
    )
    op.create_index('ix_players_world_id', 'players', ['world_id'])

    # Assign existing players to world 1 only if that world row already exists
    op.execute("""
        UPDATE players SET world_id = 1
        WHERE world_id IS NULL
          AND EXISTS (SELECT 1 FROM world_state WHERE world_id = 1)
    """)


def downgrade() -> None:
    op.drop_index('ix_players_world_id', table_name='players')
    op.drop_column('players', 'world_id')
    op.drop_column('world_state', 'world_name')
