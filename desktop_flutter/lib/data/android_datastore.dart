import '../i18n/tr.dart';
import 'dart:convert';
import 'dart:typed_data';

class AndroidDataStore {
  static Map<String, String> stringPreferences(Uint8List bytes) => {
    for (final entry in preferences(bytes).entries)
      if (entry.value is String) entry.key: entry.value as String,
  };

  static Map<String, Object> preferences(Uint8List bytes) {
    if (bytes.length > 8 * 1024 * 1024) {
      throw       FormatException(tr('DataStore 备份过大。'));
    }
    final reader = _ProtoReader(bytes);
    final result = <String, Object>{};
    final keys = <String>{};
    while (!reader.done) {
      final tag = reader.tag();
      if (tag != 10) {
        reader.skip(tag);
        continue;
      }
      final entry = _ProtoReader(reader.message());
      String? key;
      Object? value;
      var hasValue = false;
      while (!entry.done) {
        final field = entry.tag();
        if (field == 10) {
          if (key != null) throw FormatException(tr('重复 DataStore 配置名。'));
          key = utf8.decode(entry.message());
        } else if (field == 18) {
          if (hasValue) throw       FormatException(tr('重复 DataStore 配置值。'));
          hasValue = true;
          value = _value(entry.message());
        } else {
          entry.skip(field);
        }
      }
      if (key == null || key.isEmpty || key.length > 256 || !hasValue) {
        throw       FormatException(tr('DataStore 配置结构无效。'));
      }
      if (!keys.add(key) || keys.length > 4096) {
        throw       FormatException(tr('DataStore 配置重复或数量过多。'));
      }
      if (value != null) result[key] = value;
    }
    return result;
  }

  static Object? _value(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    Object? result;
    var populated = false;
    while (!reader.done) {
      final tag = reader.tag();
      final field = tag >> 3;
      if (field >= 1 && field <= 8) {
        const wires = [0, 5, 0, 0, 2, 2, 1, 2];
        if ((tag & 7) != wires[field - 1]) {
          throw       FormatException(tr('DataStore 值类型无效。'));
        }
        if (populated) throw       FormatException(tr('DataStore 值存在歧义。'));
        populated = true;
      }
      switch (tag) {
        case 8:
          final value = reader.varint();
          if (value != 0 && value != 1) {
            throw       FormatException(tr('DataStore 布尔值无效。'));
          }
          result = value == 1;
        case 21:
        case 57:
          final data = reader.fixed(tag == 21 ? 4 : 8);
          final value = tag == 21
              ? data.getFloat32(0, Endian.little)
              : data.getFloat64(0, Endian.little);
          if (!value.isFinite) {
            throw       FormatException(tr('DataStore 浮点值无效。'));
          }
          result = value;
        case 24:
          final value = reader.varint();
          if (value < -2147483648 || value > 2147483647) {
            throw       FormatException(tr('DataStore 整数越界。'));
          }
          result = value;
        case 32:
          result = reader.varint();
        case 42:
          result = utf8.decode(reader.message());
        case 50:
          final values = _ProtoReader(reader.message());
          final strings = <String>{};
          while (!values.done) {
            final field = values.tag();
            if (field == 10) {
              strings.add(utf8.decode(values.message()));
            } else {
              values.skip(field);
            }
          }
          result = strings;
        case 66:
          result = Uint8List.fromList(reader.message());
        default:
          reader.skip(tag);
      }
    }
    if (!populated) throw       FormatException(tr('DataStore 配置缺少值。'));
    return result;
  }
}

class _ProtoReader {
  _ProtoReader(this.bytes);
  final Uint8List bytes;
  int position = 0;
  bool get done => position == bytes.length;

  int varint() {
    var value = 0;
    for (var index = 0; index < 10; index++) {
      if (done) throw       FormatException(tr('DataStore 备份已截断。'));
      final byte = bytes[position++];
      if (index == 9 && byte > 1) {
        throw       FormatException(tr('DataStore 整数越界。'));
      }
      value |= (byte & 127) << (index * 7);
      if (byte < 128) return value;
    }
    throw       FormatException(tr('DataStore 整数无效。'));
  }

  int tag() {
    final value = varint();
    if (value <= 0 || value >> 3 == 0 || value >> 3 > 0x1fffffff) {
      throw       FormatException(tr('DataStore 字段无效。'));
    }
    return value;
  }

  Uint8List message() {
    final length = varint();
    if (length < 0 || length > bytes.length - position) {
      throw       FormatException(tr('DataStore 备份已截断。'));
    }
    final result = Uint8List.sublistView(bytes, position, position + length);
    position += length;
    return result;
  }

  ByteData fixed(int length) {
    if (length > bytes.length - position) {
      throw       FormatException(tr('DataStore 备份已截断。'));
    }
    final result = ByteData.sublistView(bytes, position, position + length);
    position += length;
    return result;
  }

  void skip(int tag) {
    final wire = tag & 7;
    if (wire == 0) {
      varint();
    } else if (wire == 2) {
      message();
    } else if (wire == 1 || wire == 5) {
      final length = wire == 1 ? 8 : 4;
      if (length > bytes.length - position) {
        throw       FormatException(tr('DataStore 备份已截断。'));
      }
      position += length;
    } else {
      throw       FormatException(tr('DataStore 编码无效。'));
    }
  }
}
