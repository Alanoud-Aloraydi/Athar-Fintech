
"""
Goal Facade.

`GoalFacade` is the *only* Business-layer class the Presentation layer is
permitted to call for goal management. It wraps `GoalRepository` and maps
persistence records to Presentation-facing DTOs, so the router never
touches `GoalRecord` or the repository directly.
"""

from __future__ import annotations

from app.business.categorization.models import CategoryEnum
from app.persistence.models import GoalRecord
from app.persistence.repositories.goal_repo import GoalRepository
from app.presentation.schemas.goals import GoalCreateDTO, GoalResponseDTO


class GoalFacade:
    """<<Facade>> â€” orchestrates Financial Goal creation and retrieval."""

    def __init__(self, goal_repository: GoalRepository) -> None:
        """
        Args:
            goal_repository: Repository providing read/write access to
                the `goals` table.
        """
        self._goal_repository = goal_repository

    def create_goal(self, user_id: str, payload: GoalCreateDTO) -> GoalResponseDTO:
        """
        Creates a new Financial Goal for the user.

        Every new goal is created with `status='ACTIVE'` â€” goal
        lifecycle transitions (e.g. completing or archiving a goal) are
        handled by a future dedicated flow, not by this method.

        Args:
            user_id: UUID (as string) of the owning user.
            payload: The validated `GoalCreateDTO` from the request.

        Returns:
            The newly created goal as a `GoalResponseDTO`.

        Raises:
            PersistenceError: If the insert fails. Allowed to propagate
                to the Presentation layer, which maps it to an HTTP
                response â€” the Facade does not know about HTTP.
        """
        goal_record = self._goal_repository.create_goal(
            user_id=user_id,
            title=payload.title,
            target_amount=payload.target_amount,
            category=payload.category.value,
            deadline=payload.deadline,
        )
        return self._to_response_dto(goal_record)

    def get_active_goal(self, user_id: str) -> GoalResponseDTO | None:
        """
        Fetches the user's currently active Financial Goal, if any.

        Args:
            user_id: UUID (as string) of the owning user.

        Returns:
            The active goal as a `GoalResponseDTO`, or `None` if the
            user has no active goal.

        Raises:
            PersistenceError: If the query fails.
        """
        goal_record = self._goal_repository.get_active_goal(user_id)
        if goal_record is None:
            return None

        return self._to_response_dto(goal_record)

    def transition_status(self, user_id: str, goal_id: str, new_status: str) -> GoalResponseDTO:
        """
        Transitions a goal from `ACTIVE` to `COMPLETED` or `ARCHIVED`.

        This is the *only* sanctioned way to end a goal's ACTIVE
        lifecycle, and is a required precondition for `create_goal`:
        creating a new goal while one is already ACTIVE is rejected (see
        `create_goal`'s `GoalConflictError`), so the client must call
        this first to free up the "one ACTIVE goal" slot.

        Args:
            user_id: UUID (as string) of the goal's owner.
            goal_id: UUID (as string) of the goal to transition.
            new_status: Either `"COMPLETED"` or `"ARCHIVED"`.

        Returns:
            The updated goal as a `GoalResponseDTO`.

        Raises:
            GoalNotFoundError: If no goal with `goal_id` exists for `user_id`.
            GoalConflictError: If the goal exists but isn't currently ACTIVE.
            PersistenceError: If the underlying operation fails for any
                other reason. All three are allowed to propagate to the
                Presentation layer, which maps them to HTTP responses â€”
                the Facade does not know about HTTP.
        """
        goal_record = self._goal_repository.transition_status(
            goal_id=goal_id, user_id=user_id, new_status=new_status
        )
        return self._to_response_dto(goal_record)

    def get_goal_history(self, user_id: str) -> list[GoalResponseDTO]:
        """
        Returns all goals for the user across every status, most recent first.

        Args:
            user_id: UUID (as string) of the owning user.

        Returns:
            A list of `GoalResponseDTO` instances (may be empty).

        Raises:
            PersistenceError: If the query fails.
        """
        records = self._goal_repository.get_all_goals(user_id)
        return [self._to_response_dto(r) for r in records]

    @staticmethod
    def _to_response_dto(record: GoalRecord) -> GoalResponseDTO:
        """Maps a Persistence-layer `GoalRecord` to a Presentation-layer `GoalResponseDTO`."""
        return GoalResponseDTO(
            id=record.id,
            user_id=record.user_id,
            title=record.title,
            target_amount=record.target_amount,
            saved_amount=record.saved_amount,
            category=CategoryEnum(record.category),
            deadline=record.deadline,
            status=record.status,
            created_at=record.created_at,
        )


