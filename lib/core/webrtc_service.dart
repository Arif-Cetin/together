import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants.dart';

class WebRTCService {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  WebSocketChannel? _wsChannel;

  MediaStream? localStream;
  MediaStream? screenStream;

  String? _myId;
  String? _roomId;

  enc.Encrypter? _encrypter;
  final _iv = enc.IV.fromLength(16);

  bool isMicMuted = false;
  bool isCamOff = false;

  Function(MediaStream stream)? onRemoteStreamAdded;
  Function(String sender, String text)? onMessageReceived;
  Function(bool isConnected)? onConnectionStateChanged;

  Future<void> connectToRoom(String roomId, String username) async {
    _roomId = roomId;
    _myId = '${username}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    // Şifre hash'inden 32-byte AES anahtarı üret
    final keyBytes = sha256.convert(utf8.encode(roomId)).bytes;
    _encrypter = enc.Encrypter(
      enc.AES(enc.Key(Uint8List.fromList(keyBytes)), mode: enc.AESMode.cbc),
    );

    await _initPeerConnection();
    _startSignaling();
  }

  String _encrypt(Map<String, dynamic> data) {
    return _encrypter!.encrypt(jsonEncode(data), iv: _iv).base64;
  }

  Map<String, dynamic>? _decrypt(String cipher) {
    try {
      final decrypted = _encrypter!.decrypt64(cipher, iv: _iv);
      return jsonDecode(decrypted);
    } catch (_) {
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

    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..ordered = true;
    dataChannel = await peerConnection!.createDataChannel(
      "chatChannel",
      dataChannelDict,
    );
    _setupDataChannel(dataChannel!);

    peerConnection!.onDataChannel = (RTCDataChannel channel) {
      dataChannel = channel;
      _setupDataChannel(channel);
    };
  }

  void _startSignaling() {
    final topic = 'together_mesh_room_$_roomId';
    final wsUrl = Uri.parse('wss://ntfy.sh/$topic/ws');

    try {
      _wsChannel = WebSocketChannel.connect(wsUrl);

      _wsChannel!.stream.listen((event) async {
        try {
          final msg = jsonDecode(event);
          if (msg['event'] != 'message' || msg['message'] == null) return;

          final data = _decrypt(msg['message']);
          if (data == null || data['sender'] == _myId) return;

          switch (data['type']) {
            case 'join':
              // Yeni bir cihaz geldiğinde Offer üret
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
              await peerConnection?.addCandidate(
                RTCIceCandidate(
                  c['candidate'],
                  c['sdpMid'],
                  c['sdpMLineIndex'],
                ),
              );
              break;
          }
        } catch (_) {}
      });

      // Odaya katıldığını anons et
      Timer(const Duration(milliseconds: 600), () {
        _sendSignal({'type': 'join', 'sender': _myId});
      });
    } catch (e) {
      debugPrint("Sinyal hattı hatası: $e");
    }
  }

  Future<void> _sendSignal(Map<String, dynamic> data) async {
    if (_encrypter == null) return;
    final cipher = _encrypt(data);
    final topic = 'together_mesh_room_$_roomId';

    try {
      await http.post(Uri.parse('https://ntfy.sh/$topic'), body: cipher);
    } catch (_) {}
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
        final decrypted = _encrypter!.decrypt64(message.text, iv: _iv);
        final data = jsonDecode(decrypted);
        if (data['type'] == 'msg' && onMessageReceived != null) {
          onMessageReceived!(data['sender'], data['text']);
        }
      } catch (_) {}
    };
  }

  void sendMessage(String sender, String text) {
    if (dataChannel != null &&
        dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      final raw = jsonEncode({'type': 'msg', 'sender': sender, 'text': text});
      final cipher = _encrypter!.encrypt(raw, iv: _iv).base64;
      dataChannel!.send(RTCDataChannelMessage(cipher));
    }
  }

  Future<MediaStream> initLocalStream() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
      },
    });
    localStream!.getTracks().forEach(
      (track) => peerConnection?.addTrack(track, localStream!),
    );
    return localStream!;
  }

  Future<MediaStream> startScreenShare() async {
    screenStream = await navigator.mediaDevices.getDisplayMedia({
      'video': {'cursor': 'always'},
      'audio': true,
    });
    screenStream!.getTracks().forEach(
      (track) => peerConnection?.addTrack(track, screenStream!),
    );
    return screenStream!;
  }

  void toggleMic() {
    if (localStream != null) {
      isMicMuted = !isMicMuted;
      for (var t in localStream!.getAudioTracks()) {
        t.enabled = !isMicMuted;
      }
    }
  }

  void toggleCam() {
    if (localStream != null) {
      isCamOff = !isCamOff;
      for (var t in localStream!.getVideoTracks()) {
        t.enabled = !isCamOff;
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
    await _wsChannel?.sink.close();
  }
}
