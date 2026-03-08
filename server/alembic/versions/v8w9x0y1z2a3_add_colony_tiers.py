"""Add tier and growth_points columns to colonies table.

Revision ID: v8w9x0y1z2a3
Revises: u7v8w9x0y1z2
Create Date: 2026-03-08
"""
from alembic import op
import sqlalchemy as sa

revision = 'v8w9x0y1z2a3'
down_revision = 'u7v8w9x0y1z2'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    cols = {c["name"] for c in sa.inspect(conn).get_columns("colonies")}

    if "tier" not in cols:
        op.add_column("colonies", sa.Column(
            "tier", sa.Integer(), nullable=False, server_default="3"
        ))

    if "growth_points" not in cols:
        op.add_column("colonies", sa.Column(
            "growth_points", sa.Float(), nullable=False, server_default="2500"
        ))


def downgrade() -> None:
    op.drop_column("colonies", "growth_points")
    op.drop_column("colonies", "tier")
