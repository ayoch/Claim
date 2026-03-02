#!/usr/bin/env python3
"""
Quick script to set a user as admin.
Usage: python set_admin.py <username>
"""

import asyncio
import sys
from sqlalchemy import select, update
from server.database import AsyncSessionLocal, init_db
from server.models.player import Player


async def set_admin(username: str) -> None:
    await init_db()

    async with AsyncSessionLocal() as db:
        # Find the player
        result = await db.execute(select(Player).where(Player.username == username))
        player = result.scalar_one_or_none()

        if not player:
            print(f"❌ User '{username}' not found")
            return

        if player.is_admin:
            print(f"✓ User '{username}' is already an admin")
            return

        # Set as admin
        player.is_admin = True
        db.add(player)
        await db.commit()

        print(f"✓ User '{username}' is now an admin")


async def list_users() -> None:
    await init_db()

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Player))
        players = result.scalars().all()

        if not players:
            print("No users found")
            return

        print("\nRegistered users:")
        for player in players:
            admin_badge = "👑 ADMIN" if player.is_admin else ""
            print(f"  - {player.username} (ID: {player.id}) {admin_badge}")


async def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python set_admin.py <username>")
        print("   or: python set_admin.py --list")
        sys.exit(1)

    if sys.argv[1] == "--list":
        await list_users()
    else:
        username = sys.argv[1]
        await set_admin(username)


if __name__ == "__main__":
    asyncio.run(main())
