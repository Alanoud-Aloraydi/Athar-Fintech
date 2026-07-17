

"""
Gamification Engine.

Evaluates the behavioral impact of a single transaction and translates it
into an `OasisImpact` — the growth/health deltas that drive the 3D Spline
Oasis visualization. Also derives the `OasisEnvironment` — the dynamic,
"wow factor" environmental variables (weather, aura, streak multiplier)
the Spline scene renders — from a user's already-persisted cumulative
stats. This module lives in the Business layer and is only ever invoked
through a Facade; it must never be imported directly by the Presentation
layer.
"""

from functools import lru_cache

from app.business.gamification.models import OasisEnvironment, OasisImpact

# Tunable impact magnitudes. Centralized here so the "feel" of the Oasis
# (how strongly it reacts to good/bad habits) can be rebalanced in one
# place without touching the evaluation logic below.
_SAVINGS_GROWTH_DELTA = 1.0
_ENTERTAINMENT_HEALTH_DELTA = -0.5

_EXPENSE = "EXPENSE"
_SAVINGS = "SAVINGS"
_ENTERTAINMENT = "ENTERTAINMENT"
_ESSENTIAL_CATEGORIES = {"GROCERIES", "UTILITIES"}

# Weather thresholds, evaluated against `health_score` (0-100 scale).
_WEATHER_STORMY_MAX = 40.0
_WEATHER_CLOUDY_MAX = 70.0
_WEATHER_SUNNY_MAX = 95.0

# Aura thresholds, evaluated against `growth_level` (unbounded, one point
# per SAVINGS transaction in this MVP rule set).
_AURA_SPROUTING_MIN = 5.0
_AURA_FLOURISHING_MIN = 20.0
_AURA_LUMINOUS_MIN = 50.0

# Streak multiplier: +5% per consecutive day, capped at 2.5x so the effect
# stays meaningful (and finite) even for very long streaks.
_STREAK_MULTIPLIER_PER_DAY = 0.05
_STREAK_MULTIPLIER_CAP = 2.5

# --- Palm Oasis scene mapping -----------------------------------------
# The Spline scene ("Palm_01".."Palm_12") ships with every palm hidden
# except the first one or two. `palms_visible_for` is the single source
# of truth for turning the persisted `growth_level` stat into "how many
# of the 12 palms should be visible right now" — the Presentation layer
# (OasisStateDTO.visible_palm_count) and the simulation preview both
# call through this one function so the real scene and the "what if"
# preview never drift apart.
#
# One new palm unlocks every `_GROWTH_PER_PALM` points of growth_level,
# starting from a single seed palm at growth_level=0. This deliberately
# tracks the existing aura thresholds loosely (sprouting ~ 2nd palm,
# flourishing ~ 5th palm, luminous ~ 11th palm) without being coupled to
# them, so either scale can be rebalanced independently.
_TOTAL_PALMS = 12
_GROWTH_PER_PALM = 5.0


class GamificationEngine:
    """
    Stateless rules engine that converts a transaction's category, type,
    and amount into an `OasisImpact`, and a user's persisted cumulative
    Oasis stats into an `OasisEnvironment`.

    Stateless by design: every method here is a pure function of its
    arguments, with no reliance on instance state. This keeps the engine
    trivially thread-safe and simple to unit test.
    """

    def evaluate_habit_impact(
        self,
        transaction_category: str,
        transaction_type: str,
        transaction_amount: float,
    ) -> OasisImpact:
        """
        Evaluates how a single transaction should affect the Oasis.

        Behavioral rules (in priority order):
        1. **Savings** — any transaction categorized as `SAVINGS` nurtures
           the Oasis, regardless of whether it's logged as an `EXPENSE`
           (money leaving a spending account) or `INCOME` (money arriving
           in a savings vehicle) — both represent the same underlying
           habit: money being set aside.
        2. **Entertainment spend** — an `EXPENSE` categorized as
           `ENTERTAINMENT` strains the Oasis, discouraging reckless
           discretionary spending. Non-expense entertainment activity
           (e.g. a refund) has no effect.
        3. **Essential spend** — `GROCERIES` and `UTILITIES` are treated
           as neutral, necessary spending; they neither help nor harm
           the Oasis.
        4. **Everything else** (e.g. `UNCATEGORIZED`) — neutral, no
           measurable impact.

        Args:
            transaction_category: The transaction's `CategoryEnum` value,
                as a string (e.g. "SAVINGS", "ENTERTAINMENT").
            transaction_type: Either "EXPENSE" or "INCOME", describing the
                direction of money movement.
            transaction_amount: The transaction's monetary amount. Not yet
                used to scale impact magnitude in this MVP rule set —
                accepted now so magnitude-weighted scoring (e.g. a larger
                entertainment splurge causing proportionally more strain)
                can be introduced later without changing the method's
                public signature.

        Returns:
            An `OasisImpact` describing the resulting growth/health deltas
            and a human-readable reason.
        """
        category = transaction_category.strip().upper()
        txn_type = transaction_type.strip().upper()

        if category == _SAVINGS:
            return OasisImpact(
                growth_delta=_SAVINGS_GROWTH_DELTA,
                health_delta=0.0,
                trigger_reason="Setting money aside nurtures the Oasis — steady growth.",
            )

        if category == _ENTERTAINMENT and txn_type == _EXPENSE:
            return OasisImpact(
                growth_delta=0.0,
                health_delta=_ENTERTAINMENT_HEALTH_DELTA,
                trigger_reason="Discretionary entertainment spending strains the Oasis.",
            )

        if category in _ESSENTIAL_CATEGORIES:
            return OasisImpact(
                growth_delta=0.0,
                health_delta=0.0,
                trigger_reason="Essential spending keeps the Oasis stable — no impact.",
            )

        return OasisImpact(
            growth_delta=0.0,
            health_delta=0.0,
            trigger_reason="No measurable impact on the Oasis for this transaction.",
        )

    def derive_environment(
        self,
        growth_level: float,
        health_score: float,
        current_streak_days: int,
    ) -> OasisEnvironment:
        """
        Derives the Spline scene's dynamic environmental variables from a
        user's persisted, cumulative Oasis stats.

        Pure function, deliberately: it never reads the database and never
        replays transaction history — it only maps three already-fetched
        numbers to a small set of scene descriptors. This is what lets
        `weather_condition` / `visual_aura` thresholds be rebalanced freely
        without a migration or a backfill.

        Args:
            growth_level: The user's persisted cumulative Oasis growth stat.
            health_score: The user's persisted cumulative Oasis health stat
                (0-100 scale).
            current_streak_days: Consecutive days with at least one
                "positive action" (a SAVINGS transaction).

        Returns:
            An `OasisEnvironment` ready to hand straight to the Spline
            frontend.
        """
        weather_condition = self._weather_for(health_score)
        visual_aura = self._aura_for(growth_level)
        streak_multiplier = min(
            _STREAK_MULTIPLIER_CAP,
            1.0 + (current_streak_days * _STREAK_MULTIPLIER_PER_DAY),
        )
        mood_message = self._mood_message_for(
            weather_condition, visual_aura, current_streak_days
        )

        return OasisEnvironment(
            weather_condition=weather_condition,
            visual_aura=visual_aura,
            streak_multiplier=round(streak_multiplier, 2),
            mood_message=mood_message,
        )

    def palms_visible_for(self, growth_level: float) -> int:
        """
        Maps a (persisted or hypothetical) `growth_level` to how many of
        the Spline scene's 12 named palms ("Palm_01".."Palm_12") should
        be visible.

        Single source of truth for this mapping — used both by
        `OasisFacade.get_oasis_state` (the real, persisted count) and by
        `OasisFacade.simulate_transaction_impact` (the "what if" preview),
        so the live scene and the test/preview panel can never disagree
        about what a given growth_level looks like.

        Args:
            growth_level: Cumulative Oasis growth stat, persisted or
                hypothetical (e.g. current + a proposed transaction's
                growth_delta). Clamped to >= 0 defensively — growth_level
                is not expected to go negative in normal operation.

        Returns:
            An integer in [1, 12]. Every Oasis always shows at least one
            seed palm, even at growth_level=0.
        """
        safe_growth = max(0.0, growth_level)
        palm_count = 1 + int(safe_growth // _GROWTH_PER_PALM)
        return min(_TOTAL_PALMS, palm_count)

    @staticmethod
    def _weather_for(health_score: float) -> str:
        if health_score <= _WEATHER_STORMY_MAX:
            return "stormy"
        if health_score <= _WEATHER_CLOUDY_MAX:
            return "cloudy"
        if health_score <= _WEATHER_SUNNY_MAX:
            return "sunny"
        return "radiant"

    @staticmethod
    def _aura_for(growth_level: float) -> str:
        if growth_level >= _AURA_LUMINOUS_MIN:
            return "luminous"
        if growth_level >= _AURA_FLOURISHING_MIN:
            return "flourishing"
        if growth_level >= _AURA_SPROUTING_MIN:
            return "sprouting"
        return "dormant"

    @staticmethod
    def _mood_message_for(weather: str, aura: str, streak_days: int) -> str:
        if weather == "stormy":
            return "Your Oasis is weathering a storm — ease up on discretionary spending."
        if streak_days >= 7:
            return f"{streak_days}-day saving streak — your Oasis is thriving."
        if aura in ("flourishing", "luminous"):
            return "Your Oasis is flourishing from consistent saving habits."
        if weather == "radiant":
            return "Clear skies — your spending habits are in great shape."
        return "Your Oasis is steady. Keep building your saving habit for a bigger glow-up."


@lru_cache
def get_gamification_engine() -> GamificationEngine:
    """Returns a cached, singleton `GamificationEngine` instance (it's stateless, so one is enough)."""
    return GamificationEngine()
