"""add_is_admin_to_player

Revision ID: 2a20b17739f3
Revises: 
Create Date: 2026-02-27 08:04:59.805835

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '2a20b17739f3'
down_revision: Union[str, None] = '6fc20976806c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # is_admin is included in the initial schema migration; nothing to do here
    pass


def downgrade() -> None:
    pass
