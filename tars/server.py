"""HTTP service: POST /plan {"said": "..."} → steps with family and skill.

    python -m tars.server --catalog catalogs/example.json --port 8766
"""

from __future__ import annotations

import argparse

import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel

from .catalog import Catalog
from .config import CHECKPOINT
from .planner import Planner


class PlanRequest(BaseModel):
    said: str


def app_for(planner: Planner) -> FastAPI:
    app = FastAPI(title="Tars planner")

    @app.get("/health")
    def health():
        return {"ok": True, "families": list(planner.catalog.families), "skills": len(planner.catalog.skills)}

    @app.post("/plan")
    def plan(req: PlanRequest):
        return planner.plan(req.said)

    return app


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--checkpoint", default=CHECKPOINT)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8766)
    args = ap.parse_args()
    planner = Planner(Catalog.load(args.catalog), args.checkpoint)
    planner.plan("warm up")   # load weights and warm the GPU before serving
    uvicorn.run(app_for(planner), host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
