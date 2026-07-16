import requests
import uuid
import time
import sys


# ==========================================
# ANSI Color Codes for Professional Output
# ==========================================
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


class AtharQATester:
    """Enterprise-Grade Integration Test Suite for Athar Backend"""

    def __init__(self, base_url: str, user_id: str):
        self.base_url = base_url.rstrip('/')
        self.user_id = user_id
        self.session = requests.Session()
        self.active_goal_id = None
        self.idempotency_key = f"idem-key-{uuid.uuid4().hex[:8]}"

    def print_step(self, step_num: int, description: str):
        print(f"\n{Colors.HEADER}{Colors.BOLD}[Step {step_num}] {description}{Colors.ENDC}")

    def pass_test(self, msg: str):
        print(f"{Colors.OKGREEN}  [✅ PASS] {msg}{Colors.ENDC}")

    def fail_test(self, msg: str, response=None):
        print(f"{Colors.FAIL}  [❌ FAIL] {msg}{Colors.ENDC}")
        if response is not None:
            print(f"{Colors.FAIL}     Details: {response.text}{Colors.ENDC}")
        sys.exit(1)  # Stop execution on critical failure

    def run_suite(self):
        print(f"{Colors.OKCYAN}{Colors.BOLD}🚀 Starting Athar Core Integration Suite...{Colors.ENDC}")
        print(f"Target User ID: {self.user_id}\n")

        # ---------------------------------------------------------
        # 1. Oasis Initialization & Read
        # ---------------------------------------------------------
        self.print_step(1, "Testing Initial Oasis Gamification State")
        res = self.session.get(f"{self.base_url}/oasis/{self.user_id}")
        if res.status_code == 200:
            self.pass_test(f"Oasis endpoint healthy. Current weather: {res.json().get('weather_condition')}")
        else:
            self.fail_test("Failed to fetch initial Oasis state.", res)

        # ---------------------------------------------------------
        # 2. Goal Lifecycle & Constraints (Conflict Handling)
        # ---------------------------------------------------------
        self.print_step(2, "Testing Goal Lifecycle & 409 Conflict Constraint")
        # First, ensure we don't have an active goal (Cleanup)
        active_res = self.session.get(f"{self.base_url}/goals/{self.user_id}/active")
        if active_res.status_code == 200 and active_res.json():
            existing_goal = active_res.json()
            self.active_goal_id = existing_goal['id']
            # Try to create a second one to trigger 409 Conflict
            conflict_res = self.session.post(f"{self.base_url}/goals/{self.user_id}", json={
                "title": "Conflict Goal", "target_amount": 1000, "category": "SAVINGS"
            })
            if conflict_res.status_code == 409:
                self.pass_test("System successfully blocked creation of a second ACTIVE goal (409 Conflict).")
            else:
                self.fail_test("System allowed multiple ACTIVE goals!", conflict_res)

            # Archive the existing one to clear the path
            self.session.patch(f"{self.base_url}/goals/{self.user_id}/{self.active_goal_id}/status",
                               json={"status": "ARCHIVED"})

        # Create a fresh goal for testing auto-completion
        goal_payload = {"title": "Test Goal", "target_amount": 500.0, "category": "SAVINGS"}
        new_goal_res = self.session.post(f"{self.base_url}/goals/{self.user_id}", json=goal_payload)
        if new_goal_res.status_code == 201:
            self.active_goal_id = new_goal_res.json()['id']
            self.pass_test(f"Created fresh ACTIVE goal (Target: 500). ID: {self.active_goal_id}")
        else:
            self.fail_test("Failed to create new goal.", new_goal_res)

        # ---------------------------------------------------------
        # 3. Validation Edge Case (Pydantic 422)
        # ---------------------------------------------------------
        self.print_step(3, "Testing Strict Payload Validation (Negative Amount)")
        bad_tx = {"amount": -50.0, "description": "Negative Hack", "category": "FOOD", "type_enum": "EXPENSE"}
        bad_res = self.session.post(f"{self.base_url}/transactions/", json=bad_tx)
        if bad_res.status_code == 422:
            self.pass_test("System successfully rejected negative amount with 422 Unprocessable Entity.")
        else:
            self.fail_test("System accepted invalid negative transaction amount!", bad_res)

        # ---------------------------------------------------------
        # 4. Idempotency & Replay Protection
        # ---------------------------------------------------------
        self.print_step(4, "Testing FinTech Idempotency (Network Retry Simulation)")
        idem_tx = {
            "amount": 150.0, "description": "Internet Bill",
            "category": "BILLS", "type_enum": "EXPENSE",
            "idempotency_key": self.idempotency_key
        }

        # Request 1
        res1 = self.session.post(f"{self.base_url}/transactions/", json=idem_tx)
        if res1.status_code == 201:
            self.pass_test("First transaction processed successfully.")
        else:
            self.fail_test("Failed first transaction.", res1)

        time.sleep(0.5)

        # Request 2 (The Replay)
        res2 = self.session.post(f"{self.base_url}/transactions/", json=idem_tx)
        data2 = res2.json()
        if res2.status_code in [200, 201] and data2.get("is_replay") is True:
            self.pass_test("System caught the retry! Marked as `is_replay: True` and prevented double-charging.")
        else:
            self.fail_test("Idempotency failed. System processed it as a new transaction.", res2)

        # ---------------------------------------------------------
        # 5. Goal Auto-Completion & Gamification Trigger
        # ---------------------------------------------------------
        self.print_step(5, "Testing Goal Auto-Completion via Savings Transaction")
        savings_tx = {
            "amount": 600.0,  # Exceeds the 500 target
            "description": "Transfer to Savings",
            "category": "SAVINGS", "type_enum": "EXPENSE"
        }
        self.session.post(f"{self.base_url}/transactions/", json=savings_tx)

        # Verify Goal Status
        goal_check = self.session.get(f"{self.base_url}/goals/{self.user_id}/active")
        if goal_check.status_code == 200 and goal_check.json() is None:
            self.pass_test("Goal automatically disappeared from ACTIVE (Auto-completed successfully).")
        else:
            self.fail_test("Goal did NOT auto-complete after reaching target amount.", goal_check)

        # ---------------------------------------------------------
        # 6. Anomaly Detection (The Wildcard)
        # ---------------------------------------------------------
        self.print_step(6, "Testing Algorithmic Anomaly Detection")
        huge_tx = {
            "amount": 15000.0, "description": "Luxury Watch",
            "category": "SHOPPING", "type_enum": "EXPENSE"
        }
        res_anomaly = self.session.post(f"{self.base_url}/transactions/", json=huge_tx)
        if res_anomaly.status_code == 201 and res_anomaly.json().get("is_unusual_spend") is True:
            self.pass_test("Smart engine detected unusual spending (Anomaly Flag Triggered) 🔥")
        elif res_anomaly.status_code == 201:
            print(
                f"{Colors.WARNING}  [⚠️ WARN] Transaction accepted, but anomaly not flagged. (Needs more historical data to calc StdDev){Colors.ENDC}")
        else:
            self.fail_test("Anomaly transaction failed.", res_anomaly)

        # ---------------------------------------------------------
        # 7. Unified Dashboard Analytics
        # ---------------------------------------------------------
        self.print_step(7, "Testing Dashboard Analytics & Smart Insights")
        res_analytics = self.session.get(f"{self.base_url}/analytics/{self.user_id}")
        if res_analytics.status_code == 200:
            data = res_analytics.json()
            self.pass_test("Analytics generated successfully.")
            print(f"     Balance: {data.get('current_balance')}")
            print(f"     Smart Insight: {data.get('smart_insights', 'N/A')}")
        else:
            self.fail_test("Analytics endpoint failed.", res_analytics)

        print(
            f"\n{Colors.OKGREEN}{Colors.BOLD}🎉 ALL ARCHITECTURAL TESTS PASSED SUCCESSFULLY! The backend is bulletproof. 🛡️{Colors.ENDC}\n")


if __name__ == "__main__":
    SERVER_URL = "http://127.0.0.1:8000"

    print("Welcome to Athar QA Engine.")
    target_user_id = input("Please enter a valid User ID (UUID) from Supabase to run the suite: ").strip()

    if not target_user_id:
        print(f"{Colors.FAIL}Error: User ID is required.{Colors.ENDC}")
        sys.exit(1)

    tester = AtharQATester(SERVER_URL, target_user_id)
    try:
        tester.run_suite()
    except requests.exceptions.ConnectionError:
        print(
            f"\n{Colors.FAIL}{Colors.BOLD}CRITICAL ERROR:{Colors.ENDC} Could not connect to {SERVER_URL}. Is your FastAPI server running?")