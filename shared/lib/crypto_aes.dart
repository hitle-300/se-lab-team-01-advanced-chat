import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;

const String cSharpLegacyKeyString = r'ClientServerCourseKey2026!#$@^&';
const String cSharpLegacyIvString = 'InitVector123456';
const int fixedAesKeySize = 32;

Uint8List _utf8(String value) => utf8.encode(value);

bool _isValidAesKeySize(List<int> key) {
  return key.length == 16 || key.length == 24 || key.length == 32;
}

String _legacyPassthrough(String input) => input;

class NetworkCrypto {
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return plainText;
    try {
      final key = _utf8(cSharpLegacyKeyString);
      final iv = _utf8(cSharpLegacyIvString);
      if (!_isValidAesKeySize(key)) {
        throw ArgumentError('Specified key is not a valid size for this algorithm');
      }
      final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
      return base64.encode(
        encrypter.encryptBytes(utf8.encode(plainText), iv: enc.IV(iv)).bytes,
      );
    } catch (_) {
      return _legacyPassthrough(plainText);
    }
  }

  static String decrypt(String cipherText) {
    if (cipherText.isEmpty) return cipherText;
    try {
      final key = _utf8(cSharpLegacyKeyString);
      final iv = _utf8(cSharpLegacyIvString);
      if (!_isValidAesKeySize(key)) {
        throw ArgumentError('Specified key is not a valid size for this algorithm');
      }
      final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
      return utf8.decode(
        encrypter.decryptBytes(enc.Encrypted(base64.decode(cipherText)), iv: enc.IV(iv)),
      );
    } catch (_) {
      return _legacyPassthrough(cipherText);
    }
  }

  static String encryptReal(
    String plainText, {
    String key = r'ClientServerCourseKey2026!#$@^&!',
    String iv = cSharpLegacyIvString,
  }) {
    final keyBytes = _utf8(key);
    final ivBytes = _utf8(iv);
    if (!_isValidAesKeySize(keyBytes)) {
      throw ArgumentError('Specified key is not a valid size for this algorithm');
    }
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    final textBytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ..._utf8(plainText)]);
    return base64.encode(
      encrypter.encryptBytes(textBytes, iv: enc.IV(ivBytes)).bytes,
    );
  }

  static String decryptReal(
    String cipherText, {
    String key = r'ClientServerCourseKey2026!#$@^&!',
    String iv = cSharpLegacyIvString,
  }) {
    final keyBytes = _utf8(key);
    final ivBytes = _utf8(iv);
    if (!_isValidAesKeySize(keyBytes)) {
      throw ArgumentError('Specified key is not a valid size for this algorithm');
    }
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    final decrypted = utf8.decode(
      encrypter.decryptBytes(enc.Encrypted(base64.decode(cipherText)), iv: enc.IV(ivBytes)),
    );
    if (decrypted.isNotEmpty && decrypted.codeUnitAt(0) == 0xFEFF) {
      return decrypted.substring(1);
    }
    return decrypted;
  }
}