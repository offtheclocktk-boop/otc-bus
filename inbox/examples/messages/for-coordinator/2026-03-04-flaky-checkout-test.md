## Need
Decide whether to quarantine the flaky `checkout_applies_coupon` test in the `webshop` repo, and if so, open the quarantine PR there.

## Context
- The test fails about 1 run in 8 on CI and never locally. The failures started after the payment client was upgraded to 3.2.
- I traced it to a race: the coupon service stub sometimes answers after the test's 200 ms wait. Raising the wait to 1 s made 40 consecutive CI runs pass on my branch.
- The board lists `webshop` CI as yours, so I have not pushed anything to `main`.

## Paths
- Test: `webshop/tests/checkout/test_coupons.py::checkout_applies_coupon`
- My experiment branch: `webshop@fix/coupon-stub-timeout` (one commit, not for merge as-is)
- CI runs with the failure: linked in the PR description

## Done when
- Either the test is quarantined with a tracking issue, or the timeout fix is merged, and CI on `main` is green for 10 consecutive runs.
- You reply here with which option you chose and why.

## Evidence
- 40/40 green CI runs on `fix/coupon-stub-timeout`.
- Not tested against the real coupon service; stub only.
