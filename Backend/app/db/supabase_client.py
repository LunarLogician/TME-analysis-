import os
from collections.abc import Generator

from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()


def create_supabase_service_client() -> Client:
    """Create an isolated synchronous client and HTTP connection pool."""
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_service_key = os.getenv("SUPABASE_SERVICE_KEY")
    if not supabase_url or not supabase_service_key:
        raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in .env")
    return create_client(supabase_url, supabase_service_key)


def close_supabase_client(client: Client) -> None:
    """Close every lazily-created HTTP client exposed by supabase-py 2.x."""
    try:
        client.postgrest.aclose()
    except Exception:
        pass
    try:
        client.auth.close()
    except Exception:
        pass
    try:
        client.storage.session.close()
    except Exception:
        pass


def get_supabase_client() -> Generator[Client, None, None]:
    """FastAPI dependency providing one non-shared client per request."""
    client = create_supabase_service_client()
    try:
        yield client
    finally:
        close_supabase_client(client)
