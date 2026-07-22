import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/asymmetric/api.dart';

import '../exceptions.dart';

/// Lanis RSA handshake + AES decrypt for SPH payloads.
class Cryptor {
  static const int passphraseSize = 46;
  late encrypt.Key key;
  bool authenticated = false;
  late Dio dio;

  Future<RSAPublicKey?> getPublicKey() async {
    try {
      final response = await dio.post(
        'https://start.schulportal.hessen.de/ajax.php',
        queryParameters: {'f': 'rsaPublicKey'},
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
          },
        ),
      );

      if (response.statusCode == 503) {
        throw LanisDownException();
      }

      return encrypt.RSAKeyParser().parse(
            jsonDecode(response.toString())['publickey'],
          )
          as RSAPublicKey;
    } on (SocketException, DioException) {
      return null;
    }
  }

  Future<String?> handshake(String encryptedKey) async {
    try {
      final response = await dio.post(
        'https://start.schulportal.hessen.de/ajax.php',
        queryParameters: {'f': 'rsaHandshake', 's': Random().nextInt(2000)},
        data: {'key': encryptedKey},
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
          },
        ),
      );
      return jsonDecode(response.toString())['challenge'];
    } on (SocketException, DioException) {
      return null;
    }
  }

  encrypt.Key generateKey() => encrypt.Key.fromSecureRandom(passphraseSize);

  Uint8List encryptKey(RSAPublicKey publicKey) {
    final rsa = encrypt.RSA(
      publicKey: publicKey,
      encoding: encrypt.RSAEncoding.PKCS1,
    );
    return rsa.encrypt(key.bytes).bytes;
  }

  bool checkForEqualEncryption(Uint8List challenge) {
    final decryptedChallenge = decrypt(challenge);
    return base64.encode(decryptedChallenge!) == base64.encode(key.bytes);
  }

  static Uint8List bytesToKeys(Uint8List salt, encrypt.Key key) {
    Uint8List concatenatedHashes = Uint8List(0);
    Uint8List currentHash = Uint8List(0);
    var enoughBytesForKey = false;
    Uint8List preHash = Uint8List(0);

    while (!enoughBytesForKey) {
      if (currentHash.isNotEmpty) {
        preHash = Uint8List.fromList(currentHash + key.bytes + salt);
      } else {
        preHash = Uint8List.fromList(key.bytes + salt);
      }

      currentHash = md5.convert(preHash).bytes as Uint8List;
      concatenatedHashes = Uint8List.fromList(concatenatedHashes + currentHash);
      if (concatenatedHashes.length >= 48) enoughBytesForKey = true;
    }

    return concatenatedHashes;
  }

  String encryptString(String decryptedData) {
    final salt = encrypt.SecureRandom(8).bytes;
    final derivedKeyAndIV = bytesToKeys(salt, key);
    final derivedKey = encrypt.Key(derivedKeyAndIV.sublist(0, 32));
    final derivedIV = encrypt.IV(derivedKeyAndIV.sublist(32, 48));
    final aes = encrypt.Encrypter(
      encrypt.AES(derivedKey, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    final encryptedData = aes.encrypt(decryptedData, iv: derivedIV).bytes;
    final finalEncrypted = utf8.encode('Salted__') + salt + encryptedData;
    return base64.encode(finalEncrypted);
  }

  static List<int>? decryptWithKey(
    Uint8List encryptedDataWithSalt,
    encrypt.Key key,
  ) {
    final encryptedData = encrypt.Encrypted.fromBase64(
      base64.encode(encryptedDataWithSalt.sublist(16)),
    );

    if ('Salted__' != utf8.decode(encryptedDataWithSalt.sublist(0, 8))) {
      return null;
    }

    final salt = encryptedDataWithSalt.sublist(8, 16);
    final derivedKeyAndIV = bytesToKeys(salt, key);
    final derivedKey = encrypt.Key(derivedKeyAndIV.sublist(0, 32));
    final derivedIV = encrypt.IV(derivedKeyAndIV.sublist(32, 48));
    final aes = encrypt.Encrypter(
      encrypt.AES(derivedKey, mode: encrypt.AESMode.cbc),
    );
    return aes.decryptBytes(encryptedData, iv: derivedIV);
  }

  List<int>? decrypt(Uint8List encryptedDataWithSalt) {
    return decryptWithKey(encryptedDataWithSalt, key);
  }

  static String? decryptWithKeyString(String encryptedData, encrypt.Key key) {
    final decryptedBytes = decryptWithKey(base64.decode(encryptedData), key);
    if (decryptedBytes != null) {
      return utf8.decode(decryptedBytes);
    }
    return null;
  }

  String? decryptString(String encryptedData) {
    return decryptWithKeyString(encryptedData, key);
  }

  String decryptEncodedTags(String htmlString) {
    final exp = RegExp(r'<encoded>(.*?)</encoded>');
    return htmlString.replaceAllMapped(exp, (match) {
      final encodedContent = match.group(1);
      final decryptedContent = decryptString(encodedContent!);
      return decryptedContent ?? '';
    });
  }

  /// Decrypt [encryptedData] on a background isolate using this instance's key.
  Future<String?> decryptStringInIsolate(String encryptedData) {
    final keyBytes = key.bytes;
    return Isolate.run(() {
      final k = encrypt.Key(Uint8List.fromList(keyBytes));
      return decryptWithKeyString(encryptedData, k);
    });
  }

  Future<void> initialize(Dio dioClient) async {
    dio = dioClient;
    key = generateKey();

    final publicKey = await getPublicKey();
    if (publicKey == null) {
      throw NetworkException();
    }

    final encryptedKey = encryptKey(publicKey);
    final challenge = await handshake(base64.encode(encryptedKey));
    if (challenge == null) {
      throw NetworkException();
    }

    final equal = checkForEqualEncryption(base64.decode(challenge));
    if (equal) {
      authenticated = true;
      return;
    }

    throw EncryptionCheckFailedException();
  }
}
