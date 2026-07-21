#!/usr/bin/env python3
# =============================================================================
# Athar-Fintech — demo data seeder
#
# Creates (or refreshes) ONE ready-to-try demo account and plants a realistic
# ~30-day financial story for a young Saudi professional in Riyadh. The data
# is deliberately shaped to light up every backend algorithm so anyone opening
# the live app can see them working:
#
#   • Offline categorization ....... transactions span all 10 categories
#   • Two-ledger balances .......... salary + expenses drive current/savings
#   • Goal progress & trajectory ... an ACTIVE "Emergency Fund" ~88% funded,
#                                    slightly AHEAD of the linear pace
#   • Savings streak ............... 12 consecutive days of daily saving
#   • Z-Score anomaly detection .... one unusually large SHOPPING purchase
#                                    "today" flags against the user's own mean
#   • Family-transfer exclusion .... a large "تحويل عائلي" is NOT flagged
#   • Committed obligations (BNPL).. Tabby / Tamara installments tracked
#   • Oasis health & palms ......... high health (thriving) + a lush palm count
#
# Everything is keyed to the moment you run it (dates are relative to "now"),
# and the script is idempotent — re-running it wipes and re-plants the demo
# user's data, so the demo always looks the same on any day.
#
# Requirements (set as environment variables, or in backend/.env):
#   SUPABASE_URL           your project URL
#   SUPABASE_SERVICE_KEY   the service_role key (bypasses RLS for seeding)
# Optional overrides:
#   DEMO_EMAIL     (default: demo@athar-fintech.app)
#   DEMO_PASSWORD  (default: AtharDemo2026)
#
# Run from the repo root:
#   python scripts/seed_demo.py
# =============================================================================
from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta, timezone, date
from pathlib import Path

# Windows consoles default to a legacy codepage that can't print emoji/Arabic.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# --- Make the backend package importable so we reuse the REAL engines --------
_REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO_ROOT / "backend"))

try:
    from dotenv import load_dotenv  # python-dotenv (already a backend dep)
    load_dotenv(_REPO_ROOT / "backend" / ".env")
except Exception:  # dotenv is optional; env vars may be set directly
    pass

try:
    from supabase import create_client
except ImportError:
    sys.exit("supabase-py is not installed. Run: pip install -r backend/requirements.txt")

# The exact same classifier + gamification rules the running app uses, so the
# seeded categories and Oasis math match production behaviour precisely.
from app.business.categorization.engine import CategorizationEngine
from app.business.gamification.engine import GamificationEngine

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
DEMO_EMAIL = os.environ.get("DEMO_EMAIL", "demo@athar-fintech.app")
DEMO_PASSWORD = os.environ.get("DEMO_PASSWORD", "AtharDemo2026")
DEMO_FULL_NAME = "نورة (حساب تجريبي)"

# Active savings goal: target sits ABOVE the 15,000 SAR savings baseline so the
# oasis shows partial (not maxed-out) progress and a motivating ~88%.
GOAL_TITLE = "صندوق الطوارئ"
GOAL_TARGET = 22_000.0
GOAL_CATEGORY = "SAVINGS"
GOAL_CREATED_DAYS_AGO = 32
GOAL_DEADLINE_DAYS_AHEAD = 180

INCOME = "INCOME"
EXPENSE = "EXPENSE"

# -----------------------------------------------------------------------------
# The scenario. Each row is (days_ago, hour, description, amount, type).
# `category` is filled in later by the real CategorizationEngine — we don't
# hardcode it, so this doubles as a live demonstration of the classifier.
# -----------------------------------------------------------------------------
SCENARIO: list[tuple[int, int, str, float, str]] = [
    # ---- Income -------------------------------------------------------------
    (25, 9, "الدخل الشهري من جهة العمل", 16_000.0, INCOME),
    (12, 14, "دخل إضافي من مشروع حر", 1_800.0, INCOME),

    # ---- Housing (essential obligation) ------------------------------------
    (21, 10, "إيجار الشقة الشهري", 3_200.0, EXPENSE),

    # ---- Utilities / bills (essential obligations) -------------------------
    (24, 11, "فاتورة كهرباء SEC", 380.0, EXPENSE),
    (22, 12, "فاتورة موبايلي", 199.0, EXPENSE),
    (18, 13, "فاتورة انترنت STC", 300.0, EXPENSE),
    (15, 9, "فاتورة مياه", 90.0, EXPENSE),

    # ---- Groceries ----------------------------------------------------------
    (26, 18, "بندة سوبر ماركت", 340.0, EXPENSE),
    (19, 19, "التميمي ماركت", 420.0, EXPENSE),
    (9, 17, "كارفور هايبر ماركت", 510.0, EXPENSE),
    (4, 20, "بقالة الحي", 210.0, EXPENSE),

    # ---- Transport ----------------------------------------------------------
    (23, 8, "تعبئة بنزين", 160.0, EXPENSE),
    (7, 21, "رحلة كريم Careem", 40.0, EXPENSE),
    (2, 8, "تعبئة وقود", 150.0, EXPENSE),

    # ---- Food & dining ------------------------------------------------------
    (20, 13, "مطعم البيك", 55.0, EXPENSE),
    (16, 8, "ستاربكس Starbucks", 27.0, EXPENSE),
    (11, 20, "شاورما", 30.0, EXPENSE),
    (5, 7, "قهوة الصباح", 22.0, EXPENSE),
    (1, 16, "كافيه", 35.0, EXPENSE),

    # ---- Health -------------------------------------------------------------
    (13, 17, "صيدلية النهدي", 85.0, EXPENSE),

    # ---- Entertainment (gently lowers oasis health) ------------------------
    (24, 22, "اشتراك نتفليكس Netflix", 56.0, EXPENSE),
    (14, 21, "سينما VOX", 90.0, EXPENSE),
    (8, 23, "بلايستيشن ستور PlayStation", 120.0, EXPENSE),
    (6, 20, "اشتراك شاهد", 35.0, EXPENSE),

    # ---- Committed obligations / BNPL (Sharia-compliant installments) -------
    (17, 15, "Tabby installment - Jarir", 450.0, EXPENSE),
    (3, 15, "Tamara installment - IKEA", 380.0, EXPENSE),

    # ---- Family support (excluded from anomaly detection, a KSA norm) -------
    (10, 12, "تحويل عائلي - دعم الوالدة", 1_200.0, EXPENSE),

    # ---- Shopping: three normal purchases + ONE anomaly "today" ------------
    (27, 16, "Namshi order", 260.0, EXPENSE),
    (19, 14, "Amazon.sa purchase", 320.0, EXPENSE),
    (12, 18, "Zara Riyadh", 240.0, EXPENSE),
    (0, 13, "Amazon.sa - laptop", 1_300.0, EXPENSE),   # <-- Z-score spike

    # ---- Savings: two transfers + a 12-day daily-saving streak -------------
    (28, 10, "تحويل ادخار إلى الإنماء", 1_500.0, EXPENSE),
    (20, 10, "استثمار مرابحة الراجحي", 1_200.0, EXPENSE),
]
# Daily micro-savings for the last 12 consecutive days (builds the streak).
for _d in range(0, 12):
    SCENARIO.append((_d, 6, "تحويل ادخار يومي", 140.0, EXPENSE))


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
def _client():
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        sys.exit(
            "Missing SUPABASE_URL / SUPABASE_SERVICE_KEY.\n"
            "Set them as environment variables or in backend/.env, then re-run."
        )
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)


def _get_or_create_demo_user(sb) -> str:
    """Return the demo user's UUID, creating the auth user if needed."""
    # Try to create the user. If it already exists, fall back to signing in
    # (more reliable than admin.list_users, which errors on some projects).
    try:
        resp = sb.auth.admin.create_user(
            {
                "email": DEMO_EMAIL,
                "password": DEMO_PASSWORD,
                "email_confirm": True,
                "user_metadata": {"full_name": DEMO_FULL_NAME, "demo": True},
            }
        )
        user = getattr(resp, "user", None) or resp
        if getattr(user, "id", None):
            print(f"✅ Created demo user: {DEMO_EMAIL}")
            return user.id
    except Exception as exc:  # noqa: BLE001 — likely "already registered"
        print(f"  (create_user: {exc}; signing in to fetch the existing id)")

    # Fallback: sign in on a throwaway client so the main service client keeps
    # its service-role auth (needed to bypass RLS for the seed writes).
    tmp = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    auth = tmp.auth.sign_in_with_password(
        {"email": DEMO_EMAIL, "password": DEMO_PASSWORD}
    )
    print(f"↺ Reusing existing demo user: {DEMO_EMAIL}")
    return auth.user.id


def _wipe(sb, user_id: str) -> None:
    """Remove any prior demo data so a re-run is clean and deterministic."""
    for table in ("transactions", "goals", "oasis_states"):
        try:
            sb.table(table).delete().eq("user_id", user_id).execute()
        except Exception as exc:  # noqa: BLE001
            print(f"  (wipe {table}: {exc})")


def _compute_streak(savings_dates: set[date]) -> tuple[int, int, date | None]:
    """(current_streak, longest_streak, last_positive_date) from saving days."""
    if not savings_dates:
        return 0, 0, None
    ordered = sorted(savings_dates)
    longest = run = 1
    for prev, cur in zip(ordered, ordered[1:]):
        run = run + 1 if (cur - prev).days == 1 else 1
        longest = max(longest, run)
    # current streak = trailing consecutive run ending at the latest saving day
    last = ordered[-1]
    current = 0
    d = last
    s = set(ordered)
    while d in s:
        current += 1
        d -= timedelta(days=1)
    return current, max(longest, current), last


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main() -> None:
    sb = _client()
    engine = CategorizationEngine()
    gami = GamificationEngine()
    now = datetime.now(timezone.utc)

    print("\n🌴 Athar-Fintech — seeding demo data\n" + "=" * 44)
    user_id = _get_or_create_demo_user(sb)
    _wipe(sb, user_id)

    # Ensure the profile row exists (FK target for everything else).
    sb.table("profiles").upsert(
        {"id": user_id, "full_name": DEMO_FULL_NAME}, on_conflict="id"
    ).execute()

    # --- Build transaction rows, classifying each via the real engine --------
    rows: list[dict] = []
    balance = 0.0
    savings_dates: set[date] = set()
    growth_level = 0.0
    health = 100.0
    saved_amount = 0.0
    cat_counts: dict[str, int] = {}

    for days_ago, hour, desc, amount, ttype in SCENARIO:
        category = engine.classify(desc).value
        cat_counts[category] = cat_counts.get(category, 0) + 1
        created = (now - timedelta(days=days_ago)).replace(
            hour=hour % 24, minute=int(amount) % 60, second=0, microsecond=0
        )
        rows.append(
            {
                "user_id": user_id,
                "amount": amount,
                "description": desc,
                "category": category,
                "type": ttype,
                "created_at": created.isoformat(),
            }
        )

        # Mirror the ledger + gamification effects the app applies on ingestion.
        balance += amount if ttype == INCOME else -amount
        impact = gami.evaluate_habit_impact(category, ttype, amount)
        growth_level = max(0.0, growth_level + impact.growth_delta)
        health = max(0.0, min(100.0, health + impact.health_delta))
        if category == "SAVINGS":
            saved_amount += amount
            savings_dates.add(created.date())

    # Insert transactions (service key bypasses RLS).
    sb.table("transactions").insert(rows).execute()
    print(f"✅ Inserted {len(rows)} transactions")

    # --- Active goal via the real RPC, then backdate + fund it ---------------
    deadline = (now + timedelta(days=GOAL_DEADLINE_DAYS_AHEAD)).date().isoformat()
    goal = sb.rpc(
        "create_goal_atomic",
        {
            "p_user_id": user_id,
            "p_title": GOAL_TITLE,
            "p_target_amount": GOAL_TARGET,
            "p_category": GOAL_CATEGORY,
            "p_deadline": deadline,
        },
    ).execute()
    goal_row = goal.data[0] if isinstance(goal.data, list) else goal.data
    goal_created = (now - timedelta(days=GOAL_CREATED_DAYS_AGO)).isoformat()
    sb.table("goals").update(
        {"saved_amount": round(saved_amount, 2), "created_at": goal_created}
    ).eq("id", goal_row["id"]).execute()
    print(f"✅ Goal '{GOAL_TITLE}': {saved_amount:,.0f} / {GOAL_TARGET:,.0f} SAR")

    # --- Persisted Oasis state (health/streak/growth) ------------------------
    cur_streak, long_streak, last_pos = _compute_streak(savings_dates)
    sb.table("oasis_states").upsert(
        {
            "user_id": user_id,
            "growth_level": round(growth_level, 2),
            "health_score": round(health, 2),
            "current_streak_days": cur_streak,
            "longest_streak_days": long_streak,
            "last_positive_action_date": last_pos.isoformat() if last_pos else None,
            "updated_at": now.isoformat(),
        },
        on_conflict="user_id",
    ).execute()

    # --- Current-account balance (baseline is added by the analytics layer) --
    sb.table("profiles").update({"current_balance": round(balance, 2)}).eq(
        "id", user_id
    ).execute()

    # --- Summary -------------------------------------------------------------
    wallet = 15_000.0 + saved_amount
    progress = min(1.0, wallet / GOAL_TARGET)
    print("\n" + "=" * 44)
    print("Categorization coverage:")
    for cat, n in sorted(cat_counts.items(), key=lambda kv: -kv[1]):
        print(f"   {cat:<14} {n}")
    print("-" * 44)
    print(f"Oasis health ........ {health:.0f}%  ({'thriving' if health >= 80 else 'strained'})")
    print(f"Saving streak ....... {cur_streak} days")
    print(f"Goal progress ....... {progress * 100:.0f}%  (palms scale to this)")
    print(f"Current balance ..... {8_500.0 + balance:,.0f} SAR (incl. baseline)")
    print(f"Savings wallet ...... {wallet:,.0f} SAR")
    print("=" * 44)
    print("\n🎉 Done. Log in to the live app with:")
    print(f"     Email:    {DEMO_EMAIL}")
    print(f"     Password: {DEMO_PASSWORD}\n")


if __name__ == "__main__":
    main()
