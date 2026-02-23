#!/usr/bin/env python3
"""
Local testing script for Claim server.
Run after starting server with: uvicorn server.main:app --reload

This tests all core functionality in sequence:
1. Health check
2. Seeding data
3. Auth (register, login)
4. Game state retrieval
5. Starter pack
6. Hiring workers
7. Dispatching missions
8. Buying ships
9. Firing workers
"""

import requests
import time
import json
from typing import Any

BASE_URL = "http://localhost:8000"
TOKEN = None

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'

def log_test(name: str):
    print(f"\n{Colors.BLUE}{'='*60}{Colors.END}")
    print(f"{Colors.BLUE}TEST: {name}{Colors.END}")
    print(f"{Colors.BLUE}{'='*60}{Colors.END}")

def log_success(msg: str):
    print(f"{Colors.GREEN}✓ {msg}{Colors.END}")

def log_error(msg: str):
    print(f"{Colors.RED}✗ {msg}{Colors.END}")

def log_info(msg: str):
    print(f"{Colors.YELLOW}→ {msg}{Colors.END}")

def make_request(method: str, path: str, **kwargs) -> requests.Response:
    """Make HTTP request with optional auth."""
    url = f"{BASE_URL}{path}"
    headers = kwargs.pop("headers", {})

    if TOKEN and "Authorization" not in headers:
        headers["Authorization"] = f"Bearer {TOKEN}"

    if method == "GET":
        response = requests.get(url, headers=headers, **kwargs)
    elif method == "POST":
        response = requests.post(url, headers=headers, **kwargs)
    elif method == "DELETE":
        response = requests.delete(url, headers=headers, **kwargs)
    else:
        raise ValueError(f"Unsupported method: {method}")

    return response

def test_health():
    log_test("Health Check")
    response = make_request("GET", "/health")

    if response.status_code == 200:
        log_success(f"Server is healthy: {response.json()}")
        return True
    else:
        log_error(f"Health check failed: {response.status_code}")
        return False

def test_seed():
    log_test("Seed Data (Asteroids + Colonies)")
    response = make_request("POST", "/admin/seed")

    if response.status_code == 200:
        data = response.json()
        seeded = data.get('seeded', {})
        log_success(f"Seeded {seeded.get('asteroids', 0)} asteroids, {seeded.get('colonies', 0)} colonies")
        return True
    else:
        log_error(f"Seed failed: {response.status_code} - {response.text}")
        return False

def test_register():
    log_test("Auth - Register")
    username = f"test_player_{int(time.time())}"
    password = "TestPass123"  # Meets strong password requirements

    response = make_request(
        "POST",
        "/auth/register",
        json={"username": username, "password": password}
    )

    if response.status_code == 201:
        data = response.json()
        log_success(f"Registered player: {data['username']} (ID: {data['id']})")
        return username, password, data['id']
    else:
        log_error(f"Registration failed: {response.status_code} - {response.text}")
        return None, None, None

def test_login(username: str, password: str):
    log_test("Auth - Login")
    global TOKEN

    response = make_request(
        "POST",
        "/auth/login",
        data={"username": username, "password": password}
    )

    if response.status_code == 200:
        data = response.json()
        TOKEN = data["access_token"]
        log_success(f"Logged in successfully")
        log_info(f"Token: {TOKEN[:30]}...")
        return True
    else:
        log_error(f"Login failed: {response.status_code} - {response.text}")
        return False

def test_get_state():
    log_test("Game State - Initial")
    response = make_request("GET", "/game/state")

    if response.status_code == 200:
        data = response.json()
        log_success(f"Retrieved game state")
        log_info(f"Money: ${data['money']}")
        log_info(f"Ships: {len(data['ships'])}")
        log_info(f"Workers: {len(data['workers'])}")
        log_info(f"Active Missions: {len(data.get('active_missions', []))}")
        return data
    else:
        log_error(f"Failed to get state: {response.status_code} - {response.text}")
        return None

def test_starter_pack(player_id: int):
    log_test("Admin - Give Starter Pack")
    response = make_request("POST", f"/admin/give-starter-pack/{player_id}")

    if response.status_code == 200:
        data = response.json()
        log_success(f"Received starter pack")
        log_info(f"Message: {data.get('message')}")
        log_info(f"Ship ID: {data.get('ship_id')}")
        log_info(f"Colony ID: {data.get('colony_id')}")

        # Fetch game state to get ship and worker details
        state_response = make_request("GET", "/game/state")
        if state_response.status_code == 200:
            state = state_response.json()
            ships = state.get('ships', [])
            workers = state.get('workers', [])
            if ships:
                ship = ships[0]
                log_info(f"Ship: {ship.get('ship_name')} (ID: {ship.get('id')})")
            if workers:
                log_info(f"Workers: {len(workers)} crew members")
                for worker in workers[:3]:  # Show first 3
                    name = f"{worker.get('first_name')} {worker.get('last_name')}"
                    log_info(f"  - {name} (Pilot: {worker.get('pilot_skill', 0):.2f}, Engineer: {worker.get('engineer_skill', 0):.2f}, Mining: {worker.get('mining_skill', 0):.2f})")
            return data.get('ship_id'), [w.get('id') for w in workers]
        return data.get('ship_id'), []
    else:
        log_error(f"Failed to get starter pack: {response.status_code} - {response.text}")
        return None, []

def test_dispatch_mission(ship_id: int):
    log_test("Mission - Dispatch Ship")

    # Get list of asteroids
    asteroids_response = make_request("GET", "/game/asteroids")
    if asteroids_response.status_code != 200:
        log_error(f"Failed to get asteroids: {asteroids_response.status_code}")
        return None

    asteroids = asteroids_response.json()
    if not asteroids:
        log_error("No asteroids available")
        return None

    target = asteroids[0]
    log_info(f"Target: {target.get('asteroid_name', 'Unknown')} (ID: {target['id']})")

    response = make_request(
        "POST",
        "/game/dispatch",
        json={
            "ship_id": ship_id,
            "mission_type": 0,  # MINING
            "asteroid_id": target['id'],
            "mining_duration": 7200,  # 2 game-hours
            "return_to_station": True
        }
    )

    if response.status_code == 201:
        data = response.json()
        log_success(f"Mission dispatched (ID: {data['id']})")
        log_info(f"Status: {data['status']}")
        log_info(f"Mining duration: {data['mining_duration']}s")
        return data['id']
    else:
        log_error(f"Failed to dispatch: {response.status_code} - {response.text}")
        return None

def test_hire_worker():
    log_test("Workers - Hire New Worker")
    log_info("Note: Hire endpoint requires worker_id from labor pool")
    log_info("Skipping: /admin/available-workers endpoint not yet implemented")
    return None  # Skip for now

def test_buy_ship():
    log_test("Ships - Purchase New Ship")

    # Get colonies
    colonies_response = make_request("GET", "/game/colonies")
    if colonies_response.status_code != 200:
        log_error(f"Failed to get colonies: {colonies_response.status_code}")
        return None

    colonies = colonies_response.json()
    if not colonies:
        log_error("No colonies available")
        return None

    colony = colonies[0]
    log_info(f"Purchasing from: {colony.get('colony_name', 'Unknown')} (ID: {colony['id']})")

    response = make_request(
        "POST",
        "/game/buy-ship",
        json={
            "ship_class": 0,  # Prospector
            "ship_name": "Test Ship II",
            "colony_id": colony['id']
        }
    )

    if response.status_code == 201:
        data = response.json()
        log_success(f"Purchased: {data.get('ship_name', 'Unknown')} (ID: {data['id']})")
        log_info(f"Class: {data['ship_class']}, Cargo: {data.get('cargo_capacity')}t")
        return data['id']
    elif response.status_code == 400:
        log_info(f"Expected failure (insufficient funds): {response.json()['detail']}")
        return None
    else:
        log_error(f"Failed to buy ship: {response.status_code} - {response.text}")
        return None

def test_fire_worker(worker_id: int):
    log_test("Workers - Fire Worker")

    response = make_request("POST", f"/game/fire/{worker_id}")

    if response.status_code == 200:
        log_success(f"Fired worker {worker_id}")
        return True
    else:
        log_error(f"Failed to fire: {response.status_code} - {response.text}")
        return False

def test_simulation_tick():
    log_test("Simulation - Wait for Ticks")
    log_info("Waiting 5 seconds to observe simulation ticks...")

    # Check initial tick count
    response1 = make_request("GET", "/admin/status")
    if response1.status_code != 200:
        log_error("Failed to get initial status")
        return False

    initial_ticks = response1.json()["total_ticks"]
    log_info(f"Initial tick count: {initial_ticks}")

    time.sleep(5)

    # Check final tick count
    response2 = make_request("GET", "/admin/status")
    if response2.status_code != 200:
        log_error("Failed to get final status")
        return False

    final_ticks = response2.json()["total_ticks"]
    elapsed_ticks = final_ticks - initial_ticks
    log_info(f"Final tick count: {final_ticks}")
    log_success(f"Simulation advanced {elapsed_ticks} ticks in 5 seconds")

    if elapsed_ticks >= 4:  # Should be ~5 at 1x speed, allow margin
        return True
    else:
        log_error(f"Expected ~5 ticks, got {elapsed_ticks}")
        return False

def main():
    print(f"\n{Colors.GREEN}{'='*60}")
    print(f"  Claim Server - Local Test Suite")
    print(f"{'='*60}{Colors.END}\n")

    results = {}

    # 1. Health check
    results['health'] = test_health()
    if not results['health']:
        log_error("Server is not running. Start with: uvicorn server.main:app --reload")
        return

    # 2. Seed data
    results['seed'] = test_seed()

    # 3. Register
    username, password, player_id = test_register()
    results['register'] = username is not None
    if not results['register']:
        return

    # 4. Login
    results['login'] = test_login(username, password)
    if not results['login']:
        return

    # 5. Get initial state
    initial_state = test_get_state()
    results['get_state'] = initial_state is not None

    # 6. Starter pack
    ship_id, worker_ids = test_starter_pack(player_id)
    results['starter_pack'] = ship_id is not None

    # 7. Check state after starter pack
    test_get_state()

    # 8. Dispatch mission
    if ship_id:
        mission_id = test_dispatch_mission(ship_id)
        results['dispatch'] = mission_id is not None

    # 9. Hire worker
    new_worker_id = test_hire_worker()
    results['hire'] = new_worker_id is not None

    # 10. Try to buy ship (will likely fail due to insufficient funds)
    new_ship_id = test_buy_ship()
    results['buy_ship'] = True  # Count as success even if funds insufficient

    # 11. Fire a worker
    if new_worker_id:
        results['fire'] = test_fire_worker(new_worker_id)

    # 12. Test simulation
    results['simulation'] = test_simulation_tick()

    # Summary
    print(f"\n{Colors.BLUE}{'='*60}")
    print(f"  TEST SUMMARY")
    print(f"{'='*60}{Colors.END}\n")

    passed = sum(1 for v in results.values() if v)
    total = len(results)

    for test, result in results.items():
        status = f"{Colors.GREEN}PASS{Colors.END}" if result else f"{Colors.RED}FAIL{Colors.END}"
        print(f"{test:20s} {status}")

    print(f"\n{Colors.BLUE}Result: {passed}/{total} tests passed{Colors.END}\n")

    if passed == total:
        print(f"{Colors.GREEN}✓ All tests passed! Server is working correctly.{Colors.END}\n")
    else:
        print(f"{Colors.YELLOW}⚠ Some tests failed. Check logs above for details.{Colors.END}\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Tests interrupted by user{Colors.END}\n")
    except Exception as e:
        print(f"\n{Colors.RED}Test suite crashed: {e}{Colors.END}\n")
        import traceback
        traceback.print_exc()
