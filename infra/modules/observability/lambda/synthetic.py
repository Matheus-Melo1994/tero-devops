"""Chequeo sintético de Tero: recorre desde Internet lo mismo que un cliente y publica el resultado.

Lo ejecuta EventBridge cada pocos minutos. Pide al ALB público del ambiente:

  ui-health         GET /health                 -> 200
  catalog-products  GET /api/catalog/products   -> 200 y una lista JSON no vacía (ui -> catalog -> RDS)
  admin-panel       GET /admin/                 -> 200 (el panel responde detrás del ALB)

Publica en CloudWatch (namespace Tero/Synthetics, dimensión Environment) Success (1/0) y LatencyMs
por chequeo, y AllChecksPassed para el ambiente. Escribe una línea JSON por chequeo en su log.
No envía credenciales ni datos de clientes, y no lee respuestas más allá de lo que valida.
"""

import json
import os
import time
import urllib.error
import urllib.request

import boto3

BASE_URL = os.environ["TARGET_BASE_URL"].rstrip("/")
ENVIRONMENT = os.environ["TERO_ENVIRONMENT"]
NAMESPACE = os.environ.get("METRIC_NAMESPACE", "Tero/Synthetics")
TIMEOUT_SECONDS = float(os.environ.get("TIMEOUT_SECONDS", "5"))
MAX_BODY_BYTES = 1_000_000

CHECKS = (
    {"name": "ui-health", "path": "/health", "expect_list": False},
    {"name": "catalog-products", "path": "/api/catalog/products", "expect_list": True},
    {"name": "admin-panel", "path": "/admin/", "expect_list": False},
)

cloudwatch = boto3.client("cloudwatch")


def run_check(check):
    started = time.monotonic()
    status = None
    error = None
    try:
        request = urllib.request.Request(BASE_URL + check["path"], headers={"User-Agent": "tero-synthetic/1.0"})
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310 (URL fija del ALB)
            status = response.status
            body = response.read(MAX_BODY_BYTES)
        if status != 200:
            error = "unexpected-status"
        elif check["expect_list"]:
            data = json.loads(body)
            if not isinstance(data, list) or not data:
                error = "empty-or-not-a-list"
    except urllib.error.HTTPError as exc:
        status = exc.code
        error = "http-error"
    except ValueError:
        error = "invalid-json"
    except OSError as exc:  # URLError, timeouts y errores de red
        error = type(exc).__name__

    return {
        "check": check["name"],
        "success": error is None,
        "status": status,
        "latency_ms": round((time.monotonic() - started) * 1000, 1),
        "error_type": error,
    }


def publish(results):
    environment = {"Name": "Environment", "Value": ENVIRONMENT}
    metric_data = [
        {
            "MetricName": "AllChecksPassed",
            "Dimensions": [environment],
            "Value": 1 if all(r["success"] for r in results) else 0,
            "Unit": "Count",
        }
    ]
    for result in results:
        dimensions = [environment, {"Name": "Check", "Value": result["check"]}]
        metric_data.append(
            {"MetricName": "Success", "Dimensions": dimensions, "Value": 1 if result["success"] else 0, "Unit": "Count"}
        )
        metric_data.append(
            {"MetricName": "LatencyMs", "Dimensions": dimensions, "Value": result["latency_ms"], "Unit": "Milliseconds"}
        )
    cloudwatch.put_metric_data(Namespace=NAMESPACE, MetricData=metric_data)


def handler(_event, _context):
    results = [run_check(check) for check in CHECKS]
    for result in results:
        level = "info" if result["success"] else "error"
        print(json.dumps({"service": "synthetic", "environment": ENVIRONMENT, "level": level, **result}))
    publish(results)
    return {"environment": ENVIRONMENT, "all_passed": all(r["success"] for r in results), "results": results}
