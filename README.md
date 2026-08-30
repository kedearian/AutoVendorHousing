# AutoVendorHousing

A World of Warcraft Retail addon that automatically processes Housing items when you open a merchant.

Available on Wago and CurseForge.

## What it does

- Scans all equipped bags when a merchant window opens.
- Detects Housing items (including modern Housing class support and legacy fallback mapping).
- Sells sellable Housing items automatically.
- Destroys unsellable Housing items automatically.
- Prints a one-line summary of how many Housing items were sold and total value.

## Requirements

- World of Warcraft Retail
- Interface version: 12.1 (`120100`)

## Installation

1. Install from Wago:
   - https://addons.wago.io/addons/autovendorhousing
2. Install from CurseForge:
   - https://www.curseforge.com/wow/addons/autovendorhousing
3. Or install manually by downloading or cloning this repository.
4. Place the `AutoVendorHousing` folder in:
   - `World of Warcraft/_retail_/Interface/AddOns/`
5. Launch or reload WoW.

## Notes

- The addon runs on the `MERCHANT_SHOW` event.
- Unsellable Housing items are destroyed on vendor open by design.
- If item value data is not cached yet, the addon skips destruction for safety and reports the skipped item.
- If merchant interaction starts during combat, processing is deferred until combat ends (while merchant remains open).

## Files

- `AutoVendorHousing.toc`
- `AutoVendorHousing.lua`

The packaged addon version comes from the Git tag through BigWigs packager substitution in `AutoVendorHousing.toc`.

## License

This project is licensed under the GNU General Public License v3.0.

- SPDX identifier: GPL-3.0-only
- Full text: see the LICENSE file in this repository.