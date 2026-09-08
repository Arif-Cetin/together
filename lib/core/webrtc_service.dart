import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants.dart';

class WebRTCService {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  WebSocketChannel? _signalingChannel;

  MediaStream? localStream;
  MediaStream? screenStream;

  String? _myId;
  String? _roomId;

  // Güvenlik: Paroladan türetilen AES Şifreleme Motoru
  enc.Encrypter? _encrypter;
  final _iv = enc.IV.fromLength(16);

  bool isMicMuted = false;
  bool isCamOff = false;

  Function(MediaStream stream)? onRemoteStreamAdded;
  Function(String sender, String text)? onMessageReceived;
  Function(bool isConnected)? onConnectionStateChanged;

  // 1. Odaya Bağlan ve Güvenli Sinyalleşmeyi Başlat
  Future<void> connectToRoom(String roomId, String username) async {
    _roomId = roomId;
    _myId = '${username}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    // Şifre hash'inden 32-byte (256-bit) AES anahtarı türet
    final keyBytes = sha256.convert(utf8.encode(roomId)).bytes;
    _encrypter = enc.Encrypter(
      enc.AES(enc.Key(Uint8List.fromList(keyBytes)), mode: enc.AESMode.cbc),
    );

    await _initPeerConnection();
    _connectSignaling();
  }

  // Paketleri şifreleyerek gönderme
  String _encryptPayload(Map<String, dynamic> data) {
    final rawJson = jsonEncode(data);
    return _encrypter!.encrypt(rawJson, iv: _iv).base64;
  }

  // Gelen şifreli paketi çözme
  Map<String, dynamic>? _decryptPayload(String cipherText) {
    try {
      final decrypted = _encrypter!.decrypt64(cipherText, iv: _iv);
      return jsonDecode(decrypted);
    } catch (e) {
      // Başka şifreyle odayı dinlemeye çalışan biri varsa paketi çözemez
      return null;
    }
  }

  Future<void> _initPeerConnection() async {
    peerConnection = await createPeerConnection(AppConfig.rtcConfiguration, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && onRemoteStreamAdded != null) {
        onRemoteStreamAdded!(event.streams[0]);
      }
    };

    peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal({
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
        'sender': _myId,
      });
    };

    peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      final connected =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      if (onConnectionStateChanged != null) {
        onConnectionStateChanged!(connected);
      }
    };

    // Güvenli Data Channel (Sohbet)
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..ordered = true;
    dataChannel = await peerConnection!.createDataChannel(
      "secureChat",
      dataChannelDict,
    );
    _setupDataChannel(dataChannel!);

    peerConnection!.onDataChannel = (RTCDataChannel channel) {
      dataChannel = channel;
      _setupDataChannel(channel);
    };
  }

  // 2. Gerçek Çok Kullanıcılı Güvenli Sinyal Kanalı
  void _connectSignaling() {
    try {
      // Ortak çalışan ntfy WebSocket soketi (Echo yerine gerçek yayın yapar)
      final uri = Uri.parse('wss://ntfy.sh/together_${_roomId}/ws');
      _signalingChannel = WebSocketChannel.connect(uri);

      _signalingChannel!.stream.listen((message) async {
        try {
          final eventData = jsonDecode(message);
          if (eventData['event'] != 'message' || eventData['message'] == null)
            return;

          // Gelen şifreli sinyali çöz
          final data = _decryptPayload(eventData['message']);
          if (data == null || data['sender'] == _myId) return;

          switch (data['type']) {
            case 'join':
              await _createOffer();
              break;

            case 'offer':
              await _handleOffer(data['sdp']);
              break;

            case 'answer':
              await _handleAnswer(data['sdp']);
              break;

            case 'candidate':
              final c = data['candidate'];
              final candidate = RTCIceCandidate(
                c['candidate'],
                c['sdpMid'],
                c['sdpMLineIndex'],
              );
              await peerConnection?.addCandidate(candidate);
              break;
          }
        } catch (e) {
          debugPrint("Sinyal çözümleme: $e");
        }
      });

      // Odaya katıldığımızı anons et
      _sendSignal({'type': 'join', 'sender': _myId});
    } catch (e) {
      debugPrint("Soket bağlantı hatası: $e");
    }
  }

  void _sendSignal(Map<String, dynamic> data) {
    if (_encrypter == null) return;
    final encryptedData = _encryptPayload(data);

    // Odaya HTTP POST ile şifreli paket bırakılır, WebSocket anında diğer cihaza basar
    // (Flutter Web için sıfır maliyetli ve güvenli köprü)
    _signalingChannel?.sink.add(
      jsonEncode({'action': 'send', 'message': encryptedData}),
    );
  }

  Future<void> _createOffer() async {
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    _sendSignal({
      'type': 'offer',
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
      'sender': _myId,
    });
  }

  Future<void> _handleOffer(Map<String, dynamic> sdpMap) async {
    RTCSessionDescription desc = RTCSessionDescription(
      sdpMap['sdp'],
      sdpMap['type'],
    );
    await peerConnection!.setRemoteDescription(desc);

    RTCSessionDescription answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);

    _sendSignal({
      'type': 'answer',
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
      'sender': _myId,
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> sdpMap) async {
    RTCSessionDescription desc = RTCSessionDescription(
      sdpMap['sdp'],
      sdpMap['type'],
    );
    await peerConnection!.setRemoteDescription(desc);
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onMessage = (RTCDataChannelMessage message) {
      try {
        final decryptedText = _encrypter!.decrypt64(message.text, iv: _iv);
        final data = jsonDecode(decryptedText);
        if (data['type'] == 'msg' && onMessageReceived != null) {
          onMessageReceived!(data['sender'], data['text']);
        }
      } catch (e) {
        debugPrint("Chat paketi çözülemedi: $e");
      }
    };
  }

  void sendMessage(String sender, String text) {
    if (dataChannel != null &&
        dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      final raw = jsonEncode({'type': 'msg', 'sender': sender, 'text': text});
      final encrypted = _encrypter!.encrypt(raw, iv: _iv).base64;
      dataChannel!.send(RTCDataChannelMessage(encrypted));
    }
  }

  // 3. Medya Akışları
  Future<MediaStream> initLocalStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
      },
    };

    localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localStream!.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });
    return localStream!;
  }

  Future<MediaStream> startScreenShare() async {
    final Map<String, dynamic> screenConstraints = {
      'video': {'cursor': 'always'},
      'audio': true,
    };

    screenStream = await navigator.mediaDevices.getDisplayMedia(
      screenConstraints,
    );
    screenStream!.getTracks().forEach((track) {
      peerConnection?.addTrack(track, screenStream!);
    });
    return screenStream!;
  }

  void toggleMic() {
    if (localStream != null) {
      isMicMuted = !isMicMuted;
      for (var track in localStream!.getAudioTracks()) {
        track.enabled = !isMicMuted;
      }
    }
  }

  void toggleCam() {
    if (localStream != null) {
      isCamOff = !isCamOff;
      for (var track in localStream!.getVideoTracks()) {
        track.enabled = !isCamOff;
      }
    }
  }

  Future<void> dispose() async {
    localStream?.getTracks().forEach((t) => t.stop());
    screenStream?.getTracks().forEach((t) => t.stop());
    await localStream?.dispose();
    await screenStream?.dispose();
    await dataChannel?.close();
    await peerConnection?.close();
    await _signalingChannel?.sink.close();
  }
}
