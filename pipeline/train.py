# Copyright 2026 The Tars Authors. Licensed under the Apache License, Version 2.0.
# Portions adapted from Von (https://github.com/wfzyx/von), Copyright 2026 Victor Hugo,
# Apache License 2.0: the optimizer setup (encoder lr x0.5, head lr x2.5, AdamW, weight decay 0.01), gradient clipping and the forward/loss step follow training/train_option_marker.py, whose collator and loss are imported.
# Modified by The Tars Authors: a time-budgeted loop with a clock-based cosine schedule, MPS bf16 autocast, checkpoint selection on validation plus general replay, early stopping and live status for a dashboard.
"""Full fine-tune of Tars (every weight: Von's ModernBERT encoder + scoring head)
on the local GPU (MPS or CUDA), continuing from Von 1.2 or an earlier Tars.

Picks the checkpoint by held-out validation (Tars val + general replay val),
never by the test sets; stops early when validation stops improving, or when
the time budget runs out. The test sets are printed at each check only so
progress can be watched; evaluate.py makes the promote/don't call.

    python pipeline/train.py --minutes 60
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import shutil
import time

import torch

import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from tars.config import BASE_CHECKPOINT as BASE, CHECKPOINT  # noqa: E402
from tars.model import calibration, device, load  # noqa: E402
import tars.model  # noqa: E402,F401  (puts Von on the path)
from common import accuracy, read_jsonl  # noqa: E402
import status  # noqa: E402
from training.train_option_marker import collate_marker_fn, compute_marker_rlcd_loss  # noqa: E402  (Von's)

DATA = os.environ.get("TARS_DATA", os.path.join(HERE, "..", "data"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=float, default=75)
    ap.add_argument("--lr", type=float, default=2e-5, help="encoder gets lr*0.5, head lr*2.5 (as Von's trainer)")
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--grad-accum", type=int, default=2)
    ap.add_argument("--eval-every", type=int, default=200, help="optimizer steps between checks (~10 min)")
    ap.add_argument("--patience", type=int, default=3, help="checks without improvement before stopping")
    ap.add_argument("--max-steps", type=int, default=0, help="stop after N optimizer steps (smoke tests)")
    ap.add_argument("--fp32", action="store_true", help="no bfloat16 autocast (bf16 measured 1.55x faster, same loss)")
    ap.add_argument("--out", default=CHECKPOINT + "-candidate")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--init", default=BASE, help="weights to start from (default: Von 1.2); the baseline is always the base")
    args = ap.parse_args()

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    dev = device()
    run_dir = os.path.join(os.environ.get("TARS_RUNS", os.path.join(HERE, "..", "runs")), time.strftime("%Y%m%d-%H%M%S"))
    os.makedirs(run_dir, exist_ok=True)
    log_f = open(os.path.join(run_dir, "train.log"), "w")

    def log(msg: str) -> None:
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line, flush=True)
        log_f.write(line + "\n")
        log_f.flush()
        if not msg.startswith("epoch "):
            status.log(msg)

    train = read_jsonl(os.path.join(DATA, "train.jsonl"))
    val = read_jsonl(os.path.join(DATA, "val.jsonl"))
    val_replay = read_jsonl(os.path.join(DATA, "val_replay.jsonl"))
    test_style = read_jsonl(os.path.join(DATA, "test_style.jsonl"))
    test_real = read_jsonl(os.path.join(DATA, "test_real.jsonl"))
    for rows in (train, val, val_replay, test_style, test_real):
        for r in rows:
            r.pop("_single", None)

    model, cal = load(BASE, dev)
    independent = bool(cal.get("independent_options", True))
    tok = model.tokenizer
    n_params = sum(p.numel() for p in model.parameters())
    log(f"device {dev}, {n_params/1e6:.0f}M params all trainable, independent_options={independent}")
    log(f"train {len(train):,}  val {len(val):,}  val_replay {len(val_replay)}  "
        f"test_style {len(test_style):,}  test_real {len(test_real)}")

    def check(tag: str) -> dict:
        t0 = time.time()
        m = {
            "val": accuracy(model, val, independent=independent),
            "val_replay": accuracy(model, val_replay, independent=independent),
            "test_style": accuracy(model, test_style, independent=independent),
            "test_real": accuracy(model, test_real, independent=independent),
        }
        m["select"] = 0.8 * m["val"] + 0.2 * m["val_replay"]
        log(f"{tag}: val {m['val']:.1%}  replay {m['val_replay']:.1%}  |  test_style {m['test_style']:.1%}  "
            f"test_real {m['test_real']:.1%}  ({time.time() - t0:.0f}s)")
        model.train()
        return m

    status.update("train", budget_min=args.minutes, step=0, steps_per_sec=None, elapsed_min=0, loss=[], acc=[],
                  checks=[], baseline=None, best=None, stop_reason=None, examples=len(train))
    status.update(message="Scoring today's Von first (the baseline)")
    base = check("baseline")
    if os.path.abspath(args.init) != os.path.abspath(BASE):  # continue from a candidate (e.g. a short replay-heavy follow-up)
        state = torch.load(os.path.join(args.init, "option_marker.pt"), map_location="cpu")
        model.load_state_dict(state, strict=True)
        model.to(dev)
        del state
        log(f"starting from {args.init}")
        check("start point")
    status.update("train", baseline=base)
    status.update(message="Training")
    json.dump({"baseline": base}, open(os.path.join(run_dir, "progress.json"), "w"), indent=1)

    optimizer = torch.optim.AdamW(
        [{"params": model.encoder.parameters(), "lr": args.lr * 0.5},
         {"params": model.scorer.parameters(), "lr": args.lr * 2.5}],
        weight_decay=0.01,
    )
    base_lrs = [g["lr"] for g in optimizer.param_groups]
    budget = args.minutes * 60
    started = time.time()

    def set_lr(step: int) -> None:
        # Warmup 150 steps, then cosine over the time budget (steps/sec is only
        # known once running, so the schedule follows the clock).
        frac = min(1.0, (time.time() - started) / budget)
        scale = min(1.0, (step + 1) / 150) * (0.1 + 0.9 * 0.5 * (1 + math.cos(math.pi * frac)))
        for g, lr in zip(optimizer.param_groups, base_lrs):
            g["lr"] = lr * scale

    best, best_m, bad, step, micro = -1.0, None, 0, 0, 0
    ema = ema_acc = 0.0
    stop_file = os.path.join(os.path.dirname(status.PATH), "STOP")
    if os.path.exists(stop_file):
        os.remove(stop_file)
    history = []
    model.train()
    epoch = 0
    stop_reason = "time budget"
    while True:
        epoch += 1
        random.shuffle(train)
        for i in range(0, len(train), args.batch_size):
            batch = train[i:i + args.batch_size]
            enc = collate_marker_fn(batch, tok, max_length=2048, digit_split=model.digit_split)
            with torch.autocast("mps", dtype=torch.bfloat16, enabled=not args.fp32 and dev.type == "mps"):
                logits = model(input_ids=enc["input_ids"].to(dev), attention_mask=enc["attention_mask"].to(dev),
                               mask_positions=enc["mask_positions"], independent_options=independent)
                logits = [l.float() for l in logits]
                loss, ce, acc = compute_marker_rlcd_loss(logits, enc["labels"].to(dev), brier_weight=0.5,
                                                         soft_targets=enc.get("soft_targets"))
            (loss / args.grad_accum).backward()
            micro += 1
            if micro % args.grad_accum:
                continue
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            set_lr(step)
            optimizer.step()
            optimizer.zero_grad(set_to_none=True)
            step += 1
            ema = loss.item() if step == 1 else 0.9 * ema + 0.1 * loss.item()
            ema_acc = acc if step == 1 else 0.9 * ema_acc + 0.1 * acc
            if step % 5 == 0:
                el = time.time() - started
                d = status.read().get("train", {})
                pts, accs = d.get("loss", []), d.get("acc", [])
                pts.append([step, round(ema, 4)])
                accs.append([step, round(ema_acc, 4)])
                status.update("train", step=step, steps_per_sec=round(step / el, 3), elapsed_min=round(el / 60, 2),
                              epoch=epoch, loss=pts[-600:], acc=accs[-600:],
                              seen=step * args.batch_size * args.grad_accum)
            if step % 25 == 0 or (args.max_steps and step % 5 == 0):
                el = time.time() - started
                log(f"epoch {epoch} step {step} loss {loss.item():.3f} acc {acc:.0%}  "
                    f"{step / el:.2f} steps/s  {el / 60:.1f}/{args.minutes:.0f} min")
            done_time = time.time() - started > budget or os.path.exists(stop_file)
            done_steps = args.max_steps and step >= args.max_steps
            if step % args.eval_every == 0 or done_time or done_steps:
                m = check(f"step {step}")
                m["step"] = step
                m["minutes"] = round((time.time() - started) / 60, 2)
                history.append(m)
                if m["select"] > best:
                    best, best_m, bad = m["select"], m, 0
                    save(model, cal, args.out, m, base, step)
                    log(f"  -> best so far (step {step}), saved")
                else:
                    bad += 1
                status.update("train", checks=history, best=best_m, patience_left=args.patience - bad)
                json.dump({"baseline": base, "history": history, "best": best_m},
                          open(os.path.join(run_dir, "progress.json"), "w"), indent=1)
                if bad >= args.patience:
                    stop_reason = f"no improvement in {args.patience} checks"
                    break
                if done_time or done_steps:
                    stop_reason = "time budget" if done_time else "max steps"
                    break
        else:
            continue
        break
    log(f"stopped ({stop_reason}) after {step} steps, {(time.time() - started) / 60:.1f} min")
    status.update("train", stop_reason=stop_reason)
    if best_m:
        log(f"best checkpoint: step {best_m['step']}  val {best_m['val']:.1%} (base {base['val']:.1%})  "
            f"test_style {best_m['test_style']:.1%} (base {base['test_style']:.1%})  "
            f"test_real {best_m['test_real']:.1%} (base {base['test_real']:.1%})")
    log("next: python pipeline/evaluate.py   (decides whether it's better; nothing is swapped yet)")


def save(model, cal: dict, out: str, m: dict, base: dict, step: int) -> None:
    tmp = out + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    torch.save({k: v.detach().cpu() for k, v in model.state_dict().items()}, os.path.join(tmp, "option_marker.pt"))
    model.encoder.save_pretrained(tmp)
    model.tokenizer.save_pretrained(tmp)
    # Keep 1.2's fitted calibration (temperature/map/priors): fine-tuning on one
    # task doesn't warrant refitting it on JevBench here; evaluate.py reports
    # how well confidences line up on the Tars sets.
    new_cal = dict(cal)
    new_cal.update({"model_id": "tars", "base_model": "von-1.2.0", "training": {
        "kind": "tars fine-tune (full)", "step": step, "val": m["val"], "val_replay": m["val_replay"],
        "baseline": {k: None if base[k] != base[k] else base[k] for k in ("val", "val_replay", "test_style", "test_real")}, "timestamp": time.time()}})
    json.dump(new_cal, open(os.path.join(tmp, "marker_calibration.json"), "w"), indent=1)
    for extra in ("calibration.json", "README.md"):
        src = os.path.join(BASE, extra)
        if os.path.exists(src):
            shutil.copy(src, tmp)
    shutil.rmtree(out, ignore_errors=True)
    os.rename(tmp, out)


if __name__ == "__main__":
    main()
