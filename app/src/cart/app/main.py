from fastapi import FastAPI
import logging
import re
import time
from prometheus_fastapi_instrumentator import Instrumentator
from app.config import settings
from app.router import router

app = FastAPI(title="Cart Service")
logger = logging.getLogger(__name__)
safe_request_id = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


@app.middleware("http")
async def request_log(request, call_next):
    start = time.perf_counter()
    supplied = request.headers.get("x-request-id", "")
    request_id = supplied if safe_request_id.fullmatch(supplied) else None
    try:
        response = await call_next(request)
    except Exception as error:
        logger.exception("Unhandled request error", extra={"error_type": type(error).__name__})
        raise
    route = getattr(request.scope.get("route"), "path", "unmatched")
    fields = {
        "method": request.method,
        "route": route,
        "status": response.status_code,
        "duration_ms": round((time.perf_counter() - start) * 1000, 3),
    }
    if request_id:
        fields["request_id"] = request_id
    logger.log(logging.ERROR if response.status_code >= 500 else logging.INFO, "HTTP request", extra=fields)
    return response


@app.on_event("startup")
def startup():
    if settings.cart_persistence_provider == "postgres":
        from app.postgres_service import PostgresCartService
        app.state.cart_service = PostgresCartService()
    else:
        from app.service import InMemoryCartService
        app.state.cart_service = InMemoryCartService()
    logger.info("Cart service started")


@app.get("/topology")
def topology():
    return {"provider": settings.cart_persistence_provider}


@app.get("/health")
def health():
    return {"status": "UP"}


app.include_router(router)
Instrumentator().instrument(app).expose(app, endpoint="/metrics")
