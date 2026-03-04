"""add asteroid reserves

Revision ID: add_asteroid_reserves
Revises: add_is_admin
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'add_asteroid_reserves'
down_revision = 'add_is_admin'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add reserve depletion columns to asteroids table
    op.add_column('asteroids', sa.Column('estimated_mass_kg', sa.Float(), nullable=False, server_default='0.0'))
    op.add_column('asteroids', sa.Column('composition', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'))
    op.add_column('asteroids', sa.Column('reserves', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'))
    op.add_column('asteroids', sa.Column('original_reserves', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'))


def downgrade() -> None:
    # Remove reserve depletion columns
    op.drop_column('asteroids', 'original_reserves')
    op.drop_column('asteroids', 'reserves')
    op.drop_column('asteroids', 'composition')
    op.drop_column('asteroids', 'estimated_mass_kg')
