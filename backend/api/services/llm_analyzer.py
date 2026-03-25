import json
from typing import List, Dict, Any, Optional
from ollama import Client
from api.config import AI_MODEL


class LLMAnalyzer:
    def __init__(self):
        self.client = Client()
        self.model = AI_MODEL

    def analyze(self, subscriptions: List[Dict]) -> Dict[str, Any]:
        if not subscriptions:
            return {
                "rationality_score": 0,
                "recommend_cancel": [],
                "recommend_keep": [],
                "alternatives": [],
                "short_comment_ru": "Нет подписок"
            }

        prompt = f"""Ты — строгий финансовый советник по подпискам. 
Отвечай **ТОЛЬКО** валидным JSON. Ни одного символа вне JSON.

Список подписок пользователя:
{json.dumps(subscriptions, ensure_ascii=False, indent=2)}

Верни ответ строго в следующем формате:

{{
  "rationality_score": число_от_0_до_100,
  "recommend_cancel": ["точное_название_подписки_1", "точное_название_подписки_2"],
  "recommend_keep": ["точное_название_подписки_3"],
  "alternatives": [
    {{"service": "точное_название_из_списка_подписок", "alternative": "короткое_название_альтернативы", "save_year_rub": число}},
    ...
  ],
  "short_comment_ru": "одно короткое предложение на русском языке"
}}

Дополнительные правила:
- recommend_cancel и recommend_keep должны содержать только точные названия из списка подписок пользователя.
- Если категория подписки "music" — альтернативы должны быть только музыкальными сервисами.
- save_year_rub — реалистичная сумма экономии в рублях за год (не маленькие числа).

Не добавляй никаких пояснений, только JSON.
"""

        try:
            resp = self.client.chat(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                options={"temperature": 0.25, "num_predict": 512}
            )
            text = resp["message"]["content"].strip()

            start = text.find("{")
            end = text.rfind("}") + 1
            return json.loads(text[start:end])

        except:
            return {
                "rationality_score": 50,
                "recommend_cancel": [],
                "recommend_keep": [s["name"] for s in subscriptions],
                "alternatives": [],
                "short_comment_ru": "Не удалось получить анализ"
            }


analyzer = LLMAnalyzer()