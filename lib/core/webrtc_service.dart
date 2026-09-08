import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'constants.dart';

class WebRTCService {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  MediaStream? localStream;
  MediaStream? screenStream;

  String? _myId;
  String? _roomId;
  DatabaseReference? _roomRef;
  StreamSubscription? _roomSub;
  StreamSubscription? _candidatesSub;

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

    final keyBytes = sha256.convert(utf8.encode(roomId)).bytes;
    _encrypter = enc.Encrypter(
      enc.AES(enc.Key(Uint8List.fromList(keyBytes)), mode: enc.AESMode.cbc),
    );

    _roomRef = _database.ref('rooms/$_roomId');

    await _initPeerConnection();
    await _startSignaling();
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
      if (_roomRef == null) return;
      final cipher = _encrypt({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'sender': _myId,
      });
      _roomRef!.child('candidates').push().set({
        'payload': cipher,
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
      "secureChat",
      dataChannelDict,
    );
    _setupDataChannel(dataChannel!);

    peerConnection!.onDataChannel = (RTCDataChannel channel) {
      dataChannel = channel;
      _setupDataChannel(channel);
    };
  }

  Future<void> _startSignaling() async {
    final snapshot = await _roomRef!.get();

    if (!snapshot.exists || snapshot.value == null) {
      // 1. Cihaz: Odayı açıp Offer bırakır
      RTCSessionDescription offer = await peerConnection!.createOffer();
      await peerConnection!.setLocalDescription(offer);

      final cipherOffer = _encrypt({
        'type': offer.type,
        'sdp': offer.sdp,
        'sender': _myId,
      });
      await _roomRef!.set({'offer': cipherOffer});

      // İkinci cihazın bırakacağı cevabı (Answer) dinler
      _roomSub = _roomRef!.child('answer').onValue.listen((event) async {
        if (event.snapshot.value != null &&
            peerConnection?.getRemoteDescription() == null) {
          final answerData = _decrypt(event.snapshot.value.toString());
          if (answerData != null && answerData['sender'] != _myId) {
            final desc = RTCSessionDescription(
              answerData['sdp'],
              answerData['type'],
            );
            await peerConnection!.setRemoteDescription(desc);
          }
        }
      });
    } else {
      // 2. Cihaz: Var olan odaya katılır ve Answer yazar
      final roomData = Map<String, dynamic>.from(snapshot.value as Map);
      if (roomData.containsKey('offer')) {
        final offerData = _decrypt(roomData['offer']);
        if (offerData != null) {
          final desc = RTCSessionDescription(
            offerData['sdp'],
            offerData['type'],
          );
          await peerConnection!.setRemoteDescription(desc);

          RTCSessionDescription answer = await peerConnection!.createAnswer();
          await peerConnection!.setLocalDescription(answer);

          final cipherAnswer = _encrypt({
            'type': answer.type,
            'sdp': answer.sdp,
            'sender': _myId,
          });
          await _roomRef!.child('answer').set(cipherAnswer);
        }
      }
    }

    // Karşı tarafın ICE adaylarını dinle
    _candidatesSub = _roomRef!.child('candidates').onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val != null) {
        final data = Map<String, dynamic>.from(val as Map);
        if (data.containsKey('payload')) {
          final cData = _decrypt(data['payload']);
          if (cData != null && cData['sender'] != _myId) {
            peerConnection?.addCandidate(
              RTCIceCandidate(
                cData['candidate'],
                cData['sdpMid'],
                cData['sdpMLineIndex'],
              ),
            );
          }
        }
      }
    });
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
    await _roomSub?.cancel();
    await _candidatesSub?.cancel();
    localStream?.getTracks().forEach((t) => t.stop());
    screenStream?.getTracks().forEach((t) => t.stop());
    await localStream?.dispose();
    await screenStream?.dispose();
    await dataChannel?.close();
    await peerConnection?.close();
  }
}
