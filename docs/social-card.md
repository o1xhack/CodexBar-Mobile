---
summary: "Regenerate the website and README social preview when provider counts or artwork change."
read_when:
  - Updating the social preview or provider count
  - Fixing a stale social-card validation failure
---

# Social preview

The website's Open Graph and Twitter preview and the README share `docs/social.png`.
Its editable source is `docs/social.html`; editing that page alone does not update the PNG.

After changing the card, render `docs/social.html` in a browser at a **1200 × 630** viewport
and **1× device scale**, wait for its fonts and images to load, and save the viewport as a PNG.
Use an **8-bit, noninterlaced RGB or RGBA** screenshot under 16 MiB; other PNG encodings are rejected.
Inspect the complete image for the current provider count, readable text, loaded logos, and clipping.
Then, from the repository root, run:

```sh
node Scripts/social-card.mjs --update /absolute/path/to/rendered-social.png
node Scripts/check-site-locales.mjs
node --test Scripts/test_social_card.mjs
```

The updater validates PNG chunks, checksums, and complete pixel data before changing any files.
It copies the PNG, records SHA-256 hashes of the HTML and its local image assets in
`docs/social-card.json`, and uses the PNG hash to update the website and README image cache tokens.
Commit these outputs together. Site checks reject source, asset, image, or cache-token drift.
The receipt records a reviewed render; it does not render the page or prove its visual contents.
Do not refresh it with an old screenshot to bypass a stale-card failure.

Link-preview services may keep an already-fetched page cached. The changed image URL lets a fresh
page scrape fetch the new card; existing previews may require the service's refresh tool.
