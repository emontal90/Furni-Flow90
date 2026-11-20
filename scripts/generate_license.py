#!/usr/bin/env python3
"""
مولّد أكواد التفعيل التجاري لبرنامج فورني فلو (FurniFlow)
الاستخدام:
  python scripts/generate_license.py MT-XXXX-XXXX-XXXX            # ترخيص دائم (PERM)
  python scripts/generate_license.py MT-XXXX-XXXX-XXXX 20271231   # ترخيص حتى تاريخ محدد
"""
import hashlib
import hmac
import sys

SIGNING_SECRET = "MobilyaTrack#CommercialLicense#2026!Secret"


def generate_license(device_code: str, expiry_token: str = "PERM") -> str:
    clean_device = device_code.strip().upper()
    clean_expiry = expiry_token.strip().upper()
    payload = f"{clean_device}|{clean_expiry}".encode("utf-8")
    sig = hmac.new(SIGNING_SECRET.encode("utf-8"), payload, hashlib.sha256).hexdigest()[:8].upper()
    return f"MTK-{clean_expiry}-{sig}"


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/generate_license.py <DEVICE_CODE> [PERM | YYYYMMDD]")
        sys.exit(1)

    device_code = sys.argv[1]
    expiry = sys.argv[2] if len(sys.argv) >= 3 else "PERM"
    key = generate_license(device_code, expiry)
    print("========================================")
    print("  FurniFlow Commercial License Key")
    print("========================================")
    print(f"Device Code : {device_code.strip().upper()}")
    print(f"Validity    : {'Permanent (Lifetime)' if expiry.upper() == 'PERM' else expiry}")
    print(f"License Key : {key}")
    print("========================================")


if __name__ == "__main__":
    main()
