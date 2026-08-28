# OPPA

OPPA is a mobile-first African communications platform.

## Repository direction

This repository is the source of truth for OPPA development. Build in small, verified increments.

## Planned system boundaries

- Mobile client: Flutter
- Core API: Node.js + TypeScript
- Database: Supabase PostgreSQL
- Production API: Render
- Edge/security: Cloudflare
- Web surfaces: Vercel
- SMS: replaceable provider adapter

## Engineering rules

- No fake OTP acceptance path in application code.
- External providers remain behind adapters so they can be replaced.
- Security layers and core programs follow the architecture already mapped for OPPA.
- Every milestone is tested before the next milestone is started.
