"""Add player_notifications table

Revision ID: r4s5t6u7v8w9
Revises: q3r4s5t6u7v8
Create Date: 2026-03-07

"""
from alembic import op
import sqlalchemy as sa

revision = 'r4s5t6u7v8w9'
down_revision = 'q3r4s5t6u7v8'
branch_labels = None
depends_on = None

MAX_ROWS = 100  # Keep latest N notifications per player (enforced in app logic)


def upgrade() -> None:
    conn = op.get_bind()
    existing = sa.inspect(conn).get_table_names()
    if 'player_notifications' not in existing:
        op.create_table(
            'player_notifications',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('player_id', sa.Integer(), sa.ForeignKey('players.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('tick_number', sa.Float(), nullable=False),
            sa.Column('event_type', sa.String(64), nullable=False),
            sa.Column('message', sa.String(512), nullable=False),
            sa.Column('is_read', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_player_notifications_id', 'player_notifications', ['id'], unique=False)
        op.create_index('ix_player_notifications_player_unread', 'player_notifications', ['player_id', 'is_read'])


def downgrade() -> None:
    op.drop_index('ix_player_notifications_player_unread', table_name='player_notifications')
    op.drop_index('ix_player_notifications_id', table_name='player_notifications')
    op.drop_table('player_notifications')
