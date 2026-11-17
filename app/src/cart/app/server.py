import os

import uvicorn

from app.logging_config import configure_logging

configure_logging()
uvicorn.run("app.main:app", host="0.0.0.0", port=int(os.environ.get("PORT", "8080")), log_config=None, access_log=False)
