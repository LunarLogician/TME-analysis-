import asyncio
from typing import Optional

from fastapi import HTTPException
from starlette.requests import Request
import pytest

from app.middleware.auth import AuthUser, require_admin, require_auth, require_clinician


def _request(authorization: Optional[str] = None) -> Request:
    headers = []
    if authorization is not None:
        headers.append((b"authorization", authorization.encode("utf-8")))
    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/protected",
            "headers": headers,
        }
    )


def test_missing_auth_header_is_rejected():
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(require_auth(_request()))
    assert exc_info.value.status_code == 401


def test_invalid_bearer_token_is_rejected():
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(require_auth(_request("Bearer invalid-token")))
    assert exc_info.value.status_code == 401


def test_patient_cannot_use_clinician_endpoint():
    patient = AuthUser("patient-id", "patient@example.com", "patient")
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(require_clinician(patient))
    assert exc_info.value.status_code == 403


def test_clinician_cannot_use_admin_endpoint():
    clinician = AuthUser("clinician-id", "doctor@example.com", "clinician")
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(require_admin(clinician))
    assert exc_info.value.status_code == 403
