from collections import defaultdict
from datetime import date
from dateutil.relativedelta import relativedelta
from typing import List

from api.models.subscribe import Subscribe
from api.models.enums import Interval
from api.schemas.stats import ChartData, PeriodAmount, CategoryAmount


class ChartService:
    @staticmethod
    def generate(subs: List[Subscribe]) -> ChartData:
        if not subs:
            return ChartData(monthly=[], quarterly=[], by_category=[], forecast_12_months=0.0)

        today = date.today()
        monthly_cost = defaultdict(float)
        quarterly_cost = defaultdict(float)
        category_annual = defaultdict(float)
        annual = 0.0

        for sub in subs:
            if sub.type_interval == Interval.month:
                m = float(sub.cost)
            elif sub.type_interval == Interval.year:
                m = sub.cost / 12
            elif sub.type_interval == Interval.day:
                m = sub.cost * 30.4375
            else:
                m = 0.0

            annual += m * 12
            cat = sub.category or "Без категории"
            category_annual[cat] += m * 12

            current = today
            for _ in range(12):
                monthly_cost[current.strftime("%Y-%m")] += m
                q = ((current.month - 1) // 3) + 1
                quarterly_cost[f"{current.year}-Q{q}"] += m * 3
                current += relativedelta(months=1)

        total = sum(category_annual.values()) or 1
        return ChartData(
            monthly=[PeriodAmount(period=k, amount=round(v, 1)) for k, v in sorted(monthly_cost.items())],
            quarterly=[PeriodAmount(period=k, amount=round(v, 1)) for k, v in sorted(quarterly_cost.items())],
            by_category=[
                CategoryAmount(category=k, amount=round(v, 1), percent=round(v / total * 100, 1))
                for k, v in sorted(category_annual.items(), key=lambda x: x[1], reverse=True)
            ],
            forecast_12_months=round(annual, 1)
        )