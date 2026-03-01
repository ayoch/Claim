"""initial schema

Revision ID: 6fc20976806c
Revises:
Create Date: 2026-02-27 09:46:04.354066

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '6fc20976806c'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'colonies',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('colony_name', sa.String(64), unique=True, nullable=False, index=True),
        sa.Column('planet_id', sa.String(32), nullable=False),
        sa.Column('has_rescue_ops', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('price_multipliers', sa.JSON(), server_default='{}', nullable=False),
    )

    op.create_table(
        'asteroids',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('asteroid_name', sa.String(64), unique=True, nullable=False, index=True),
        sa.Column('body_type', sa.String(32), nullable=False),
        sa.Column('semi_major_axis', sa.Float(), nullable=False),
        sa.Column('eccentricity', sa.Float(), nullable=False),
        sa.Column('inclination', sa.Float(), nullable=False),
        sa.Column('long_ascending_node', sa.Float(), nullable=False),
        sa.Column('arg_perihelion', sa.Float(), nullable=False),
        sa.Column('mean_anomaly_at_epoch', sa.Float(), nullable=False),
        sa.Column('epoch_jd', sa.Float(), nullable=False),
        sa.Column('ore_yields', sa.JSON(), server_default='{}', nullable=False),
        sa.Column('max_mining_slots', sa.Integer(), server_default='6', nullable=False),
    )

    op.create_table(
        'players',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('username', sa.String(64), unique=True, nullable=False, index=True),
        sa.Column('password_hash', sa.String(128), nullable=False),
        sa.Column('money', sa.Integer(), server_default='14000000', nullable=False),
        sa.Column('reputation', sa.Integer(), server_default='0', nullable=False),
        sa.Column('is_admin', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('hq_colony_id', sa.Integer(), sa.ForeignKey('colonies.id', ondelete='SET NULL'), nullable=True),
        sa.Column('thrust_policy', sa.Integer(), server_default='1', nullable=False),
        sa.Column('supply_policy', sa.Integer(), server_default='1', nullable=False),
        sa.Column('collection_policy', sa.Integer(), server_default='1', nullable=False),
        sa.Column('encounter_policy', sa.Integer(), server_default='1', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('last_seen', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        'ships',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('player_id', sa.Integer(), sa.ForeignKey('players.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('ship_name', sa.String(64), nullable=False),
        sa.Column('ship_class', sa.Integer(), nullable=False),
        sa.Column('max_thrust_g', sa.Float(), nullable=False),
        sa.Column('thrust_setting', sa.Float(), server_default='1.0', nullable=False),
        sa.Column('cargo_capacity', sa.Float(), nullable=False),
        sa.Column('cargo_volume', sa.Float(), nullable=False),
        sa.Column('fuel_capacity', sa.Float(), nullable=False),
        sa.Column('fuel', sa.Float(), nullable=False),
        sa.Column('base_mass', sa.Float(), nullable=False),
        sa.Column('min_crew', sa.Integer(), nullable=False),
        sa.Column('max_equipment_slots', sa.Integer(), nullable=False),
        sa.Column('engine_condition', sa.Float(), server_default='100.0', nullable=False),
        sa.Column('is_derelict', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('position_x', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('position_y', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('is_stationed', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('station_colony_id', sa.Integer(), sa.ForeignKey('colonies.id', ondelete='SET NULL'), nullable=True),
        sa.Column('current_cargo', sa.JSON(), server_default='{}', nullable=False),
        sa.Column('supplies', sa.JSON(), server_default='{}', nullable=False),
    )

    op.create_table(
        'missions',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('player_id', sa.Integer(), sa.ForeignKey('players.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('ship_id', sa.Integer(), sa.ForeignKey('ships.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('asteroid_id', sa.Integer(), sa.ForeignKey('asteroids.id', ondelete='SET NULL'), nullable=True),
        sa.Column('mission_type', sa.Integer(), nullable=False),
        sa.Column('status', sa.Integer(), server_default='0', nullable=False),
        sa.Column('transit_time', sa.Float(), nullable=False),
        sa.Column('elapsed_ticks', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('fuel_per_tick', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('origin_x', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('origin_y', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('origin_name', sa.String(64), server_default='', nullable=False),
        sa.Column('origin_is_earth', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('return_to_station', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('mining_duration', sa.Float(), server_default='86400.0', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        'workers',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('player_id', sa.Integer(), sa.ForeignKey('players.id', ondelete='CASCADE'), nullable=True, index=True),
        sa.Column('first_name', sa.String(32), nullable=False),
        sa.Column('last_name', sa.String(32), nullable=False),
        sa.Column('pilot_skill', sa.Float(), nullable=False),
        sa.Column('engineer_skill', sa.Float(), nullable=False),
        sa.Column('mining_skill', sa.Float(), nullable=False),
        sa.Column('pilot_xp', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('engineer_xp', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('mining_xp', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('wage', sa.Integer(), nullable=False),
        sa.Column('loyalty', sa.Float(), server_default='50.0', nullable=False),
        sa.Column('fatigue', sa.Float(), server_default='0.0', nullable=False),
        sa.Column('personality', sa.Integer(), server_default='2', nullable=False),
        sa.Column('assigned_ship_id', sa.Integer(), sa.ForeignKey('ships.id', ondelete='SET NULL'), nullable=True),
        sa.Column('assigned_mission_id', sa.Integer(), sa.ForeignKey('missions.id', ondelete='SET NULL'), nullable=True),
        sa.Column('is_available', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('leave_status', sa.Integer(), server_default='0', nullable=False),
    )


def downgrade() -> None:
    op.drop_table('workers')
    op.drop_table('missions')
    op.drop_table('ships')
    op.drop_table('players')
    op.drop_table('asteroids')
    op.drop_table('colonies')
