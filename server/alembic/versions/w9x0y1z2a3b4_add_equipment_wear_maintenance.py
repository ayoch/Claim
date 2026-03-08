"""Add wear_per_tick to equipment; add maintenance_policy to players.

Revision ID: w9x0y1z2a3b4
Revises: v8w9x0y1z2a3
Create Date: 2026-03-08
"""
from alembic import op
import sqlalchemy as sa

revision = 'w9x0y1z2a3b4'
down_revision = 'v8w9x0y1z2a3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()

    # equipment.wear_per_tick — per-game-second degradation rate
    equip_cols = {c["name"] for c in sa.inspect(conn).get_columns("equipment")}
    if "wear_per_tick" not in equip_cols:
        op.add_column("equipment", sa.Column(
            "wear_per_tick", sa.Float(), nullable=False, server_default="0.0000193"
        ))

    # players.maintenance_policy — 0=PREVENTIVE 1=AS_NEEDED 2=RUN_TO_FAILURE 3=MANUAL
    player_cols = {c["name"] for c in sa.inspect(conn).get_columns("players")}
    if "maintenance_policy" not in player_cols:
        op.add_column("players", sa.Column(
            "maintenance_policy", sa.Integer(), nullable=False, server_default="1"
        ))


def downgrade() -> None:
    op.drop_column("equipment", "wear_per_tick")
    op.drop_column("players", "maintenance_policy")
