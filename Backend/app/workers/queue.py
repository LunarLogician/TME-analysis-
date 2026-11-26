"""RQ production queue with an explicit development-only local executor."""

from __future__ import annotations

import os
import logging
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import Future
from typing import Callable, Protocol

from app.db.supabase_client import close_supabase_client


logger = logging.getLogger(__name__)


class AnalysisQueue(Protocol):
    def enqueue(self, analysis_run_id: str) -> str: ...

    def shutdown(self) -> None: ...


class RQAnalysisQueue:
    def __init__(self, redis_url: str | None = None):
        try:
            from redis import Redis
            from rq import Queue
        except ImportError as exc:
            raise RuntimeError("Production analysis queue requires redis and rq") from exc
        configured = redis_url or os.getenv("REDIS_URL")
        if not configured:
            raise RuntimeError("REDIS_URL is required for the durable analysis queue")
        self.queue = Queue(
            "tme-analysis",
            connection=Redis.from_url(configured),
            default_timeout=int(os.getenv("TME_ANALYSIS_JOB_TIMEOUT", "3600")),
        )

    def enqueue(self, analysis_run_id: str) -> str:
        job = self.queue.enqueue(
            "app.workers.analysis_worker.execute_analysis_job",
            analysis_run_id,
            job_id=f"tme-analysis:{analysis_run_id}",
            retry=self._retry_policy(),
        )
        return str(job.id)

    def shutdown(self) -> None:
        """RQ owns no process-local worker resources."""

    @staticmethod
    def _retry_policy():
        from rq import Retry

        return Retry(max=2, interval=[10, 60])


class DevelopmentAnalysisQueue:
    """Non-production convenience queue; production startup never selects it."""

    def __init__(self, service, service_factory: Callable | None = None):
        self.service = service
        self.service_factory = service_factory
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="tme-v2-dev")

    def enqueue(self, analysis_run_id: str) -> str:
        future = self.executor.submit(self._execute, analysis_run_id)
        future.add_done_callback(
            lambda completed: self._log_result(analysis_run_id, completed)
        )
        return f"development:{analysis_run_id}"

    def _execute(self, analysis_run_id: str):
        job_service = self.service_factory() if self.service_factory else self.service
        try:
            return job_service.execute_analysis(analysis_run_id)
        finally:
            if job_service is not self.service:
                client = getattr(job_service.repository, "db", None)
                if client is not None:
                    close_supabase_client(client)

    @staticmethod
    def _log_result(analysis_run_id: str, future: Future) -> None:
        try:
            future.result()
        except Exception:
            logger.exception("Development V2 analysis failed for run %s", analysis_run_id)

    def shutdown(self) -> None:
        self.executor.shutdown(wait=False, cancel_futures=False)


def build_analysis_queue(
    service, *, development_service_factory: Callable | None = None
) -> AnalysisQueue:
    environment = os.getenv("ENV", "development").strip().lower()
    mode = os.getenv(
        "TME_ANALYSIS_QUEUE", "rq" if environment == "production" else "development"
    ).strip().lower()
    if mode == "rq":
        return RQAnalysisQueue()
    if mode == "development" and environment != "production":
        return DevelopmentAnalysisQueue(service, development_service_factory)
    raise RuntimeError("Production requires TME_ANALYSIS_QUEUE=rq")
