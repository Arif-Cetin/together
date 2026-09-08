import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'constants.dart';

class WebRTCService {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;

  MediaStream? localStream;
  MediaStream? screenStream;

  bool isMicMuted = false;
  bool isCamOff = false;

  // Olay Dinleyicileri (Callback'ler)
  Function(MediaStream stream)? onRemoteStreamAdded;
  Function(String sender, String text)? onMessageReceived;
  Function(bool isConnected)? onConnectionStateChanged;

  // WebRTC Peer Bağlantısını Başlatma
  Future<void> initPeerConnection() async {
    peerConnection = await createPeerConnection(AppConfig.rtcConfiguration, {});

    // Uzaktaki video/ses akışı geldiğinde yakala
    peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && onRemoteStreamAdded != null) {
        onRemoteStreamAdded!(event.streams[0]);
      }
    };

    // Bağlantı durumu değiştiğinde
    peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      final connected =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      if (onConnectionStateChanged != null) {
        onConnectionStateChanged!(connected);
      }
    };

    // Veri Kanalı (Chat için)
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit();
    dataChannel = await peerConnection!.createDataChannel(
      "chatChannel",
      dataChannelDict,
    );
    _setupDataChannelListeners(dataChannel!);

    peerConnection!.onDataChannel = (RTCDataChannel channel) {
      dataChannel = channel;
      _setupDataChannelListeners(channel);
    };
  }

  void _setupDataChannelListeners(RTCDataChannel channel) {
    channel.onMessage = (RTCDataChannelMessage message) {
      try {
        final data = jsonDecode(message.text);
        if (data['type'] == 'msg' && onMessageReceived != null) {
          onMessageReceived!(data['sender'], data['text']);
        }
      } catch (e) {
        debugPrint("Chat veri hatası: $e");
      }
    };
  }

  // Mesaj Gönderme
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

  // Kamera & Mikrofon Başlat
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

  // PC Ekran Paylaşımı
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
  }
}
