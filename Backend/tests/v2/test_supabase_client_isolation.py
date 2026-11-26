from threading import Event

import pytest

from app.db import supabase_client
from app.workers.queue import DevelopmentAnalysisQueue


class _Closeable:
    def __init__(self, on_close=None):
        self.closed = False
        self._on_close = on_close

    def close(self):
        self.closed = True
        if self._on_close is not None:
            self._on_close()


class _Postgrest:
    def __init__(self):
        self.session = _Closeable()

    def aclose(self):
        self.session.close()


class _FakeClient:
    def __init__(self, closed_event=None):
        self.postgrest = _Postgrest()
        self.auth = _Closeable()
        self.storage = type(
            "Storage",
            (),
            {"session": _Closeable(closed_event.set if closed_event else None)},
        )()


def test_fastapi_dependency_creates_and_closes_one_client_per_request(monkeypatch):
    created = []

    def factory(_url, _key):
        client = _FakeClient()
        created.append(client)
        return client

    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_KEY", "service-key")
    monkeypatch.setattr(supabase_client, "create_client", factory)

    dependency = supabase_client.get_supabase_client()
    first = next(dependency)
    with pytest.raises(StopIteration):
        next(dependency)

    dependency = supabase_client.get_supabase_client()
    second = next(dependency)
    dependency.close()

    assert first is not second
    assert len(created) == 2
    for client in created:
        assert client.postgrest.session.closed
        assert client.auth.closed
        assert client.storage.session.closed


def test_development_worker_uses_and_closes_job_local_client():
    closed = Event()
    completed = Event()
    job_client = _FakeClient(closed)

    class JobService:
        repository = type("Repository", (), {"db": job_client})()

        def execute_analysis(self, analysis_run_id):
            assert analysis_run_id == "run-1"
            completed.set()
            return {"status": "COMPLETE"}

    template = object()
    queue = DevelopmentAnalysisQueue(template, lambda: JobService())
    try:
        assert queue.enqueue("run-1") == "development:run-1"
        assert completed.wait(2)
        assert closed.wait(2)
    finally:
        queue.shutdown()
