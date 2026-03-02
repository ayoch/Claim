#!/usr/bin/env python3
"""
Reset a user's password.
Usage: python reset_password.py <username> <new_password>
"""

import asyncio
import sys
from sqlalchemy import select
from server.database import AsyncSessionLocal, init_db
from server.models.player import Player
from server.auth import hash_password


async def reset_password(username: str, new_password: str) -> None:
    await init_db()

    async with AsyncSessionLocal() as db:
        # Find the player
        result = await db.execute(select(Player).where(Player.username == username))
        player = result.scalar_one_or_none()

        if not player:
            print(f"❌ User '{username}' not found")
            return

        # Update password
        player.password_hash = hash_password(new_password)
        db.add(player)
        await db.commit()

        print(f"✓ Password reset for user '{username}'")
        if player.is_admin:
            print(f"  (Admin account)")


async def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: python reset_password.py <username> <new_password>")
        print("\nExample:")
        print("  python reset_password.py Jon MyNewPassword123")
        sys.exit(1)

    username = sys.argv[1]
    new_password = sys.argv[2]

    # Validate password strength
    if len(new_password) < 12:
        print("❌ Password must be at least 12 characters long")
        sys.exit(1)
    if not any(c.isupper() for c in new_password):
        print("❌ Password must contain at least one uppercase letter")
        sys.exit(1)
    if not any(c.islower() for c in new_password):
        print("❌ Password must contain at least one lowercase letter")
        sys.exit(1)
    if not any(c.isdigit() for c in new_password):
        print("❌ Password must contain at least one number")
        sys.exit(1)

    await reset_password(username, new_password)


if __name__ == "__main__":
    asyncio.run(main())
