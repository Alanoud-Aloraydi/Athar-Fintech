"""
Privacy-First Offline Categorization Engine.

Classifies raw bank transaction descriptions into a `CategoryEnum` using a
purely local Regex/Dictionary lookup — no network call, no third-party AI
API, no data leaving the process boundary. This module lives in the
Business layer and is only ever invoked through a Facade (see
`app/business/facades/`); it must never be imported directly by the
Presentation layer.

Bilingual design (English + Arabic):
- English pass: single pre-compiled alternation regex with \\b word-boundaries.
  Keywords sorted longest-first so specific phrases beat short substrings.
- Arabic pass: plain substring scan after diacritic normalisation.
  \\b boundaries don't work with Arabic Unicode, so we use a simple
  linear scan instead — still O(n × k) worst-case but k is small and fixed.
"""

import re
from functools import lru_cache

from app.business.categorization.models import CategoryEnum


class CategorizationEngine:
    """
    Maps a transaction description to a spending category via keyword rules.

    Call `classify(description)` — returns a `CategoryEnum`.
    """

    # ── English / Latin keywords ──────────────────────────────────────────
    _en_rules: dict[str, CategoryEnum] = {
        # ── Food & Dining ────────────────────────────────────────────────
        "burger king": CategoryEnum.FOOD,    # longest first for regex
        "apple music": CategoryEnum.FOOD,    # placeholder: overridden by ENTERTAINMENT below
        "gas station": CategoryEnum.TRANSPORT,
        "farm superstore": CategoryEnum.GROCERIES,
        "saudi aramco": CategoryEnum.UTILITIES,
        "riyad bank": CategoryEnum.SAVINGS,
        "starbucks": CategoryEnum.FOOD,
        "restaurant": CategoryEnum.FOOD,
        "mcdonalds": CategoryEnum.FOOD,
        "mcdonald": CategoryEnum.FOOD,
        "albaik": CategoryEnum.FOOD,
        "coffee": CategoryEnum.FOOD,
        "pizza": CategoryEnum.FOOD,
        "shawarma": CategoryEnum.FOOD,
        "cafe": CategoryEnum.FOOD,
        # ── Groceries ────────────────────────────────────────────────────
        "carrefour": CategoryEnum.GROCERIES,
        "danube": CategoryEnum.GROCERIES,
        "tamimi": CategoryEnum.GROCERIES,
        "hypermarket": CategoryEnum.GROCERIES,
        "supermarket": CategoryEnum.GROCERIES,
        "othaim": CategoryEnum.GROCERIES,
        "panda": CategoryEnum.GROCERIES,
        "lulu": CategoryEnum.GROCERIES,
        # ── Utilities ────────────────────────────────────────────────────
        "electricity": CategoryEnum.UTILITIES,
        "internet": CategoryEnum.UTILITIES,
        "mobily": CategoryEnum.UTILITIES,
        "water": CategoryEnum.UTILITIES,
        "zain": CategoryEnum.UTILITIES,
        "stc": CategoryEnum.UTILITIES,
        "sec": CategoryEnum.UTILITIES,
        # ── Entertainment ────────────────────────────────────────────────
        "playstation": CategoryEnum.ENTERTAINMENT,
        "apple music": CategoryEnum.ENTERTAINMENT,
        "shahid": CategoryEnum.ENTERTAINMENT,
        "spotify": CategoryEnum.ENTERTAINMENT,
        "cinema": CategoryEnum.ENTERTAINMENT,
        "gaming": CategoryEnum.ENTERTAINMENT,
        "netflix": CategoryEnum.ENTERTAINMENT,
        "muvi": CategoryEnum.ENTERTAINMENT,
        "vox": CategoryEnum.ENTERTAINMENT,
        # ── Health ───────────────────────────────────────────────────────
        "pharmacy": CategoryEnum.HEALTH,
        "hospital": CategoryEnum.HEALTH,
        "medical": CategoryEnum.HEALTH,
        "clinic": CategoryEnum.HEALTH,
        "doctor": CategoryEnum.HEALTH,
        "nahdi": CategoryEnum.HEALTH,
        "dawaa": CategoryEnum.HEALTH,
        # ── Transport ────────────────────────────────────────────────────
        "careem": CategoryEnum.TRANSPORT,
        "petrol": CategoryEnum.TRANSPORT,
        "fuel": CategoryEnum.TRANSPORT,
        "taxi": CategoryEnum.TRANSPORT,
        "uber": CategoryEnum.TRANSPORT,
        # ── Housing ──────────────────────────────────────────────────────
        "maintenance": CategoryEnum.HOUSING,
        "rent": CategoryEnum.HOUSING,
        # ── Shopping ─────────────────────────────────────────────────────
        "namshi": CategoryEnum.SHOPPING,
        "amazon": CategoryEnum.SHOPPING,
        "noon": CategoryEnum.SHOPPING,
        "zara": CategoryEnum.SHOPPING,
        # ── Savings / Investment ─────────────────────────────────────────
        "investment": CategoryEnum.SAVINGS,
        "murabaha": CategoryEnum.SAVINGS,
        "tadawul": CategoryEnum.SAVINGS,
        "savings": CategoryEnum.SAVINGS,
        "wafir": CategoryEnum.SAVINGS,
        "alinma": CategoryEnum.SAVINGS,
        "salary": CategoryEnum.SAVINGS,
        "kfc": CategoryEnum.FOOD,
    }

    # ── Arabic keywords ───────────────────────────────────────────────────
    # Checked in descending length order so longer phrases win on overlap.
    _ar_rules: dict[str, CategoryEnum] = {
        # ── Savings — most specific phrases first ────────────────────────
        "صندوق الاستثمار": CategoryEnum.SAVINGS,
        "تحويل ادخار": CategoryEnum.SAVINGS,
        "ادخار شهري": CategoryEnum.SAVINGS,
        "توفير شهري": CategoryEnum.SAVINGS,
        "مواد غذائية": CategoryEnum.GROCERIES,
        "استثمار": CategoryEnum.SAVINGS,
        "ادخار": CategoryEnum.SAVINGS,
        "توفير": CategoryEnum.SAVINGS,
        "وديعة": CategoryEnum.SAVINGS,
        "راتب": CategoryEnum.SAVINGS,
        # ── Food & Dining ────────────────────────────────────────────────
        "كافيتريا": CategoryEnum.FOOD,
        "كافيه": CategoryEnum.FOOD,
        "شاورما": CategoryEnum.FOOD,
        "مطعم": CategoryEnum.FOOD,
        "مقهى": CategoryEnum.FOOD,
        "قهوة": CategoryEnum.FOOD,
        "وجبة": CategoryEnum.FOOD,
        "برغر": CategoryEnum.FOOD,
        "بيتزا": CategoryEnum.FOOD,
        # ── Groceries ────────────────────────────────────────────────────
        "تموينات": CategoryEnum.GROCERIES,
        "هايبر": CategoryEnum.GROCERIES,
        "ماركت": CategoryEnum.GROCERIES,
        "سوبر": CategoryEnum.GROCERIES,
        "بقالة": CategoryEnum.GROCERIES,
        "خضار": CategoryEnum.GROCERIES,
        # ── Utilities ────────────────────────────────────────────────────
        "اتصالات": CategoryEnum.UTILITIES,
        "إنترنت": CategoryEnum.UTILITIES,
        "انترنت": CategoryEnum.UTILITIES,
        "فواتير": CategoryEnum.UTILITIES,
        "فاتورة": CategoryEnum.UTILITIES,
        "كهرباء": CategoryEnum.UTILITIES,
        "هاتف": CategoryEnum.UTILITIES,
        "مياه": CategoryEnum.UTILITIES,
        "ماء": CategoryEnum.UTILITIES,
        # ── Entertainment ────────────────────────────────────────────────
        "نتفليكس": CategoryEnum.ENTERTAINMENT,
        "اشتراك": CategoryEnum.ENTERTAINMENT,
        "سينما": CategoryEnum.ENTERTAINMENT,
        "ترفيه": CategoryEnum.ENTERTAINMENT,
        "ألعاب": CategoryEnum.ENTERTAINMENT,
        "العاب": CategoryEnum.ENTERTAINMENT,
        "شاهد": CategoryEnum.ENTERTAINMENT,
        # ── Health ────────────────────────────────────────────────────────
        "مستشفى": CategoryEnum.HEALTH,
        "صيدلية": CategoryEnum.HEALTH,
        "عيادة": CategoryEnum.HEALTH,
        "طبيب": CategoryEnum.HEALTH,
        "دواء": CategoryEnum.HEALTH,
        # ── Transport ────────────────────────────────────────────────────
        "بنزين": CategoryEnum.TRANSPORT,
        "وقود": CategoryEnum.TRANSPORT,
        "تاكسي": CategoryEnum.TRANSPORT,
        "نقل": CategoryEnum.TRANSPORT,
        # ── Housing ──────────────────────────────────────────────────────
        "إيجار": CategoryEnum.HOUSING,
        "ايجار": CategoryEnum.HOUSING,
        "صيانة": CategoryEnum.HOUSING,
        # ── Shopping ─────────────────────────────────────────────────────
        "ملابس": CategoryEnum.SHOPPING,
        "تسوق": CategoryEnum.SHOPPING,
    }

    # Pre-sort Arabic rules longest-first so more specific phrases win.
    _ar_rules_sorted: list[tuple[str, CategoryEnum]] = sorted(
        _ar_rules.items(), key=lambda kv: len(kv[0]), reverse=True
    )

    # Strip non-alphanumeric (English pass)
    _CLEAN_EN = re.compile(r"[^a-z0-9]+")
    # Strip Arabic diacritics / tashkeel (Arabic pass)
    _CLEAN_AR = re.compile(r"[\u0610-\u061a\u064b-\u065f\u0670]+")

    def __init__(self) -> None:
        self._en_pattern = self._compile_en_pattern()

    def _compile_en_pattern(self) -> re.Pattern[str]:
        keywords = sorted(self._en_rules.keys(), key=len, reverse=True)
        escaped = (re.escape(k) for k in keywords)
        return re.compile(rf"\b({'|'.join(escaped)})\b")

    @staticmethod
    def _clean_en(description: str) -> str:
        lowered = description.strip().lower()
        return CategorizationEngine._CLEAN_EN.sub(" ", lowered).strip()

    @staticmethod
    def _clean_ar(description: str) -> str:
        """Remove diacritics and normalise whitespace for Arabic matching."""
        stripped = CategorizationEngine._CLEAN_AR.sub("", description.strip())
        return " ".join(stripped.split())

    def classify(self, description: str) -> CategoryEnum:
        """
        Classifies a raw transaction description into a `CategoryEnum`.

        Runs an English regex pass first, then an Arabic substring pass.

        Args:
            description: Raw merchant/transaction description (Arabic or Latin).

        Returns:
            The matched `CategoryEnum`, or `CategoryEnum.UNCATEGORIZED` if
            no rule matches.
        """
        if not description:
            return CategoryEnum.UNCATEGORIZED

        # 1. English / Latin pass (fast regex, \b-bounded)
        en_cleaned = self._clean_en(description)
        m = self._en_pattern.search(en_cleaned)
        if m:
            return self._en_rules[m.group(1)]

        # 2. Arabic pass (substring scan, longest-match wins)
        ar_cleaned = self._clean_ar(description)
        for keyword, category in self._ar_rules_sorted:
            if keyword in ar_cleaned:
                return category

        return CategoryEnum.UNCATEGORIZED


@lru_cache
def get_categorization_engine() -> CategorizationEngine:
    """
    Returns a cached, singleton `CategorizationEngine` instance so the rules
    pattern is compiled exactly once per process and reused by every Facade
    that depends on it.
    """
    return CategorizationEngine()
