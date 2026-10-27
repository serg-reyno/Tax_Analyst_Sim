# Query relocation map

| Original block | Destination |
|---|---|
| 01: table definitions | sql/01_define_schema.sql |
| 02: all quality checks | sql/02_data_quality_controls.sql |
| 03: lines 1-28 | sql/03_transaction_cost_basis_reconciliation.sql |
| 03: lines 29-48 | sql/99_investigation_notes.sql |
| 03: lines 80-92 | sql/99_investigation_notes.sql |
| 03: lines 93-105 | sql/99_investigation_notes.sql |
| 03: lines 106-129 | sql/99_investigation_notes.sql |
| 03: lines 130-148 | sql/03_transaction_cost_basis_reconciliation.sql |
| 03: lines 149-162 | sql/03_transaction_cost_basis_reconciliation.sql |
| 03: lines 163-207 | sql/99_investigation_notes.sql |
| 03: lines 208-225 | sql/03_transaction_cost_basis_reconciliation.sql |
| 03: lines 226-241 | sql/99_investigation_notes.sql |
| 03: lines 242-266 | sql/99_investigation_notes.sql |
| 03: lines 267-284 | sql/99_investigation_notes.sql |
| 03: lines 285-295 | sql/06_exception_analysis.sql |
| 03: lines 296-307 | sql/06_exception_analysis.sql |
| 03: lines 308-319 | sql/06_exception_analysis.sql |
| 03: lines 320-330 | sql/06_exception_analysis.sql |
| 03: lines 331-341 | sql/06_exception_analysis.sql |
| 03: lines 342-352 | sql/06_exception_analysis.sql |
| 03: lines 353-367 | sql/06_exception_analysis.sql |
| 03: lines 368-383 | sql/06_exception_analysis.sql |
| 03: lines 384-398 | sql/03_transaction_cost_basis_reconciliation.sql |
| 03: lines 399-418 | sql/06_exception_analysis.sql |
| 03: lines 419-428 | sql/06_exception_analysis.sql |
| 03: lines 429-438 | sql/06_exception_analysis.sql |
| 03: lines 439-451 | sql/06_exception_analysis.sql |
| 04: lines 1-22 | sql/04_tax_reporting_reconciliation.sql |
| 04: lines 23-44 | sql/04_tax_reporting_reconciliation.sql |
| 04: lines 45-50 | sql/06_exception_analysis.sql |
| 04: lines 51-88 | sql/06_exception_analysis.sql |
| 04: lines 89-117 | sql/06_exception_analysis.sql |
| 04: lines 118-135 | sql/99_investigation_notes.sql |
| 04: lines 136-158 | sql/99_investigation_notes.sql |
| 04: lines 159-175 | sql/99_investigation_notes.sql |
| 04: lines 176-192 | sql/99_investigation_notes.sql |
| 04: lines 193-207 | sql/99_investigation_notes.sql |
| 04: lines 208-225 | sql/99_investigation_notes.sql |
| 04: lines 226-248 | sql/99_investigation_notes.sql |
| 04: lines 249-265 | sql/99_investigation_notes.sql |
| 04: lines 266-287 | sql/05_withholding_reconciliation.sql |
| 04: lines 288-311 | sql/05_withholding_reconciliation.sql |
| 04: lines 312-327 | sql/06_exception_analysis.sql |
| 04: lines 328-342 | sql/06_exception_analysis.sql |
| 04: lines 343-393 | sql/05_withholding_reconciliation.sql |
| 04: lines 394-405 | sql/05_withholding_reconciliation.sql |
| 04: lines 406-418 | sql/05_withholding_reconciliation.sql |
| 04: lines 419-435 | sql/05_withholding_reconciliation.sql |
| 04: lines 436-479 | sql/05_withholding_reconciliation.sql |
| 04: lines 480-492 | sql/05_withholding_reconciliation.sql |
| 04: lines 493-539 | sql/05_withholding_reconciliation.sql |
| 04: lines 540-569 | sql/99_investigation_notes.sql |
| 04: lines 570-599 | sql/99_investigation_notes.sql |
| 04: lines 600-623 | sql/99_investigation_notes.sql |
| 04: lines 624-641 | sql/99_investigation_notes.sql |
| 04: lines 642-660 | sql/99_investigation_notes.sql |
| 04: lines 661-683 | sql/05_withholding_reconciliation.sql |

Removed: duplicated basis-record uniqueness query from original File 03 (already in File 02), repeated TXN00000034 investigation, and schema sample preview.
