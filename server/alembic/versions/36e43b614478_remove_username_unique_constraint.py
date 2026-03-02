"""remove_username_unique_constraint

Revision ID: 36e43b614478
Revises: c1d2e3f4a5b6
Create Date: 2026-03-02 13:37:12.084685

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '36e43b614478'
down_revision: Union[str, None] = 'c1d2e3f4a5b6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Drop unique constraint on username column
    # The constraint is actually named 'ix_players_username' (created as a unique index)
    op.drop_index('ix_players_username', 'players')
    # Recreate as non-unique index for performance
    op.create_index('ix_players_username', 'players', ['username'], unique=False)


def downgrade() -> None:
    # Re-add unique constraint on username column
    op.drop_index('ix_players_username', 'players')
    op.create_index('ix_players_username', 'players', ['username'], unique=True)
