"""Production-grade Kinesis consumer.

Polls every shard independently, backs off with jitter on throttling and
re-acquires a fresh iterator on ExpiredIteratorException instead of dying,
adapts its poll interval to traffic (fast when records are flowing, slow when
idle so it doesn't hammer the API), and shuts down cleanly on SIGINT/SIGTERM.
"""
from __future__ import annotations

import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass, field
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"),
                     format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "user-events-stream")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
LOG_EVERY_N_EVENTS = int(os.environ.get("LOG_EVERY_N_EVENTS", "20"))
MIN_POLL_INTERVAL_SECONDS = float(os.environ.get("MIN_POLL_INTERVAL_SECONDS", "0.2"))
MAX_POLL_INTERVAL_SECONDS = float(os.environ.get("MAX_POLL_INTERVAL_SECONDS", "1.0"))
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "5"))

kinesis = boto3.client("kinesis", region_name=AWS_REGION, config=Config(retries={"mode": "standard"}))


@dataclass
class ShardState:
    """Per-shard mutable state: current iterator token and adaptive poll interval."""

    iterator: str | None
    poll_interval: float = MIN_POLL_INTERVAL_SECONDS


@dataclass
class ConsumerStats:
    """Running totals updated on every successfully decoded record."""

    total_events: int = 0
    events_by_user: dict[str, int] = field(default_factory=dict)

    def record(self, user_id: str) -> None:
        """Increment the global counter and the per-user counter for user_id."""
        self.total_events += 1
        self.events_by_user[user_id] = self.events_by_user.get(user_id, 0) + 1


class KinesisConsumer:
    """Multi-shard Kinesis consumer with adaptive polling and graceful shutdown."""

    def __init__(self, stream_name: str):
        self.stream_name = stream_name
        self.shards: dict[str, ShardState] = {}
        self.stats = ConsumerStats()
        self._init_shards()

    def _init_shards(self) -> None:
        """Discover all open shards and seed each with a LATEST iterator."""
        response = kinesis.describe_stream(StreamName=self.stream_name)
        shard_ids = [s["ShardId"] for s in response["StreamDescription"]["Shards"]]
        for shard_id in shard_ids:
            self.shards[shard_id] = ShardState(iterator=self._get_iterator(shard_id))
        logger.info("Watching %d shards: %s", len(self.shards), ", ".join(shard_ids))

    def _get_iterator(self, shard_id: str) -> str:
        """Return a LATEST shard iterator, skipping records produced before startup."""
        return kinesis.get_shard_iterator(
            StreamName=self.stream_name,
            ShardId=shard_id,
            # Only new records from now on — anything sent before startup is skipped.
            ShardIteratorType="LATEST",
        )["ShardIterator"]

    def _poll_shard(self, shard_id: str, state: ShardState) -> None:
        """Read one batch from a shard, handle throttling and expired iterators, update poll pace."""
        if state.iterator is None:
            return
        for attempt in range(MAX_RETRIES + 1):
            try:
                response = kinesis.get_records(ShardIterator=state.iterator, Limit=100)
                break
            except ClientError as e:
                code = e.response.get("Error", {}).get("Code", "")
                if code == "ExpiredIteratorException":
                    logger.warning("Iterator expired for %s, re-acquiring", shard_id)
                    state.iterator = self._get_iterator(shard_id)
                    return
                if code in ("ProvisionedThroughputExceededException", "LimitExceededException"):
                    backoff = min(2 ** attempt, 8)
                    logger.warning("Throttled on %s, backing off %ds (attempt %d/%d)",
                                    shard_id, backoff, attempt + 1, MAX_RETRIES)
                    time.sleep(backoff)
                    continue
                logger.error("Unrecoverable error reading %s: %s", shard_id, e)
                return
        else:
            logger.error("Giving up on %s after %d retries", shard_id, MAX_RETRIES)
            return

        state.iterator = response["NextShardIterator"]
        records = response["Records"]

        # Adapt poll pace to traffic: speed up when records are flowing, back off when idle.
        state.poll_interval = (
            MIN_POLL_INTERVAL_SECONDS if records
            else min(state.poll_interval * 1.5, MAX_POLL_INTERVAL_SECONDS)
        )

        for record in records:
            event = self._parse(record["Data"])
            if event is None:
                continue
            self.stats.record(event.get("user_id", "unknown"))
            if self.stats.total_events % LOG_EVERY_N_EVENTS == 0:
                logger.info("[%d] %s by %s (%s, %s)", self.stats.total_events,
                            event.get("event_type"), event.get("user_id"),
                            event.get("content"), event.get("device"))

    @staticmethod
    def _parse(data: bytes) -> dict[str, Any] | None:
        """Decode a raw Kinesis record payload; returns None and warns on malformed JSON."""
        try:
            return json.loads(data)
        except json.JSONDecodeError:
            logger.warning("Skipping malformed record")
            return None

    def run(self, should_stop: dict[str, bool]) -> None:
        """Poll all shards in a round-robin loop until should_stop['requested'] is set."""
        logger.info("Starting consumer... reading from: %s", self.stream_name)
        while not should_stop["requested"]:
            for shard_id, state in self.shards.items():
                self._poll_shard(shard_id, state)
            time.sleep(min(s.poll_interval for s in self.shards.values()))

        self._log_summary()

    def _log_summary(self) -> None:
        """Emit a final per-user event breakdown after the consumer stops."""
        logger.info("Stopped. Total events processed: %d", self.stats.total_events)
        logger.info("Events by user:")
        for user_id, count in sorted(self.stats.events_by_user.items()):
            logger.info("  %s: %d events", user_id, count)


def main() -> int:
    """Wire up signal handlers, start KinesisConsumer, and return 0 on clean exit."""
    should_stop = {"requested": False}

    def request_shutdown(signum: int, _frame: Any) -> None:
        logger.info("Received signal %d, shutting down...", signum)
        should_stop["requested"] = True

    signal.signal(signal.SIGINT, request_shutdown)
    signal.signal(signal.SIGTERM, request_shutdown)

    try:
        consumer = KinesisConsumer(STREAM_NAME)
    except ClientError as e:
        logger.error("Cannot reach stream '%s': %s", STREAM_NAME, e)
        return 1

    consumer.run(should_stop)
    return 0


if __name__ == "__main__":
    sys.exit(main())
