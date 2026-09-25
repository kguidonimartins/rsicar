# Offline CAPTCHA fixtures

`upstream/` contains six CAPTCHA images copied from the pinned Python SICAR
reference at commit `facffbf91a4998a2daa814a65d1d36ea99266f83`,
`tests/integration/captchas/`. The upstream project is by Gilson Urbano and
is distributed under the MIT license; see the accompanying `LICENSE`. Filenames are
the expected case-sensitive answers.

`current/` contains three public SICAR CAPTCHA images fetched on 2026-09-25.
Their answers were transcribed visually and are encoded in the filenames.
They were not checked by submitting answers to the service. No cookies or
service responses other than these PNGs are included.

These fixtures catch regressions. Nine images are too few to estimate the
solver's success rate on future CAPTCHAs, and OCR output may vary by
Tesseract version or trained data.

`manifest.csv` marks all nine images as development data, since they have
already been used to adjust the solver. Seven solved cases are protected in
the opt-in regression check (`make ocr-regression`); failures on the other two
do not prevent future improvements. The default suite tests deterministic
selection and diagnostic behavior. See `tools/TESSERACT.md` in the repository
for separate tuning and evaluation workflows.
