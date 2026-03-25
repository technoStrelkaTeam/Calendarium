from enum import Enum

class Interval(str, Enum):
    day   = "day"
    month = "month"
    year  = "year"