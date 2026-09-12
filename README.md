# AutoVendorHousing

A World of Warcraft Retail addon that automatically processes Housing items when you open a merchant.

Available on Wago and CurseForge.

## What it does

- Scans all equipped bags when a merchant window opens.
- Detects Housing items by their item class (`Enum.ItemClass.Housing`), covering every Housing subclass.
- Sells sellable Housing items automatically, one every 0.2 seconds so the server does not drop sales.
- Adds a `Destroy Housing (N)` button below the merchant window for Housing items that have no sell value. Each click destroys one item, because the game only allows one item deletion per click.
- Prints a one-line summary of how many Housing items were actually sold and the total value once the server confirms the sales.

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
- Unsellable Housing items are never destroyed automatically. Blizzard requires a real click or key press for each item deletion, so use the `Destroy Housing (N)` button on the merchant window once per item.
- Housing items that are still within their vendor refund window are skipped and reported, so no refund confirmation popups appear. They are sold on a later visit once the window has ended.
- If the vendor does not buy items, the addon stops and reports it instead of claiming a sale.
- If merchant interaction starts during combat, processing is deferred until combat ends (while merchant remains open).

## Files

- `AutoVendorHousing.toc`
- `AutoVendorHousing.lua`

The packaged addon version comes from the Git tag through BigWigs packager substitution in `AutoVendorHousing.toc`.

## License

This project is licensed under the GNU General Public License v3.0.

- SPDX identifier: GPL-3.0-only
- All files in `assets/` are original works by the project author and are licensed under GPL-3.0-only.
- Full text: see the LICENSE file in this repository.