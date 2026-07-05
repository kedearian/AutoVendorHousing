# AutoVendorHousing

A World of Warcraft Retail addon that automatically processes Housing items when you open a merchant.

## What it does

- Scans all equipped bags when a merchant window opens.
- Detects Housing items (including modern Housing class support and legacy fallback mapping).
- Sells sellable Housing items automatically.
- Destroys unsellable Housing items automatically.
- Prints a one-line summary of how many Housing items were sold and total value.

## Requirements

- World of Warcraft Retail
- Interface version: 12.0.7 (`120007`)

## Installation

1. Install from Wago:
   - https://addons.wago.io/addons/autovendorhousing
2. Or install manually by downloading or cloning this repository.
3. Place the `AutoVendorHousing` folder in:
   - `World of Warcraft/_retail_/Interface/AddOns/`
4. Launch or reload WoW.

## Notes

- The addon runs on the `MERCHANT_SHOW` event.
- Unsellable Housing items are destroyed on vendor open by design.

## Files

- `AutoVendorHousing.toc`
- `AutoVendorHousing.lua`

## Release Automation

This repository is configured for the BigWigs packager with a GitHub Actions workflow at `.github/workflows/release.yml`.

### Required GitHub configuration

Set these repository settings before creating a release tag:

- Repository secret: `WAGO_API_TOKEN`

The Wago project ID is stored in [AutoVendorHousing.toc](AutoVendorHousing.toc) as `## X-Wago-ID: j6jmDMNR`. The workflow uses the built-in `GITHUB_TOKEN` automatically for GitHub releases.

### Creating a release

1. Commit your changes to `main`.
2. Create and push a version tag such as `v1.0.1`.
3. GitHub Actions will build the addon zip, create or update the GitHub release, and upload the package to Wago.

Example:

```bash
git tag -a v1.0.1 -m "v1.0.1"
git push origin v1.0.1
```

The packaged addon version comes from the Git tag through BigWigs packager substitution in `AutoVendorHousing.toc`.

## License

This project is licensed under the GNU General Public License v3.0.

- SPDX identifier: GPL-3.0-only
- Full text: see the LICENSE file in this repository.
