# WP-14 completion

## Files changed

- `Backend/migrations/20260827_tme_insight_v2.sql`
- V2 repository adapter.

## Behavior changed

- Added model/image/run/cell/tumor/spatial/TME/artifact tables, indexes, six-state constraint, idempotent cell persistence, and ownership RLS.

## Tests run

- Repository-independent application tests; SQL was reviewed locally.

## Acceptance criteria status

- Migration authored: pass.
- Applied migration and live RLS tests: pending deployment.

## Remaining risks

- Apply to a staging Supabase project and test clinician/patient/admin JWTs before production.

## Intentional deviations

- `output_json` and `metadata_json` snapshots were added for auditable API reconstruction.
