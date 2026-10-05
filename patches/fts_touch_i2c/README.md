# fts_touch_i2c Binary Patch

Fixes screen-off UDFPS and Double Tap to Wake (DT2W) lockups on beryl (Redmi Note 14 5G).

## Problem

Under stock FocalTech 6.12 driver behavior:
1. When virtual proximity mode is set upon suspend, the driver takes an early return, skipping `fts_gesture_suspend`. Register `0xD0` remains unset, causing subsequent touches to be dropped with `gesture not enable in fw, don't process gesture`.
2. When userspace fingerprint authentication completes or cancels (`fod_status = 0`), the driver clears bit 1 of register `0xCF`, disarming screen-off UDFPS.
3. If DT2W is disabled while `fod_status = 0`, `gesture_support` evaluates to 0, powering off the touch IC into deep sleep and disabling IRQs.
4. When suspended, `fts_read_and_report_foddata` drops touch-down events if `fod_status == 0`.

## Patched Sites

| Site | File offset | Original | Patched | Description |
|---|---|---|---|---|
| P1 | `0x0000cfc8` | `e1 00 00 54` (`b.ne 0x800cfe4`) | `07 00 00 14` (`b 0x800cfe4`) | Bypasses proximity suspend abort; guarantees gesture suspend execution |
| P2 | `0x0000d008` | `68 00 00 37` (`tbnz w8, 0, 0x800d014`) | `03 00 00 14` (`b 0x800d014`) | Forces `gesture_support = 1` on suspend to keep IRQs active |
| P3 | `0x0000d02c` | `0c 01 00 54` (`b.gt 0x800d04c`) | `08 00 00 14` (`b 0x800d04c`) | Always arms register `0xCF` (FOD) and `0xD0` (DT2W) on suspend |
| P4 | `0x0000c58c` | `89 0f 00 34` (`cbz w9, 0x800c5b4`) | `1f 20 03 d5` (`nop`) | Never drops suspended touch-down when `fod_status == 0` |

## Reverting

To revert to the stock module:
```bash
cp device/xiaomi/beryl-kernel/modules_dlkm/fts_touch_i2c.ko.orig device/xiaomi/beryl-kernel/modules_dlkm/fts_touch_i2c.ko
cp device/xiaomi/beryl-kernel/modules_ramdisk/fts_touch_i2c.ko.orig device/xiaomi/beryl-kernel/modules_ramdisk/fts_touch_i2c.ko
```
