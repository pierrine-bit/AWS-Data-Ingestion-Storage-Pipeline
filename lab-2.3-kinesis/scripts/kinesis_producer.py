"""Production-grade Kinesis event producer.

Batches events via put_records (fewer API calls, higher throughput than
put_record), retries only the records a batch partially failed on with
exponential backoff, and shuts down cleanly on SIGINT/SIGTERM — flushing
whatever is buffered before exit rather than dropping it.
"""
from __future__ import annotations

import json
import logging
import os
import random
import signal
import sys
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"),
                     format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "user-events-stream")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
EVENTS_PER_SECOND = float(os.environ.get("EVENTS_PER_SECOND", "5"))
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "25"))
BATCH_FLUSH_INTERVAL_SECONDS = float(os.environ.get("BATCH_FLUSH_INTERVAL_SECONDS", "1.0"))
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "5"))

EVENT_TYPES = ["play", "pause", "resume", "seek_forward", "seek_backward",
               "stop", "like", "dislike", "share"]
USER_IDS = ["user_001", "user_002", "user_003", "user_004", "user_005"]
CONTENT_TITLES = ["Stranger Things", "The Crown", "Bridgerton",
                   "The Witcher", "Black Mirror"]
DEVICES = ["web", "mobile", "tv"]
REGIONS = ["us-east", "us-west", "eu-west", "ap-southeast"]

kinesis = boto3.client("kinesis", region_name=AWS_REGION, config=Config(retries={"mode": "standard"}))


@dataclass
class UserEvent:
    """Immutable schema for a single streaming user-interaction event."""

    timestamp: str
    user_id: str
    event_type: str
    content: str
    duration_seconds: int
    device: str
    region: str


@dataclass
class ProducerStats:
    """Mutable counters updated after every put_records call."""

    sent: int = 0
    failed: int = 0
    start_time: float = 0.0

    def rate(self) -> float:
        """Return the average events-per-second throughput since start_time."""
        elapsed = time.time() - self.start_time
        return self.sent / elapsed if elapsed > 0 else 0.0


def generate_event() -> UserEvent:
    """Return a randomly generated UserEvent with a UTC timestamp."""
    return UserEvent(
        timestamp=datetime.now(timezone.utc).isoformat(),
        user_id=random.choice(USER_IDS),
        event_type=random.choice(EVENT_TYPES),
        content=random.choice(CONTENT_TITLES),
        duration_seconds=random.randint(1, 3600),
        device=random.choice(DEVICES),
        region=random.choice(REGIONS),
    )


def to_kinesis_record(event: UserEvent) -> dict[str, Any]:
    """Serialize a UserEvent to the dict format expected by put_records."""
    return {
        "Data": json.dumps(asdict(event)).encode("utf-8"),
        # Groups one user's events on the same shard to preserve per-user ordering.
        "PartitionKey": event.user_id,
    }


def put_records_with_retry(records: list[dict[str, Any]], stats: ProducerStats) -> None:
    """Send a batch via put_records, retrying only the records that failed."""
    pending = records
    for attempt in range(MAX_RETRIES + 1):
        if not pending:
            return
        try:
            response = kinesis.put_records(StreamName=STREAM_NAME, Records=pending)
        except ClientError as e:
            logger.error("put_records call failed (attempt %d/%d): %s", attempt + 1, MAX_RETRIES, e)
            time.sleep(2 ** attempt)
            continue

        if response.get("FailedRecordCount", 0) == 0:
            stats.sent += len(pending)
            return

        retryable = [
            rec for rec, result in zip(pending, response["Records"])
            if "ErrorCode" in result
        ]
        stats.sent += len(pending) - len(retryable)
        pending = retryable
        if pending:
            backoff = min(2 ** attempt, 10) + random.uniform(0, 0.5)
            logger.warning("%d records throttled/failed, retrying in %.1fs (attempt %d/%d)",
                            len(pending), backoff, attempt + 1, MAX_RETRIES)
            time.sleep(backoff)

    if pending:
        stats.failed += len(pending)
        logger.error("Dropped %d records after %d retries", len(pending), MAX_RETRIES)


def verify_stream_active() -> None:
    """Fail fast with a clear error if the stream doesn't exist or isn't ready."""
    try:
        status = kinesis.describe_stream_summary(StreamName=STREAM_NAME)["StreamDescriptionSummary"]["StreamStatus"]
    except ClientError as e:
        logger.error("Cannot reach stream '%s': %s", STREAM_NAME, e)
        raise SystemExit(1)
    if status != "ACTIVE":
        logger.error("Stream '%s' is not ACTIVE (status=%s)", STREAM_NAME, status)
        raise SystemExit(1)


def main() -> int:
    """Run the producer loop: verify stream, buffer events, flush via put_records, shutdown cleanly."""
    verify_stream_active()
    logger.info("Producer -> %s (%.1f events/sec, batch_size=%d)", STREAM_NAME, EVENTS_PER_SECOND, BATCH_SIZE)

    stats = ProducerStats(start_time=time.time())
    buffer: list[dict[str, Any]] = []
    last_flush = time.time()
    shutdown = {"requested": False}

    def request_shutdown(signum: int, _frame: Any) -> None:
        logger.info("Received signal %d, shutting down after final flush...", signum)
        shutdown["requested"] = True

    signal.signal(signal.SIGINT, request_shutdown)
    signal.signal(signal.SIGTERM, request_shutdown)

    interval = 1.0 / EVENTS_PER_SECOND if EVENTS_PER_SECOND > 0 else 0

    while not shutdown["requested"]:
        buffer.append(to_kinesis_record(generate_event()))

        due_for_flush = len(buffer) >= BATCH_SIZE or (time.time() - last_flush) >= BATCH_FLUSH_INTERVAL_SECONDS
        if due_for_flush and buffer:
            put_records_with_retry(buffer, stats)
            buffer = []
            last_flush = time.time()
            if stats.sent and stats.sent % (BATCH_SIZE * 4) < BATCH_SIZE:
                logger.info("[%d sent, %d failed] %.1f events/sec", stats.sent, stats.failed, stats.rate())

        time.sleep(interval)

    if buffer:
        put_records_with_retry(buffer, stats)

    elapsed = time.time() - stats.start_time
    logger.info("Stopped. Sent=%d Failed=%d Elapsed=%.1fs AvgRate=%.1f/s",
                stats.sent, stats.failed, elapsed, stats.rate())
    return 0 if stats.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
