# Future work

The completed version establishes purchasing analysis and validated data preparation. Extensions should preserve those checks and add measurable acceptance criteria.

1. **Campaign and redemption reporting.** Model household campaign recipients, campaign descriptions, coupon-product eligibility and redemption events at their own grains. Define distinct eligible-recipient and redeemer counts before calculating rates. Acceptance: documented denominators, reconciled counts and no sales duplication from many-to-many joins.
2. **Campaign impact.** After descriptive campaign reporting, use a defensible comparison group or experimental design. Purchases have no direct campaign ID; date overlap is not proof of attribution. Acceptance: explicit exposure rules, comparable groups and uncertainty reporting.
3. **Incremental loading.** Replace full fact refreshes with tested change handling when new batches become available. Acceptance: reruns do not duplicate facts, failures recover correctly and audit totals reconcile.
4. **Historical dimension versions.** Add Type 2 history only when dated attribute changes are available and historical analysis needs them. Acceptance: purchases resolve to the appropriate version at the transaction date.
5. **Automated quality regression checks.** Turn existing SQL checks into a repeatable test workflow, including intentionally invalid fixtures and rollback verification. Acceptance: known defects are detected before published results change.
6. **Dashboard refinements.** Add complete-period comparisons, clearer missing-category labels and measures that explain selected-department basket value. Acceptance: filter behaviour, totals and labels remain consistent.
7. **Forecasting or customer segmentation.** Treat these as separate future analytical projects with suitable validation and documented assumptions. No AI model is implemented in the current version.
