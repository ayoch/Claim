"""make worker player_id nullable for labor pool

Revision ID: f2g3h4i5j6k7
Revises: e1f2g3h4i5j6
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f2g3h4i5j6k7'
down_revision = 'e1f2g3h4i5j6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Make player_id nullable to support labor pool (workers with no assigned player)
    op.alter_column('workers', 'player_id',
                    existing_type=sa.Integer(),
                    nullable=True)


def downgrade() -> None:
    # Revert to non-nullable (note: this will fail if there are NULL values)
    op.alter_column('workers', 'player_id',
                    existing_type=sa.Integer(),
                    nullable=False)
