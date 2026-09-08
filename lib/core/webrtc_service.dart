import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'constants.dart';

class WebRTCService {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  MqttBrowserClient? _mqttClient;

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

  // 1. Odaya Bağlan ve Sinyalleşmeyi Başlat
  Future<void> connectToRoom(String roomId, String username) async {
    _roomId = roomId;
    _myId = '${username}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    // Şifre hash'inden 256-bit AES anahtarı türet
    final keyBytes = sha256.convert(utf8.encode(roomId)).bytes;
    _encrypter = enc.Encrypter(
      enc.AES(enc.Key(Uint8List.fromList(keyBytes)), mode: enc.AESMode.cbc),
    );

    await _initPeerConnection();
    await _setupSignaling();
  }

  String _encryptPayload(Map<String, dynamic> data) {
    return _encrypter!.encrypt(jsonEncode(data), iv: _iv).base64;
  }

  Map<String, dynamic>? _decryptPayload(String cipherText) {
    try {
      final decrypted = _encrypter!.decrypt64(cipherText, iv: _iv);
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

  // 2. MQTT WebSocket Sinyalleşme Hattı
  Future<void> _setupSignaling() async {
    final clientId =
        'client_${_myId}_${DateTime.now().millisecondsSinceEpoch % 1000}';
    _mqttClient = MqttBrowserClient('wss://broker.emqx.io/mqtt', clientId);
    _mqttClient!.port = 8084;
    _mqttClient!.websocketProtocols =
        MqttClientConstants.protocolsSingleDefault;
    _mqttClient!.logging(on: false);
    _mqttClient!.keepAlivePeriod = 20;

    try {
      await _mqttClient!.connect();
    } catch (e) {
      debugPrint("MQTT Broker bağlantı hatası: $e");
      return;
    }

    final topic = 'together/room/$_roomId';
    _mqttClient!.subscribe(topic, MqttQos.atLeastOnce);

    _mqttClient!.updates!.listen((
      List<MqttReceivedMessage<MqttMessage>> c,
    ) async {
      final recMess = c[0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      final data = _decryptPayload(pt);
      if (data == null || data['sender'] == _myId) return;

      switch (data['type']) {
        case 'join':
          // Yeni gelen cihaz için Offer oluştur
          await _createOffer();
          break;
        case 'offer':
          await _handleOffer(data['sdp']);
          break;
        case 'answer':
          await _handleAnswer(data['sdp']);
          break;
        case 'candidate':
          final cd = data['candidate'];
          await peerConnection?.addCandidate(
            RTCIceCandidate(cd['candidate'], cd['sdpMid'], cd['sdpMLineIndex']),
          );
          break;
      }
    });

    // Odaya katıldığımızı duyur
    Timer(const Duration(milliseconds: 500), () {
      _sendSignal({'type': 'join', 'sender': _myId});
    });
  }

  void _sendSignal(Map<String, dynamic> data) {
    if (_mqttClient == null ||
        _mqttClient!.connectionStatus!.state != MqttConnectionState.connected) {
      return;
    }
    final cipher = _encryptPayload(data);
    final builder = MqttClientPayloadBuilder();
    builder.addString(cipher);
    _mqttClient!.publishMessage(
      'together/room/$_roomId',
      MqttQos.atLeastOnce,
      builder.payload!,
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
        final decrypted = _encrypter!.decrypt64(message.text, iv: _iv);
        final data = jsonDecode(decrypted);
        if (data['type'] == 'msg' && onMessageReceived != null) {
          onMessageReceived!(data['sender'], data['text']);
        }
      } catch (e) {
        debugPrint("DataChannel çözme hatası: $e");
      }
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

  // 3. Medya Akışları (Kamera, Mikrofon, Ekran)
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
    _mqttClient?.disconnect();
  }
}
