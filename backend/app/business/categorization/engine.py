
"""
Privacy-First Offline Categorization Engine.

Classifies raw bank transaction descriptions into a `CategoryEnum` using a
purely local Regex/Dictionary lookup â€” no network call, no third-party AI
API, no data leaving the process boundary. This module lives in the
Business layer and is only ever invoked through a Facade (see
`app/business/facades/`); it must never be imported directly by the
Presentation layer.
"""

import re
from functools import lru_cache

from app.business.categorization.models import CategoryEnum


class CategorizationEngine:
    """
    Maps a transaction description to a spending category via keyword rules.

    Design notes:
    - `_rules_dictionary` is the single source of truth for merchant/keyword
      â†’ category mappings. Extend this dict to add new merchants; no other
      code path needs to change.
    - Matching is performed with **one pre-compiled alternation regex**
      rather than iterating over the dictionary and calling `re.search`
      once per keyword. This turns classification into a single linear
      scan of the input string regardless of how large the rules
      dictionary grows, which keeps `classify()` fast enough to run
      synchronously in the request path.
    - Keywords are sorted longest-first before compilation so that a more
      specific phrase (e.g. "saudi electricity") is preferred over a
      shorter substring that might otherwise match first in an
      unordered alternation.
    """

    # Merchant / keyword â†’ category rules, tuned for a Saudi / GCC context.
    # Keys are lowercase, cleaned keywords (no punctuation); values are
    # CategoryEnum members.
    _rules_dictionary: dict[str, CategoryEnum] = {
        # --- Groceries ---
        "panda": CategoryEnum.GROCERIES,
        "othaim": CategoryEnum.GROCERIES,
        "carrefour": CategoryEnum.GROCERIES,
        "danube": CategoryEnum.GROCERIES,
        "tamimi": CategoryEnum.GROCERIES,
        # --- Utilities ---
        "stc": CategoryEnum.UTILITIES,
        "mobily": CategoryEnum.UTILITIES,
        "zain": CategoryEnum.UTILITIES,
        "electricity": CategoryEnum.UTILITIES,
        "water": CategoryEnum.UTILITIES,
        # --- Entertainment ---
        "starbucks": CategoryEnum.ENTERTAINMENT,
        "netflix": CategoryEnum.ENTERTAINMENT,
        "shahid": CategoryEnum.ENTERTAINMENT,
        "vox": CategoryEnum.ENTERTAINMENT,
        "muvi": CategoryEnum.ENTERTAINMENT,
        # --- Savings / Investment ---
        "murabaha": CategoryEnum.SAVINGS,
        "tadawul": CategoryEnum.SAVINGS,
        "wafir": CategoryEnum.SAVINGS,
        "investment": CategoryEnum.SAVINGS,
    }

    # Replaces anything that isn't a lowercase letter or digit with a single
    # space, so punctuation acts as a word separator rather than fusing
    # adjacent tokens together (e.g. "NETFLIX.COM" -> "netflix com", not
    # "netflixcom", which would otherwise break \b-anchored matching).
    _CLEAN_PATTERN = re.compile(r"[^a-z0-9]+")

    def __init__(self) -> None:
        self._pattern = self._compile_rules_pattern()

    def _compile_rules_pattern(self) -> re.Pattern[str]:
        """
        Builds a single alternation regex from `_rules_dictionary`, e.g.
        `\\b(carrefour|electricity|starbucks|...)\\b`, with keywords ordered
        longest-first so more specific phrases win over short substrings.
        """
        keywords = sorted(self._rules_dictionary.keys(), key=len, reverse=True)
        escaped = (re.escape(keyword) for keyword in keywords)
        return re.compile(rf"\b({'|'.join(escaped)})\b")

    @staticmethod
    def _clean(description: str) -> str:
        """Lowercases input and normalizes punctuation/special characters to spaces."""
        lowered = description.strip().lower()
        return CategorizationEngine._CLEAN_PATTERN.sub(" ", lowered).strip()

    def classify(self, description: str) -> CategoryEnum:
        """
        Classifies a raw transaction description into a `CategoryEnum`.

        Args:
            description: Raw merchant/transaction description as it appears
                on the bank statement (e.g. "STARBUCKS COFFEE #4521 RIYADH").

        Returns:
            The matched `CategoryEnum`, or `CategoryEnum.UNCATEGORIZED` if
            no rule matches the cleaned description.
        """
        if not description:
            return CategoryEnum.UNCATEGORIZED

        cleaned = self._clean(description)
        match = self._pattern.search(cleaned)

        if match is None:
            return CategoryEnum.UNCATEGORIZED

        return self._rules_dictionary[match.group(1)]


@lru_cache
def get_categorization_engine() -> CategorizationEngine:
    """
    Returns a cached, singleton `CategorizationEngine` instance so the rules
    pattern is compiled exactly once per process and reused by every Facade
    that depends on it (e.g. via FastAPI's `Depends`).
    """
    return CategorizationEngine()


