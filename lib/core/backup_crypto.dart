import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// محرك تشفير محلي موثّق (Pure Dart) لتشفير النسخ الاحتياطية والتحقق من التراخيص
/// يستخدم AES-256-CTR + HMAC-SHA256 + PBKDF2-HMAC-SHA256 بدون أي حزم خارجية إضافية
class BackupCrypto {
  static const List<int> magicHeader = [0x4D, 0x54, 0x52, 0x4B, 0x45, 0x4E, 0x43, 0x31]; // "MTRKENC1"
  static const String defaultBackupSecret = 'MobilyaTrack#2026!SecureBackupKey@ERP';

  /// اشتقاق مفتاح تشفير خاص بكل جهاز للنسخ الاحتياطية السحابية والمحلية
  static String deriveDeviceBackupKey(String deviceCode) {
    final clean = deviceCode.trim().toUpperCase();
    final digest = sha256(Uint8List.fromList(utf8.encode('FurniFlow|BackupKey|$clean|2026')));
    return toHexUpper(digest);
  }
  static const int _saltLen = 16;
  static const int _ivLen = 16;
  static const int _macLen = 32;
  static const int _pbkdf2Iterations = 6000;

  /// التحقق مما إذا كان الملف مشفراً بصيغة FurniFlow
  static bool isEncryptedBytes(Uint8List data) {
    if (data.length < magicHeader.length + _saltLen + _ivLen + _macLen) {
      return false;
    }
    for (int i = 0; i < magicHeader.length; i++) {
      if (data[i] != magicHeader[i]) return false;
    }
    return true;
  }

  /// تشفير مصفوفة بايت (مثل ملف قاعدة بيانات SQLite) مع توقيع HMAC للتحقق من السلامة
  static Uint8List encryptBytes(Uint8List plainBytes, {String? passphrase}) {
    final secret = (passphrase != null && passphrase.trim().isNotEmpty)
        ? passphrase.trim()
        : defaultBackupSecret;

    final rnd = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(_saltLen, (_) => rnd.nextInt(256)));
    final iv = Uint8List.fromList(List<int>.generate(_ivLen, (_) => rnd.nextInt(256)));

    final derived = pbkdf2HmacSha256(
      Uint8List.fromList(utf8.encode(secret)),
      salt,
      _pbkdf2Iterations,
      64,
    );
    final encKey = Uint8List.sublistView(derived, 0, 32);
    final macKey = Uint8List.sublistView(derived, 32, 64);

    final cipherText = _aes256Ctr(plainBytes, encKey, iv);

    final payloadLen = magicHeader.length + _saltLen + _ivLen + cipherText.length;
    final output = Uint8List(payloadLen + _macLen);
    int offset = 0;
    output.setRange(offset, offset + magicHeader.length, magicHeader);
    offset += magicHeader.length;
    output.setRange(offset, offset + _saltLen, salt);
    offset += _saltLen;
    output.setRange(offset, offset + _ivLen, iv);
    offset += _ivLen;
    output.setRange(offset, offset + cipherText.length, cipherText);

    final mac = hmacSha256(macKey, Uint8List.sublistView(output, 0, payloadLen));
    output.setRange(payloadLen, payloadLen + _macLen, mac);
    return output;
  }

  /// فك تشفير ملف نسخة احتياطية بعد التحقق من سلامة التوقيع HMAC
  static Uint8List decryptBytes(Uint8List encryptedBytes, {String? passphrase}) {
    if (!isEncryptedBytes(encryptedBytes)) {
      throw const FormatException('الملف ليس بصيغة النسخة المشفرة الصالحة.');
    }

    final secret = (passphrase != null && passphrase.trim().isNotEmpty)
        ? passphrase.trim()
        : defaultBackupSecret;

    int offset = magicHeader.length;
    final salt = Uint8List.sublistView(encryptedBytes, offset, offset + _saltLen);
    offset += _saltLen;
    final iv = Uint8List.sublistView(encryptedBytes, offset, offset + _ivLen);
    offset += _ivLen;

    final payloadEnd = encryptedBytes.length - _macLen;
    final cipherText = Uint8List.sublistView(encryptedBytes, offset, payloadEnd);
    final storedMac = Uint8List.sublistView(encryptedBytes, payloadEnd);

    final derived = pbkdf2HmacSha256(
      Uint8List.fromList(utf8.encode(secret)),
      salt,
      _pbkdf2Iterations,
      64,
    );
    final encKey = Uint8List.sublistView(derived, 0, 32);
    final macKey = Uint8List.sublistView(derived, 32, 64);

    final expectedMac = hmacSha256(macKey, Uint8List.sublistView(encryptedBytes, 0, payloadEnd));
    if (!constantTimeEquals(storedMac, expectedMac)) {
      throw const FormatException('كلمة مرور فك التشفير غير صحيحة أو الملف تالف.');
    }

    return _aes256Ctr(cipherText, encKey, iv);
  }

  static bool constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// تحويل البايتات إلى نص Hex بحروف كبيرة
  static String toHexUpper(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // SHA-256 (FIPS 180-4)
  // ---------------------------------------------------------------------------
  static const List<int> _sha256K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr32(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;

  static Uint8List sha256(Uint8List data) {
    int h0 = 0x6a09e667;
    int h1 = 0xbb67ae85;
    int h2 = 0x3c6ef372;
    int h3 = 0xa54ff53a;
    int h4 = 0x510e527f;
    int h5 = 0x9b05688c;
    int h6 = 0x1f83d9ab;
    int h7 = 0x5be0cd19;

    final bitLen = data.length * 8;
    final rem = (data.length + 9) % 64;
    final padLen = rem == 0 ? 0 : (64 - rem);
    final padded = Uint8List(data.length + 1 + padLen + 8);
    padded.setRange(0, data.length, data);
    padded[data.length] = 0x80;
    final bd = ByteData.view(padded.buffer);
    bd.setUint32(padded.length - 8, (bitLen ~/ 0x100000000) & 0xFFFFFFFF, Endian.big);
    bd.setUint32(padded.length - 4, bitLen & 0xFFFFFFFF, Endian.big);

    final w = Uint32List(64);
    for (int offset = 0; offset < padded.length; offset += 64) {
      for (int i = 0; i < 16; i++) {
        w[i] = bd.getUint32(offset + i * 4, Endian.big);
      }
      for (int i = 16; i < 64; i++) {
        final s0 = _rotr32(w[i - 15], 7) ^ _rotr32(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr32(w[i - 2], 17) ^ _rotr32(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
      }

      int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (int i = 0; i < 64; i++) {
        final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final temp1 = (h + s1 + ch + _sha256K[i] + w[i]) & 0xFFFFFFFF;
        final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h0 = (h0 + a) & 0xFFFFFFFF;
      h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF;
      h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF;
      h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF;
      h7 = (h7 + h) & 0xFFFFFFFF;
    }

    final out = Uint8List(32);
    final outBd = ByteData.view(out.buffer);
    outBd.setUint32(0, h0, Endian.big);
    outBd.setUint32(4, h1, Endian.big);
    outBd.setUint32(8, h2, Endian.big);
    outBd.setUint32(12, h3, Endian.big);
    outBd.setUint32(16, h4, Endian.big);
    outBd.setUint32(20, h5, Endian.big);
    outBd.setUint32(24, h6, Endian.big);
    outBd.setUint32(28, h7, Endian.big);
    return out;
  }

  static Uint8List hmacSha256(Uint8List key, Uint8List message) {
    const blockSize = 64;
    Uint8List k = key.length > blockSize ? sha256(key) : Uint8List.fromList(key);
    final keyBlock = Uint8List(blockSize);
    keyBlock.setRange(0, k.length, k);

    final inner = Uint8List(blockSize + message.length);
    final outer = Uint8List(blockSize + 32);
    for (int i = 0; i < blockSize; i++) {
      inner[i] = keyBlock[i] ^ 0x36;
      outer[i] = keyBlock[i] ^ 0x5c;
    }
    inner.setRange(blockSize, inner.length, message);
    final innerHash = sha256(inner);
    outer.setRange(blockSize, outer.length, innerHash);
    return sha256(outer);
  }

  static Uint8List pbkdf2HmacSha256(
    Uint8List password,
    Uint8List salt,
    int iterations,
    int dkLen,
  ) {
    final blocks = (dkLen + 31) ~/ 32;
    final out = Uint8List(blocks * 32);
    final saltBlock = Uint8List(salt.length + 4);
    saltBlock.setRange(0, salt.length, salt);
    final sbBd = ByteData.view(saltBlock.buffer);

    for (int b = 1; b <= blocks; b++) {
      sbBd.setUint32(salt.length, b, Endian.big);
      Uint8List u = hmacSha256(password, saltBlock);
      final t = Uint8List.fromList(u);
      for (int i = 1; i < iterations; i++) {
        u = hmacSha256(password, u);
        for (int j = 0; j < 32; j++) {
          t[j] ^= u[j];
        }
      }
      out.setRange((b - 1) * 32, b * 32, t);
    }
    return Uint8List.sublistView(out, 0, dkLen);
  }

  // ---------------------------------------------------------------------------
  // AES-256-CTR (FIPS 197)
  // ---------------------------------------------------------------------------
  static const List<int> _sBox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];

  static const List<int> _rCon = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

  static int _xTime(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1b : 0)) & 0xFF;

  static Uint8List _expandKey256(Uint8List key) {
    // 14 rounds -> 15 round keys * 16 bytes = 240 bytes
    final expanded = Uint8List(240);
    expanded.setRange(0, 32, key);
    int bytesGen = 32;
    int rconIdx = 1;
    final temp = Uint8List(4);

    while (bytesGen < 240) {
      for (int i = 0; i < 4; i++) {
        temp[i] = expanded[bytesGen - 4 + i];
      }
      if (bytesGen % 32 == 0) {
        final t = temp[0];
        temp[0] = _sBox[temp[1]] ^ _rCon[rconIdx++];
        temp[1] = _sBox[temp[2]];
        temp[2] = _sBox[temp[3]];
        temp[3] = _sBox[t];
      } else if (bytesGen % 32 == 16) {
        for (int i = 0; i < 4; i++) {
          temp[i] = _sBox[temp[i]];
        }
      }
      for (int i = 0; i < 4; i++) {
        expanded[bytesGen] = expanded[bytesGen - 32] ^ temp[i];
        bytesGen++;
      }
    }
    return expanded;
  }

  static void _aesEncryptBlock(Uint8List input, Uint8List output, Uint8List roundKeys) {
    final s = Uint8List.fromList(input);
    for (int i = 0; i < 16; i++) {
      s[i] ^= roundKeys[i];
    }

    for (int round = 1; round <= 14; round++) {
      // SubBytes
      for (int i = 0; i < 16; i++) {
        s[i] = _sBox[s[i]];
      }
      // ShiftRows
      int t = s[1];
      s[1] = s[5];
      s[5] = s[9];
      s[9] = s[13];
      s[13] = t;

      t = s[2];
      s[2] = s[10];
      s[10] = t;
      t = s[6];
      s[6] = s[14];
      s[14] = t;

      t = s[15];
      s[15] = s[11];
      s[11] = s[7];
      s[7] = s[3];
      s[3] = t;

      // MixColumns (except final round)
      if (round < 14) {
        for (int c = 0; c < 4; c++) {
          final i = c * 4;
          final a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
          final x = a0 ^ a1 ^ a2 ^ a3;
          s[i] ^= x ^ _xTime(a0 ^ a1);
          s[i + 1] ^= x ^ _xTime(a1 ^ a2);
          s[i + 2] ^= x ^ _xTime(a2 ^ a3);
          s[i + 3] ^= x ^ _xTime(a3 ^ a0);
        }
      }

      // AddRoundKey
      final rkOffset = round * 16;
      for (int i = 0; i < 16; i++) {
        s[i] ^= roundKeys[rkOffset + i];
      }
    }

    output.setRange(0, 16, s);
  }

  static Uint8List _aes256Ctr(Uint8List input, Uint8List key, Uint8List iv) {
    final roundKeys = _expandKey256(key);
    final output = Uint8List(input.length);
    final counter = Uint8List.fromList(iv);
    final keystream = Uint8List(16);

    for (int offset = 0; offset < input.length; offset += 16) {
      _aesEncryptBlock(counter, keystream, roundKeys);
      final blockLen = (input.length - offset) < 16 ? (input.length - offset) : 16;
      for (int i = 0; i < blockLen; i++) {
        output[offset + i] = input[offset + i] ^ keystream[i];
      }
      // Increment 128-bit big-endian counter
      for (int i = 15; i >= 0; i--) {
        counter[i] = (counter[i] + 1) & 0xFF;
        if (counter[i] != 0) break;
      }
    }
    return output;
  }
}
