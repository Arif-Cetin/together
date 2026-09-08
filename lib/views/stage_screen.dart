import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/constants.dart';
import '../core/webrtc_service.dart';
import 'reaction_layer.dart';

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
  final WebRTCService _rtcService = WebRTCService();
  final RTCVideoRenderer _screenRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localCamRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteCamRenderer = RTCVideoRenderer();

  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final List<FloatingReaction> _reactions = [];

  bool _isScreenSharing = false;
  bool _isCamActive = false;
  bool _isMicActive = true;
  bool _hasRemoteCam = false;
  bool _isConnected = false;
  bool _hasUnreadMessages = false;

  // Bağımsız Ses Seviyeleri (1.0 = %100, 2.0 = %200 Boost)
  double _screenVolume = 1.0;
  double _remoteUserVolume = 1.0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _setupRTC();
  }

  Future<void> _setupRTC() async {
    await _screenRenderer.initialize();
    await _localCamRenderer.initialize();
    await _remoteCamRenderer.initialize();

    await _rtcService.initPeerConnection();

    _rtcService.onRemoteStreamAdded = (stream) {
      _remoteCamRenderer.srcObject = stream;
      setState(() => _hasRemoteCam = true);
    };

    _rtcService.onMessageReceived = (sender, text) {
      setState(() {
        _messages.add({'sender': sender, 'text': text});
        if (_scaffoldKey.currentState?.isEndDrawerOpen != true) {
          _hasUnreadMessages = true;
        }
      });
    };

    _rtcService.onConnectionStateChanged = (connected) {
      setState(() => _isConnected = connected);
    };
  }

  void _triggerReaction(String emoji) {
    final reaction = FloatingReaction(
      id: UniqueKey().toString(),
      emoji: emoji,
      leftPosition:
          MediaQuery.of(context).size.width * 0.15 +
          Random().nextDouble() * (MediaQuery.of(context).size.width * 0.65),
    );

    setState(() => _reactions.add(reaction));

    Future.delayed(const Duration(milliseconds: 2300), () {
      if (mounted) {
        setState(() => _reactions.removeWhere((r) => r.id == reaction.id));
      }
    });
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

  Future<void> _toggleScreenShare() async {
    if (_isScreenSharing) {
      _screenRenderer.srcObject = null;
      setState(() => _isScreenSharing = false);
    } else {
      try {
        final stream = await _rtcService.startScreenShare();
        _screenRenderer.srcObject = stream;
        setState(() => _isScreenSharing = true);
      } catch (e) {
        debugPrint("Ekran paylaşımı hatası: $e");
      }
    }
  }

  Future<void> _toggleCam() async {
    if (_isCamActive) {
      _localCamRenderer.srcObject = null;
      _rtcService.toggleCam();
      setState(() => _isCamActive = false);
    } else {
      final stream = await _rtcService.initLocalStream();
      _localCamRenderer.srcObject = stream;
      setState(() => _isCamActive = true);
    }
  }

  // Katılımcı ve Ses Seviyesi Dialog Menüsü
  void _showUserVolumeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.glassBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.glassBorder),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.people_alt,
                    color: AppColors.neonGreenBright,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'KATILIMCILAR (${_isConnected ? 2 : 1})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Kendin
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.neonPurple,
                        child: Text(
                          widget.username[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      title: Text(
                        widget.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      trailing: const Text(
                        '(Sen)',
                        style: TextStyle(
                          color: AppColors.neonPurpleBright,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white12),

                    // Arkadaşın (Ses Slider'ı: %0 - %200 Boost)
                    if (_isConnected) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.neonGreen,
                          child: Text(
                            'A',
                            style: TextStyle(fontSize: 12, color: Colors.white),
                          ),
                        ),
                        title: const Text(
                          'Arkadaşın',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '%${(_remoteUserVolume * 100).round()}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        trailing: SizedBox(
                          width: 130,
                          child: Slider(
                            value: _remoteUserVolume,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            activeColor: AppColors.neonGreenBright,
                            onChanged: (val) {
                              setDialogState(() => _remoteUserVolume = val);
                              setState(() => _remoteUserVolume = val);
                            },
                          ),
                        ),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Odada başka kimse yok.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),

                    if (_isScreenSharing) ...[
                      const Divider(color: Colors.white12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.volume_up,
                          color: AppColors.neonPurpleBright,
                          size: 20,
                        ),
                        title: const Text(
                          'Yayın Sesi',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '%${(_screenVolume * 100).round()}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        trailing: SizedBox(
                          width: 130,
                          child: Slider(
                            value: _screenVolume,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            activeColor: AppColors.neonPurpleBright,
                            onChanged: (val) {
                              setDialogState(() => _screenVolume = val);
                              setState(() => _screenVolume = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgDarkest,
      onEndDrawerChanged: (isOpen) {
        if (isOpen) setState(() => _hasUnreadMessages = false);
      },
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.tv, color: AppColors.neonGreenBright, size: 20),
            const SizedBox(width: 8),
            const Text(
              '# sinema-odası',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),

            // Tıklanabilir Katılımcı Rozeti
            InkWell(
              onTap: _showUserVolumeDialog,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isConnected
                            ? AppColors.neonGreenBright
                            : const Color(0xFFF0B232),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Oda: ${_isConnected ? 2 : 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Tepki / Emoji Menüsü
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.favorite,
              color: AppColors.neonPurpleBright,
              size: 20,
            ),
            color: AppColors.glassBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.glassBorder),
            ),
            onSelected: _triggerReaction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: '❤️', child: Text('❤️ Kalp')),
              const PopupMenuItem(value: '🍿', child: Text('🍿 Mısır')),
              const PopupMenuItem(value: '😂', child: Text('😂 Kahkaha')),
              const PopupMenuItem(value: '🔥', child: Text('🔥 Ateş')),
              const PopupMenuItem(value: '✨', child: Text('✨ Işıltı')),
            ],
          ),

          // Sohbet Butonu & Kırmızı Bildirim Noktası
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.forum, color: Colors.white70),
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
              if (_hasUnreadMessages)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),

      // Discord Sağ Sohbet Paneli
      endDrawer: Drawer(
        backgroundColor: AppColors.glassBg,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 44, 16, 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.glassBorder),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '# genel-sohbet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isMe = msg['sender'] == widget.username;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['sender']!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isMe
                                ? AppColors.neonPurpleBright
                                : AppColors.neonGreenBright,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            msg['text']!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: AppColors.bgSurface,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '#genel-sohbet kanalına yaz...',
                        hintStyle: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: AppColors.inputBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: AppColors.neonGreenBright,
                      size: 18,
                    ),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // Ekran, Kameralar ve Tepkiler
      body: Stack(
        children: [
          Positioned.fill(
            child: _isScreenSharing
                ? Center(
                    child: RTCVideoView(
                      _screenRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.neonGreen,
                                AppColors.neonPurple,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.neonPurple.withOpacity(0.4),
                                blurRadius: 25,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.movie_creation_outlined,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'together Sineması',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ekran paylaşıldığında yayın burada belirecek.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // Kamera Izgarası
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                if (_isCamActive)
                  _buildCamBox(
                    _localCamRenderer,
                    '${widget.username} (Sen)',
                    true,
                  ),
                if (_hasRemoteCam)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildCamBox(_remoteCamRenderer, 'Arkadaşın', false),
                  ),
              ],
            ),
          ),

          // Uçuşan Tepkiler Katmanı
          Positioned.fill(child: ReactionLayer(reactions: _reactions)),

          // Alt Kontrol Butonları
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.glassBg,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: const [
                    BoxShadow(color: Colors.black87, blurRadius: 20),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_isMicActive ? Icons.mic : Icons.mic_off),
                      color: _isMicActive ? Colors.white : AppColors.danger,
                      onPressed: () {
                        _rtcService.toggleMic();
                        setState(() => _isMicActive = !_isMicActive);
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _isCamActive ? Icons.videocam : Icons.videocam_off,
                      ),
                      color: _isCamActive
                          ? AppColors.neonGreenBright
                          : Colors.white70,
                      onPressed: _toggleCam,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.desktop_windows),
                      color: _isScreenSharing
                          ? AppColors.neonPurpleBright
                          : Colors.white70,
                      onPressed: _toggleScreenShare,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.call_end),
                      color: AppColors.danger,
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, '/'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamBox(RTCVideoRenderer renderer, String tag, bool isLocal) {
    return Container(
      width: 150,
      height: 95,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            RTCVideoView(
              renderer,
              mirror: isLocal,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            Positioned(
              bottom: 4,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(
                  tag,
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
