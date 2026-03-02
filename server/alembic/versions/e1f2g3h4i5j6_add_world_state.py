"""add world state table

Revision ID: e1f2g3h4i5j6
Revises: d4e5f6a7b8c9
Create Date: 2026-03-02

"""
from alembic import op
import sqlalchemy as sa
from datetime import datetime, timezone


# revision identifiers, used by Alembic.
revision = 'e1f2g3h4i5j6'
down_revision = 'd4e5f6a7b8c9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create world_state table
    op.create_table(
        'world_state',
        sa.Column('world_id', sa.Integer(), nullable=False),
        sa.Column('total_ticks', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('last_updated', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('world_id')
    )

    # Insert default world state (world_id=1, total_ticks=0)
    op.execute(
        "INSERT INTO world_state (world_id, total_ticks, last_updated) VALUES (1, 0, NOW())"
    )


def downgrade() -> None:
    op.drop_table('world_state')
