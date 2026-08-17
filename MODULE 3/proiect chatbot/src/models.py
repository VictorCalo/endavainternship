from dataclasses import dataclass, field
from typing import Any


Match = dict[str, Any]


@dataclass
class ToolResolution:
    response: Any
    recommended_title: str | None = None
    detailed_summary: str | None = None
    tool_requested_by_model: bool = False


@dataclass
class BookQuestionResult:
    answer: str
    matches: list[Match] = field(default_factory=list)
    recommended_title: str | None = None
    tool_called: bool = False
    tool_summary_found: bool = False
    tool_call_source: str = "not_called"


@dataclass
class MessagePayload:
    role: str
    content: str
    matches: list[Match] = field(default_factory=list)
    recommended_title: str | None = None
    tool_summary_found: bool = False
    tool_call_source: str = "necunoscut"

