from __future__ import annotations

import logging
import traceback
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any

LOG_DIR = Path(__file__).resolve().parents[1] / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)


def _make_logger(name: str, filename: str) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)
    logger.propagate = False

    handler = RotatingFileHandler(
        LOG_DIR / filename,
        maxBytes=5 * 1024 * 1024,
        backupCount=5,
        encoding="utf-8",
    )
    handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(message)s"))
    logger.addHandler(handler)
    return logger


request_logger = _make_logger("cnc_api.requests", "api_requests.log")
db_logger = _make_logger("cnc_api.database", "api_db.log")
error_logger = _make_logger("cnc_api.errors", "api_errors.log")


def _one_line(value: Any, limit: int = 700) -> str:
    text = " ".join(str(value).replace("\r", " ").replace("\n", " ").split())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def log_request(method: str, path: str, query: str, status: int, elapsed_ms: float) -> None:
    request_logger.info(
        "method=%s path=%s query=%s status=%s elapsed_ms=%.2f",
        method,
        path,
        query or "-",
        status,
        elapsed_ms,
    )


def log_db(operation: str, sql: str, params: Any, elapsed_ms: float, rows: int | None, ok: bool) -> None:
    db_logger.info(
        "operation=%s ok=%s elapsed_ms=%.2f rows=%s sql=%s params=%s",
        operation,
        ok,
        elapsed_ms,
        "-" if rows is None else rows,
        _one_line(sql),
        _one_line(repr(params), 500),
    )


def log_error(source: str, message: str, exc: BaseException | None = None, **context: Any) -> None:
    ctx = " ".join(f"{k}={_one_line(v, 300)}" for k, v in context.items())
    if exc is None:
        error_logger.error("source=%s message=%s %s", source, _one_line(message), ctx)
    else:
        error_logger.error(
            "source=%s message=%s exception=%s %s\n%s",
            source,
            _one_line(message),
            repr(exc),
            ctx,
            traceback.format_exc(),
        )
