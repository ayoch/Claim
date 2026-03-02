"""make_email_required

Revision ID: d4e5f6a7b8c9
Revises: 36e43b614478
Create Date: 2026-03-02 15:30:00.000000

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'd4e5f6a7b8c9'
down_revision: Union[str, None] = '36e43b614478'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Delete any players with NULL email (these are old accounts that can't continue)
    # This is necessary because we can't convert NULL to a valid unique email
    op.execute("DELETE FROM players WHERE email IS NULL")

    # Make email column NOT NULL
    # SQLite doesn't support ALTER COLUMN, so we need to check the dialect
    with op.batch_alter_table('players') as batch_op:
        batch_op.alter_column('email',
                              existing_type=sa.String(255),
                              nullable=False,
                              existing_nullable=True)


def downgrade() -> None:
    # Revert email to nullable
    with op.batch_alter_table('players') as batch_op:
        batch_op.alter_column('email',
                              existing_type=sa.String(255),
                              nullable=True,
                              existing_nullable=False)
