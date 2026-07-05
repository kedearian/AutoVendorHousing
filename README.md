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

1. Download or clone this repository.
2. Place the `AutoVendorHousing` folder in:
   - `World of Warcraft/_retail_/Interface/AddOns/`
3. Launch or reload WoW.

## Notes

- The addon runs on the `MERCHANT_SHOW` event.
- Unsellable Housing items are destroyed on vendor open by design.

## Files

- `AutoVendorHousing.toc`
- `AutoVendorHousing.lua`

## License

This project is licensed under the GNU General Public License v3.0.

- SPDX identifier: GPL-3.0-only
- Full text: see the LICENSE file in this repository.
