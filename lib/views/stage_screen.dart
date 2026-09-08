import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/constants.dart';
import '../core/webrtc_service.dart';

class StageScreen extends StatefulWidget {
  final String username;
  final String roomHash;

  const StageScreen({
    super.key,
    required this.username,
    required this.roomHash,
  });

  @override
  State<StageScreen> createState() => _StageScreenState();
}

class _StageScreenState extends State<StageScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final WebRTCService _rtcService = WebRTCService();

  final RTCVideoRenderer _screenRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localCamRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteCamRenderer = RTCVideoRenderer();

  bool _hasRemoteCam = false;
  bool _hasScreenShare = false;
  bool _isConnected = false;
  bool _hasUnreadMessages = false;

  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _messages = [];

  // Kullanıcı ses seviyeleri (0.0 - 2.0)
  double _screenVolume = 1.0;
  final Map<String, double> _userVolumes = {};

  @override
  void initState() {
    super.initState();
    _setupRTC();
  }

  Future<void> _setupRTC() async {
    await _screenRenderer.initialize();
    await _localCamRenderer.initialize();
    await _remoteCamRenderer.initialize();

    // Sinyalleşme ve odaya bağlantı
    await _rtcService.connectToRoom(widget.roomHash, widget.username);

    _rtcService.onRemoteStreamAdded = (stream) {
      if (mounted) {
        setState(() {
          _remoteCamRenderer.srcObject = stream;
          _hasRemoteCam = true;
        });
      }
    };

    _rtcService.onMessageReceived = (sender, text) {
      if (mounted) {
        setState(() {
          _messages.add({'sender': sender, 'text': text});
          if (_scaffoldKey.currentState?.isEndDrawerOpen != true) {
            _hasUnreadMessages = true;
          }
        });
      }
    };

    _rtcService.onConnectionStateChanged = (connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
      }
    };
  }

  @override
  void dispose() {
    _screenRenderer.dispose();
    _localCamRenderer.dispose();
    _remoteCamRenderer.dispose();
    _rtcService.dispose();
    _chatController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    _rtcService.sendMessage(widget.username, text);
    setState(() {
      _messages.add({'sender': widget.username, 'text': text});
      _chatController.clear();
    });
  }

  void _showUserListModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.glassBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Odadakiler ve Ses Ayarları",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  // Kendi Profilin
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.neonPurple,
                      child: Text(
                        widget.username[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      widget.username,
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: const Text(
                      "(Sen)",
                      style: TextStyle(
                        color: AppColors.neonPurpleBright,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Bağlı Karşı Taraf
                  if (_isConnected)
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.neonGreen,
                        child: Text("K", style: TextStyle(color: Colors.white)),
                      ),
                      title: const Text(
                        "Katılımcı",
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Row(
                        children: [
                          const Icon(
                            Icons.volume_down,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: Slider(
                              value: _userVolumes['remote'] ?? 1.0,
                              min: 0.0,
                              max: 2.0,
                              divisions: 20,
                              activeColor: AppColors.neonGreenBright,
                              onChanged: (val) {
                                setModalState(
                                  () => _userVolumes['remote'] = val,
                                );
                                setState(() => _userVolumes['remote'] = val);
                              },
                            ),
                          ),
                          Text(
                            "%${((_userVolumes['remote'] ?? 1.0) * 100).round()}",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        "Henüz başka katılımcı bağlanmadı...",
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgDarkest,
      endDrawer: _buildChatDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.bgRail,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.tv, color: AppColors.neonPurpleBright, size: 20),
            const SizedBox(width: 8),
            const Text(
              "together",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: _showUserListModal,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isConnected
                        ? AppColors.neonGreen
                        : AppColors.glassBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isConnected
                            ? AppColors.neonGreenBright
                            : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected ? "Bağlandı (2)" : "Oda: 1",
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.forum, color: AppColors.textMain),
                onPressed: () {
                  setState(() => _hasUnreadMessages = false);
                  _scaffoldKey.currentState?.openEndDrawer();
                },
              ),
              if (_hasUnreadMessages)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Ana Yayın Alanı
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _hasScreenShare
                  ? RTCVideoView(_screenRenderer)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.movie,
                            size: 64,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(height: 12),
                          Text(
                            "Yayın Bekleniyor",
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "PC'den bağlanan kişi alttan ekran paylaşabilir.",
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),

          // Kameralar (Floating PIP)
          Positioned(
            bottom: 90,
            right: 16,
            child: Column(
              children: [
                if (_localCamRenderer.srcObject != null)
                  _buildCamBox(_localCamRenderer, "${widget.username} (Sen)"),
                if (_hasRemoteCam)
                  _buildCamBox(_remoteCamRenderer, "Katılımcı"),
              ],
            ),
          ),

          // Alt Dock Kontrol Butonları
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.glassBg,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _rtcService.isMicMuted ? Icons.mic_off : Icons.mic,
                      color: _rtcService.isMicMuted
                          ? AppColors.danger
                          : AppColors.neonGreenBright,
                    ),
                    onPressed: () {
                      _rtcService.toggleMic();
                      setState(() {});
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      _localCamRenderer.srcObject == null
                          ? Icons.videocam_off
                          : Icons.videocam,
                      color: _localCamRenderer.srcObject == null
                          ? AppColors.textMuted
                          : AppColors.neonGreenBright,
                    ),
                    onPressed: () async {
                      if (_localCamRenderer.srcObject == null) {
                        final stream = await _rtcService.initLocalStream();
                        setState(() => _localCamRenderer.srcObject = stream);
                      } else {
                        _rtcService.toggleCam();
                        setState(() {});
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      _hasScreenShare
                          ? Icons.stop_screen_share
                          : Icons.screen_share,
                      color: _hasScreenShare
                          ? AppColors.neonPurpleBright
                          : AppColors.textMain,
                    ),
                    onPressed: () async {
                      if (!_hasScreenShare) {
                        final s = await _rtcService.startScreenShare();
                        setState(() {
                          _screenRenderer.srcObject = s;
                          _hasScreenShare = true;
                        });
                      } else {
                        setState(() {
                          _screenRenderer.srcObject = null;
                          _hasScreenShare = false;
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.call_end, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamBox(RTCVideoRenderer renderer, String tag) {
    return Container(
      width: 140,
      height: 90,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          RTCVideoView(
            renderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: Colors.black87,
              child: Text(
                tag,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatDrawer() {
    return Drawer(
      backgroundColor: AppColors.bgSurface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.bgRail,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "# sohbet",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, idx) {
                  final m = _messages[idx];
                  final isMe = m['sender'] == widget.username;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['sender'] ?? '',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? AppColors.neonPurple
                                : AppColors.bgRail,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            m['text'] ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Mesaj gönder...",
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.inputBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: AppColors.neonPurpleBright,
                    ),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
