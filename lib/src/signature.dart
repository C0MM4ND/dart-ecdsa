import 'package:elliptic/elliptic.dart';
import 'package:ninja_asn1/ninja_asn1.dart';
import 'dart:math';

import 'utils.dart';

class ErrInvalidCurve implements Exception {}

class Signature {
  late BigInt R;
  late BigInt S;

  Signature.fromRS(this.R, this.S);

  Signature.fromASN1(List<int> asn1Bytes) {
    var p = ASN1Sequence.decode(asn1Bytes);
    R = (p.children[0] as ASN1Integer).value;
    S = (p.children[1] as ASN1Integer).value;
  }

  Signature.fromASN1Hex(String asn1Hex) {
    var asn1Bytes = List<int>.generate(asn1Hex.length ~/ 2,
        (i) => int.parse(asn1Hex.substring(i * 2, i * 2 + 2), radix: 16));
    var p = ASN1Sequence.decode(asn1Bytes);
    R = (p.children[0] as ASN1Integer).value;
    S = (p.children[1] as ASN1Integer).value;
  }

  List<int> toASN1() {
    return ASN1Sequence([ASN1Integer(R), ASN1Integer(S)]).encode();
  }

  String toASN1Hex() {
    var asn1 = toASN1();
    return List<String>.generate(
        asn1.length, (i) => asn1[i].toRadixString(16).padLeft(2, '0')).join();
  }
}

/// [signature] signs a hash (which should be the result of hashing a larger message)
/// using the private key, priv. If the hash is longer than the bit-length of the
/// private key's curve order, the hash will be truncated to that length. It
/// returns the signature as a pair of integers.
Signature signature(PrivateKey priv, List<int> hash) {
  var curve = priv.curve;

  var sig = Signature.fromRS(BigInt.zero, BigInt.zero);
  if (curve.n.sign == 0) {
    throw ErrInvalidCurve;
  }

  var random = Random.secure();
  late List<int> rand;
  var byteLen = curve.bitSize ~/ 8 + 8;

  late BigInt k, kInv;
  while (true) {
    while (true) {
      rand =
          List<int>.generate(byteLen, (i) => random.nextInt(256)); // bytes of k
      k = BigInt.parse(
          List<String>.generate(
              byteLen, (i) => rand[i].toRadixString(16).padLeft(2, '0')).join(),
          radix: 16);

      kInv = k.modInverse(curve.n);

      sig.R = priv.curve.scalarBaseMul(rand).X;
      sig.R = sig.R % curve.n;
      if (sig.R.sign != 0) {
        // valid r
        break;
      }
    }

    var e = hashToInt(hash, curve);
    sig.S = priv.D * sig.R;
    sig.S = sig.S + e;
    sig.S = sig.S * kInv;
    sig.S = sig.S % curve.n; // N != 0
    if (sig.S.sign != 0) {
      break;
    }
  }

  return sig;
}

/// [verify] verifies the signature in r, s of hash using the public key, pub.
/// Its return value records whether the signature is valid.
bool verify(PublicKey pub, List<int> hash, Signature sig) {
  // See [NSA] 3.4.2
  var curve = pub.curve;
  var byteLen = (curve.bitSize + 7) ~/ 8;

  if (sig.R.sign <= 0 || sig.S.sign <= 0) {
    return false;
  }

  if (sig.R >= curve.n || sig.S >= curve.n) {
    return false;
  }

  var e = hashToInt(hash, curve);
  var w = sig.S.modInverse(curve.n);

  var u1 = e * w;
  u1 = u1 % curve.n;
  var u2 = sig.R * w;
  u2 = u2 % curve.n;

  // Check if implements S1*g + S2*p
  var hexU1 = u1.toRadixString(16).padLeft(byteLen * 2, '0');
  var hexU2 = u2.toRadixString(16).padLeft(byteLen * 2, '0');
  var p1 = curve.scalarBaseMul(List<int>.generate(hexU1.length ~/ 2,
      (i) => int.parse(hexU1.substring(i * 2, i * 2 + 2), radix: 16)));
  var p2 = curve.scalarMul(
      pub,
      List<int>.generate(hexU2.length ~/ 2,
          (i) => int.parse(hexU2.substring(i * 2, i * 2 + 2), radix: 16)));
  var p = curve.add(p1, p2);

  if (p.X.sign == 0 && p.Y.sign == 0) {
    return false;
  }

  p.X = p.X % curve.n;
  return p.X == sig.R;
}
