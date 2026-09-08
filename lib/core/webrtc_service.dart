import 'dart:async';
import 'dart:convert';

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
  bool isHost = false;

  bool isMicMuted = false;
  bool isCamOff = false;

  Function(MediaStream stream)? onRemoteStreamAdded;
  Function(String sender, String text)? onMessageReceived;
  Function(bool isConnected)? onConnectionStateChanged;

  // 1. Odaya Bağlan ve Sinyalleşmeyi Başlat
  Future<void> connectToRoom(String roomId, String username) async {
    _roomId = roomId;
    _myId = '${username}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    await _initPeerConnection();
    _connectSignaling();
  }

  Future<void> _initPeerConnection() async {
    peerConnection = await createPeerConnection(AppConfig.rtcConfiguration, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    // Uzaktan medya akışı geldiğinde
    peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && onRemoteStreamAdded != null) {
        onRemoteStreamAdded!(event.streams[0]);
      }
    };

    // ICE Candidate toplanınca diğer tarafa ilet
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

    // Data Channel (Sohbet)
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

  // 2. Ücretsiz Genel Sinyalleşme Broker'ı (P2P El Sıkışması İçin)
  void _connectSignaling() {
    try {
      // Ücretsiz ve genel PieSocket / echo sinyalleşme endpoint'i
      final uri = Uri.parse('wss://echo.websocket.events');
      _signalingChannel = WebSocketChannel.connect(uri);

      _signalingChannel!.stream.listen((message) async {
        try {
          final data = jsonDecode(message);
          if (data['room'] != _roomId || data['sender'] == _myId) return;

          switch (data['type']) {
            case 'join':
              // Odaya yeni biri geldi, biz eskiysek Offer üret
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
          debugPrint("Sinyal parse hatası: $e");
        }
      });

      // Odaya girdiğimizi anons et
      _sendSignal({'type': 'join', 'sender': _myId});
    } catch (e) {
      debugPrint("Sinyal soket bağlantı hatası: $e");
    }
  }

  void _sendSignal(Map<String, dynamic> data) {
    data['room'] = _roomId;
    _signalingChannel?.sink.add(jsonEncode(data));
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
        final data = jsonDecode(message.text);
        if (data['type'] == 'msg' && onMessageReceived != null) {
          onMessageReceived!(data['sender'], data['text']);
        }
      } catch (e) {
        debugPrint("Veri kanalı mesaj hatası: $e");
      }
    };
  }

  void sendMessage(String sender, String text) {
    if (dataChannel != null &&
        dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      final payload = jsonEncode({
        'type': 'msg',
        'sender': sender,
        'text': text,
      });
      dataChannel!.send(RTCDataChannelMessage(payload));
    }
  }

  // 3. Medya Fonksiyonları
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
