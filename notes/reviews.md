# Code reviews of the patches

Every change in this repo (the exllamav3 patches, the scripts and the docs) was written by Claude Opus 5.5 and reviewed
by GPT-6.1 Sol (at high effort), round by round, until the reviewer had no open findings on the production path. The
reviews were static reads plus CPU-side checks; GPU validation was run separately on the test machine and is noted where
relevant. Commit hashes below (d6a4353, 70ba2c2, and the branch names) are local work commits, not upstream ones;
file:line references point into those trees. The exceptions are upstream commits kept unchanged under their authors:
turboderp's 96838c9 and Rafa's PR #423.

Where the findings ended up:

- First review (RDNA4 patches): all six items fixed in a review-fixes commit on the old base; in the port to 0662fac
  those fixes are folded into the commits in `patches/features/`.
- Second review (DeltaNet replay): all five items fixed in the replay commit. Abandoned caches hand their pending
  records back on eviction, rewind validates every layer before consuming anything and marks failed commits,
  recording storage uses bounded power-of-two row buckets, the test counts real captured-graph launches, and
  `batched_gdn_replay` checks head counts before using them.
- Batching series: fixed in the series itself (two rounds); the open items are test-only.
- PR #423 (upstream, not ours): the four findings below were fixed upstream (ffd18f5); it ships as an optional
  patch, off by default.
- Port to 9cc3bd1 (the current base), 2026-10-12: the findings of the rebase review and the three reviews below are
  fixed in `patches/features/` (`0013`, `0015`, `0017`, `0018`).

## Review of d6a4353 (RDNA4 patches), 2026-10-06

Static review plus CPU symbolic checks; no GPU runs. A second read-only WMMA audit agreed on 1-2.

1. Risk: the WMMA LDS exchanges (exl3_gemv_multirow_rdna.cu:654, 754, 763, 774) use bare
   `__builtin_amdgcn_wave_barrier()`, which LLVM marks IntrNoMem, so the compiler may reorder LDS
   accesses across it. Use `__syncwarp()` (fence/barrier/fence). No corruption observed.
2. Bug: `EXL3_GEMV_WMMA=1` selects the WMMA kernel on any arch (:1110, :1212); on gfx11 the body
   traps. Gate on runtime gfx12 + wave32.
3. Bug: eager decode (EXL3_BC_ATTN=0 or a BC decline) ignores EXL3_DEC_BLOCK_N/WARPS/STAGES
   (triton_paged.py:1458). Share the override resolution with BC.
4. Bug: EXL3_DEC_STAGES alone is ignored in bc_attn.py:79 (read only when WARPS is set).
5. Risk: EXL3_DEC_BLOCK_H=0 or a non-power-of-two value breaks the launch (triton_paged.py:1364). Validate.
6. Nit: inactive Q4W splits still do the query-selection dots before the inactive-split guard
   (triton_paged.py:1114 vs 1227).

Clean: row masking/clamp m1..8, mgemv indexing, LDS bounds (max 40,960 B), U/tail coverage over 1,152
K/warps/U combos, attention geometry q_len 1-16 x group 1-64, Q4W word indexing, graph re-instantiation.

## Review of 70ba2c2 (graph-captured GDN replay), 2026-10-06

The normal decode path is clean: reduction order, conv window, launch indexing over 64 jobs, graph param patching,
kernel args (2,064 / 1,048 B, under 4 KB). Off the normal path:
1. P2: a cache detached or deleted with unresolved records leaves GDNReplayBuffers.live > 0, so that shape stays eager forever.
2. P2: _pop_replay runs before validation and dispatch; a failure drops the only record, and a retry silently no-ops.
3. P2: per-layer recording buffers accumulate per (bsz, seqlen) shape: up to 4,896 rows/layer vs 128.
4. P3: the test counts configured buffers, not captured-graph launches.
5. P3: gdn.cu:2206 can hit `% 0` before validating head counts.
Sent back to the author for fixes, then re-reviewed (fixed as listed above).

## Review of the batching series (16/32-row WMMA GEMV, graphed MLP to 32 rows, row budget), 2026-10-06

Round 1: the kernel is clean (layouts, partial tiles, LDS barriers, 40/48/32 KiB of LDS). Fixed in the series: the MLP
graph cache was keyed by row count only (a dtype mismatch could write out of bounds; never hit by this model), the
graphed MLP path bypassed LoRA adapters and per-projection controls, the row budget was made soft, DFlash2 row pruning,
and three weak tests (one of them, through `sys.path`, compared a checkout with itself).

Round 2: no production regression; the Qwen3.8 dense target and the DFlash2 draft stay on the fast path. Open, all
test-only: the tests don't check which native extension build was loaded (they import whatever is first on
`PYTHONPATH`); the batch sanity bench could flag shared prompt boilerplate as cross-talk (it didn't fire, and
`bench/bench_batch_sanity.py` now treats that signal as informational unless the topic check also fails); exact
replay determinism on the same path is no longer asserted.

GPU validation: bs1 greedy output identical to the series' base; bs2 and bs4 batched outputs identical to bs1 over 400
tokens; a 120k fill with 4 slots peaks at 16.13 GB; through TabbyAPI, 131-132 tok/s for one request and ~240-245 tok/s
combined for 4 concurrent requests over a common window. Generator-only (no API): 282.8 tok/s at 4 at once.

## Review of upstream PR #423 (DFlash2 rejection sampling), 2026-10-06

Reviewed as rebased onto our RDNA4 series (before the batching series). At that point it wasn't clean, so we didn't use
it and the recipe shipped it off by default.
- P1: speculative verify bypasses job-level token masks (`min_new_tokens`, banned-string retries), so a stop token can
  end generation early (generator.py:1011).
- P2: `probs()` truncates top-k by exact count at ties; the fused sampler keeps every tied token (custom.py:1203).
- P2: the sampled DFlash2 path skips the `draft_conf` export, which disables confidence calibration
  (dflash2.py:286-296).
- P3: extra device-to-host syncs on the hot path.

Correct: the accept/residual/bonus math, the GDN replay accounting, the RNG handling; greedy decoding unaffected. GPU,
on that pre-batching rebase: sampled prose 59.3 -> 62.6 tok/s, acceptance 24% -> 26%; greedy output identical.

The patch has since been rebased onto the batching series with one adaptation (see `patches/README.md`).

Follow-up, 2026-10-07: Rafa fixed all four in ffd18f5, which applied unchanged on top. A job now stays on
match-the-sample verification while `min_new_tokens` or a banned-string checkpoint is active; `probs()` follows the
fused sampler's logit-threshold cutoffs, ties included; no speculative sampling with `dynamic_draft`; the accepted
length stays on the device. On the GPU: the PR's tests pass, `min_tokens = 64` holds, greedy output is unchanged,
sampled prose 52.6 -> 53.2 tok/s (one run per mode, not an established speedup).

## Port to 9cc3bd1, 2026-10-12

Rebase review (on the 10 October snapshot, carried over): P1, upstream's fde1b37 passed `staging_pages` to a function
that doesn't take it (the eager Q4-cache decode raised TypeError; upstream later fixed it the same way in 3a513ac, so
the port drops ours); P2, `test_gemv32.py` didn't show whether graph replay ran (it now prints `EXL3_GRAPHS`); P3,
test and doc cleanups. All fixed in `0013`.

Split-decode stage fallback (`0014`): one P2, pre-existing. The launch pick's cache key didn't include the
single-split (FINAL) variant, whose footprint differs (67,584 vs 65,536 B at the failing shape), so a pick cached by a
16-split call was reused for a 1-split call and the launch ran out of resources. Fixed in `0015` (the key carries FINAL
per candidate, the test runs both orders). Round 2: clean; the graph-captured path never compiles a FINAL kernel, so
it can't hit the same problem.

DeltaNet scan in registers (`0016`): the change itself is correct. Each thread's slice is disjoint, the separate-launch
speculative path still works because every launch flushes its state, there are no private-scratch or VGPR spills on
gfx1201 (including the 64-float array of the 256-wide generic kernel), and the 128-wide GDN, KDA and replay kernels have
the same FMA, multiply and add counts before and after. VGPRs go from 64 to 106 (verify) and 74 to 131 (KDA). Two
findings: P2, pre-existing upstream, the Mamba2 replay launch used a v split with no matching kernel (fixed in `0018`);
P3, the operand comments still described the per-token round trip (fixed in `0017`). Round 2: clean, with a ranked list
of suspects for the open NaN in upstream's spec-rewind e2e test (`notes/research-log.md`).
