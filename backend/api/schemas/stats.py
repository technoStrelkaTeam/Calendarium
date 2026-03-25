from pydantic import BaseModel
from typing import List, Dict, Any

class PeriodAmount(BaseModel):
    period: str
    amount: float

class CategoryAmount(BaseModel):
    category: str
    amount: float
    percent: float

class ChartData(BaseModel):
    monthly: List[PeriodAmount]
    quarterly: List[PeriodAmount]
    by_category: List[CategoryAmount]
    forecast_12_months: float

class AiInsights(BaseModel):
    rationality_score: int
    recommend_cancel: List[str]
    recommend_keep: List[str]
    alternatives: List[Dict[str, Any]]
    short_comment_ru: str