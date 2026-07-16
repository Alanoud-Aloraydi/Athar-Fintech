
"""
Transaction Facade.

`TransactionFacade` is the *only* Business-layer class the Presentation
layer is permitted to call for transaction ingestion. It orchestrates
categorization, gamification evaluation, persistence (including the
persisted Oasis running totals and idempotent replay handling), and
(when applicable) active-goal progress updates and spend-anomaly
detection as a single logical operation, so the router never has to know
about — or call — any of these collaborators directly.
"""

from __future__ import annotations

import logging

from app.business.categorization.engine import CategorizationEngine
from app.business.categorization.models import CategoryEnum
from app.business.gamification.engine import GamificationEngine
from app.core.exceptions import PersistenceError
from app.persistence.models import TransactionWriteResult
from app.persistence.repositories.goal_repo import GoalRepository
from app.persistence.repositories.transaction_repo import TransactionRepository
from app.presentation.schemas.transactions import TransactionCreateDTO, TransactionResponseDTO

logger = logging.getLogger(__name__)

# Anomaly detection (the "Hackathon Edge" wildcard): flag an EXPENSE as
# unusual if it's more than this many standard deviations above the user's
# own historical average for that category. Requires a minimum sample size
# so a brand-new category isn't flagged off a single data point.
_ANOMALY_STDDEV_THRESHOLD = 2.0
_ANOMALY_MIN_SAMPLE_SIZE = 3


class TransactionFacade:
    """
    <<Facade>> — orchestrates the full transaction-ingestion flow across
    the Categorization Engine, Gamification Engine, and both repositories.
    """

    def __init__(
        self,
        categorization_engine: CategorizationEngine,
        gamification_engine: GamificationEngine,
        transaction_repository: TransactionRepository,
        goal_repository: GoalRepository,
    ) -> None:
        """
        Args:
            categorization_engine: Classifies transaction descriptions.
            gamification_engine: Evaluates a transaction's Oasis impact and
                derives its Oasis environment.
            transaction_repository: Persists/reads transactions and the
                persisted Oasis running totals.
            goal_repository: Reads/updates the user's active Financial Goal.
        """
        self._categorization_engine = categorization_engine
        self._gamification_engine = gamification_engine
        self._transaction_repository = transaction_repository
        self._goal_repository = goal_repository

    def process_and_store(self, payload: TransactionCreateDTO) -> TransactionResponseDTO:
        """
        Executes the end-to-end transaction-ingestion flow:

        1. Classify the description into a `CategoryEnum`.
        2. Evaluate the resulting `OasisImpact` via the Gamification Engine.
        3. Persist the transaction — atomically, in the same database
           operation, this also updates the user's
           `profiles.current_balance` and their persisted Oasis running
           totals (see `create_transaction_atomic`). If `payload.idempotency_key`
           matches a prior request, this step returns the existing
           transaction instead (`is_replay=True`) without mutating anything
           a second time.
        4. If this was a genuine write (not a replay) AND the transaction
           was categorized as SAVINGS, roll the amount into the user's
           active goal's `saved_amount`.
        5. If this was a genuine write of an EXPENSE, check whether the
           amount is unusually large for the user's own history in that
           category (the spend-anomaly wildcard).
        6. Return a `TransactionResponseDTO` combining the persisted
           transaction with its `OasisImpact` and anomaly flag.

        Args:
            payload: The validated `TransactionCreateDTO` from the request.

        Returns:
            A `TransactionResponseDTO` for the newly created (or replayed)
            transaction.

        Raises:
            ProfileNotFoundError: If the user has no `profiles` row (see
                `TransactionRepository.create_transaction`) — a
                data-integrity anomaly, not a routine rejection.
            PersistenceError: If classifying and evaluating succeed but
                persisting the transaction itself fails. Both of these
                are allowed to propagate to the Presentation layer,
                which is responsible for translating them into an HTTP
                response — the Facade does not know about HTTP.
        """
        user_id_str = str(payload.user_id)

        category = self._categorization_engine.classify(payload.description)

        oasis_impact = self._gamification_engine.evaluate_habit_impact(
            transaction_category=category.value,
            transaction_type=payload.type_enum,
            transaction_amount=payload.amount,
        )

        # The transaction itself is the critical write for this request —
        # if this fails, we let PersistenceError propagate so the caller
        # gets an accurate failure response.
        write_result = self._transaction_repository.create_transaction(
            user_id=user_id_str,
            amount=payload.amount,
            description=payload.description,
            category=category.value,
            type_enum=payload.type_enum,
            idempotency_key=payload.idempotency_key,
            growth_delta=oasis_impact.growth_delta,
            health_delta=oasis_impact.health_delta,
        )

        is_anomaly = False
        if not write_result.is_replay:
            if category == CategoryEnum.SAVINGS:
                self._roll_into_active_goal(user_id=user_id_str, amount=payload.amount)

            if payload.type_enum == "EXPENSE":
                is_anomaly = self._check_spend_anomaly(
                    user_id=user_id_str,
                    category=category.value,
                    amount=payload.amount,
                )

        return self._to_response_dto(write_result, oasis_impact, is_anomaly)

    def _roll_into_active_goal(self, user_id: str, amount: float) -> None:
        """
        Best-effort update of the user's active goal's `saved_amount`.

        This is deliberately a *secondary* effect of the request: the
        transaction has already been safely persisted by the time this
        runs, so a failure here (no active goal, or a transient
        Persistence error on the update) is logged and swallowed rather
        than failing the whole request. The transaction record itself
        remains the source of truth and the goal update can be
        reconciled/retried out-of-band if needed.

        The increment itself is delegated to
        `GoalRepository.increment_saved_amount`, which performs a single
        atomic `saved_amount = saved_amount + amount` statement in the
        database (and auto-completes the goal if the total reaches its
        target) — this method does not read the current `saved_amount`
        and compute a new total itself, which would reintroduce a
        lost-update race under concurrent transactions for the same goal.
        """
        try:
            active_goal = self._goal_repository.get_active_goal(user_id)
            if active_goal is None:
                return

            self._goal_repository.increment_saved_amount(
                goal_id=str(active_goal.id),
                amount=amount,
            )
        except PersistenceError:
            logger.exception(
                "Failed to roll a SAVINGS transaction into the active goal for "
                "user_id=%s; the transaction was persisted successfully and "
                "this goal update can be retried.",
                user_id,
            )

    def _check_spend_anomaly(self, user_id: str, category: str, amount: float) -> bool:
        """
        Best-effort check for whether `amount` is an unusually large spend
        for the user's own history in `category` — the "Hackathon Edge"
        wildcard. Compares against the user's mean + N standard deviations
        for that category (computed server-side, see
        `TransactionRepository.get_category_spending_stats`), entirely
        from the user's own past transactions — no external data, no
        third-party model, consistent with the offline-first/privacy
        posture of the rest of this backend.

        Deliberately non-critical: a failure here is logged and swallowed
        rather than failing the request, since it's a nice-to-have signal
        rather than a core part of the ingestion flow.
        """
        try:
            avg_amount, stddev_amount, sample_size = (
                self._transaction_repository.get_category_spending_stats(
                    user_id=user_id, category=category
                )
            )
        except PersistenceError:
            logger.exception(
                "Failed to fetch category spending stats for user_id=%s, "
                "category=%s; skipping anomaly check for this transaction.",
                user_id,
                category,
            )
            return False

        if sample_size < _ANOMALY_MIN_SAMPLE_SIZE or stddev_amount <= 0:
            return False

        threshold = avg_amount + (_ANOMALY_STDDEV_THRESHOLD * stddev_amount)
        return amount > threshold

    @staticmethod
    def _to_response_dto(
        write_result: TransactionWriteResult,
        oasis_impact,
        is_anomaly: bool,
    ) -> TransactionResponseDTO:
        return TransactionResponseDTO(
            id=write_result.id,
            user_id=write_result.user_id,
            description=write_result.description,
            amount=write_result.amount,
            category=CategoryEnum(write_result.category),
            type_enum=write_result.type,  # type: ignore[arg-type]
            created_at=write_result.created_at,
            oasis_impact=oasis_impact,
            is_replay=write_result.is_replay,
            is_unusual_spend=is_anomaly,
        )
