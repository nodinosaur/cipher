// Copyright (c) 2013-present, Iván Zaera Avellón - izaera@gmail.com

// This library is dually licensed under LGPL 3 and MPL 2.0. See file LICENSE for more information.

// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of
// the MPL was not distributed with this file, you can obtain one at http://mozilla.org/MPL/2.0/.

library cipher.asymmetric.pkcs1;

import "dart:typed_data";

import "package:cipher/api.dart";
import "package:cipher/params/asymmetric_key_parameter.dart";
import "package:cipher/params/parameters_with_random.dart";
import "package:cipher/asymmetric/base_asymmetric_block_cipher.dart";

class PKCS1Encoding extends BaseAsymmetricBlockCipher {

  static const _HEADER_LENGTH = 10;

  final AsymmetricBlockCipher _engine;

  SecureRandom _random;
  bool _forEncryption;
  bool _forPrivateKey;

  PKCS1Encoding(this._engine);

  String get algorithmName => "${_engine.algorithmName}/PKCS1";

  void reset() {
  }

  void init(bool forEncryption, CipherParameters params) {
    AsymmetricKeyParameter akparams;

    if (params is ParametersWithRandom) {
      ParametersWithRandom paramswr = params;

      _random = paramswr.random;
      akparams = paramswr.parameters;
    } else {
      _random = new SecureRandom();
      akparams = params;
    }

    _engine.init(forEncryption, akparams);

    _forPrivateKey = (akparams.key is PrivateKey);
    _forEncryption = forEncryption;
  }

  int get inputBlockSize {
    var baseBlockSize = _engine.inputBlockSize;

    if (_forEncryption) {
      return baseBlockSize - _HEADER_LENGTH;
    } else {
      return baseBlockSize;
    }
  }

  int get outputBlockSize {
    var baseBlockSize = _engine.outputBlockSize;

    if (_forEncryption) {
      return baseBlockSize;
    } else {
      return baseBlockSize - _HEADER_LENGTH;
    }
  }

  int processBlock(Uint8List inp, int inpOff, int len, Uint8List out, int outOff) {
    if (_forEncryption) {
      return _encodeBlock(inp, inpOff, len, out, outOff);
    } else {
      return _decodeBlock(inp, inpOff, len, out, outOff);
    }
  }

  int _encodeBlock(Uint8List inp, int inpOff, int inpLen, Uint8List out, int outOff) {
    if (inpLen > inputBlockSize) {
      throw new ArgumentError("Input data too large");
    }

    var block = new Uint8List(_engine.inputBlockSize);
    var padLength = (block.length - inpLen - 1);

    if (_forPrivateKey) {
      block[0] = 0x01;                        // type code 1
      block.fillRange(1, padLength, 0xFF);
    } else {
      block[0] = 0x02;                        // type code 2
      block.setRange(1, padLength, _random.nextBytes(padLength-1));

      // a zero byte marks the end of the padding, so all
      // the pad bytes must be non-zero.
      for (var i = 1; i < padLength; i++) {
        while (block[i] == 0) {
          block[i] = _random.nextUint8();
        }
      }
    }

    block[padLength] = 0x00; // mark the end of the padding
    block.setRange(padLength+1, block.length, inp.sublist(inpOff));

    return _engine.processBlock(block, 0, block.length, out, outOff);
  }

  int _decodeBlock(Uint8List inp, int inpOff, int inpLen, Uint8List out, int outOff) {
    var block = new Uint8List(_engine.inputBlockSize);
    var len = _engine.processBlock(inp, inpOff, inpLen, block, 0);
    block = block.sublist(0, len);

    if (block.length < outputBlockSize) {
      throw new ArgumentError("Block truncated");
    }

    var type = block[0];

    if (_forPrivateKey && (type != 2)) {
      throw new ArgumentError("Unsupported block type for private key: $type");
    }
    if (!_forPrivateKey && (type != 1)) {
      throw new ArgumentError("Unsupported block type for public key: $type");
    }
    if (block.length != _engine.outputBlockSize) {
      throw new ArgumentError("Block size is incorrect: ${block.length}");
    }

    // find and extract the message block.
    var start;

    for (start = 1; start < block.length; start++) {
      var pad = block[start];

      if (pad == 0) {
        break;
      }
      if (type == 1 && (pad != 0xFF)) {
        throw new ArgumentError("Incorrect block padding");
      }
    }

    start++;           // data should start at the next byte

    if ((start > block.length) || (start < _HEADER_LENGTH)) {
      throw new ArgumentError("No data found in block, only padding");
    }

    var result = new Uint8List(block.length - start);

    var rlen = (block.length - start);
    out.setRange(0, rlen, block.sublist(start));
    return rlen;
  }

}
