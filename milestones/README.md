# Archivist — Milestones

This directory holds the learning roadmap for building Archivist.

## How the roadmap is organized

The project is split into **stages**. Each stage is a coherent body of learning plus concrete progress on the database. Stages are sequential — finish one before starting the next.

Each stage is broken into **lessons**. Each lesson is sized for a focused evening (1.5–3 hours) and has:

- A **learning goal** — one concept to internalize
- A **delivery goal** — a concrete piece of Archivist shipped
- A **verification step** — code that proves the lesson is done

## Stages

- [Stage 1 — A typed event store on SQLite](stage-1/README.md) ← current focus
- **Stage 2** — Custom append-only storage engine with WAL (designed once Stage 1 is complete)
- **Stage 3** — Performance, query layer, wire protocol (further out)

## How to use a lesson

1. Open the lesson's `README.md`.
2. Work through it in order: learning goal → warm-up → build → verify.
3. When verification passes, you're done. Move on.

Take notes inside the lesson directory — create a `notes.md` or whatever you like. Each lesson directory is yours to grow.

## The bigger picture

See [project_context.md](../project_context.md) at the repo root for the project vision and the design decisions already made.
