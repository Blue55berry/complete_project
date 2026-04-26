import sys
import re

path = r'frontend/lib/screens/intelligence/threat_intelligence_screen.dart'
try:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
except FileNotFoundError:
    print('Error: Could not find dart file.')
    sys.exit(1)

# 1. Update _buildPreviewContent in _SmallMediaPreview
preview_old = '''  Widget _buildPreviewContent() {
    // If we have base64 preview data (image/video), show the thumbnail
    if (threat.previewData != null && threat.previewData!.isNotEmpty) {
      try {
        // Strip data-URI prefix if present: "data:image/png;base64,..."
        String raw = threat.previewData!;
        final commaIdx = raw.indexOf(',');
        if (commaIdx > 0 && commaIdx < 80) raw = raw.substring(commaIdx + 1);
        final bytes = base64Decode(raw);
        return Image.memory(bytes, fit: BoxFit.cover, width: 44, height: 44);
      } catch (_) {}
    }

    // Fallback: show media-type-specific icon
    final mediaType = threat.mediaType.toLowerCase();
    if (mediaType.contains('image') || threat.threatClass.contains('image')) {
      return const Center(
        child: Icon(Icons.image_rounded, color: Color(0xFF26D9FF), size: 22),
      );
    } else if (mediaType.contains('video') ||
        threat.threatClass.contains('video')) {
      return const Center(
        child: Icon(
          Icons.play_circle_filled_rounded,
          color: Color(0xFFFF7043),
          size: 22,
        ),
      );
    } else if (mediaType.contains('voice') ||
        threat.threatClass.contains('voice') ||
        threat.threatClass.contains('clone')) {
      return _MiniWaveform();
    } else {
      return const Center(
        child: Icon(
          Icons.description_rounded,
          color: Color(0xFF7AA6C1),
          size: 22,
        ),
      );
    }
  }'''

preview_new = '''  Widget _buildPreviewContent() {
    final mediaType = threat.mediaType.toLowerCase();
    final cls = threat.threatClass.toLowerCase();
    final isVideo = cls.contains('video') || mediaType.contains('video');
    final isVoice = cls.contains('voice') || cls.contains('clone') || mediaType.contains('voice') || mediaType.contains('audio');
    
    // Voice thumbnail logic
    if (isVoice) {
      return Container(
        color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_rounded, color: Color(0xFF14B8A6), size: 14),
              const SizedBox(height: 2),
              _MiniWaveform(),
            ]
          )
        ),
      );
    }

    Widget? thumbnail;
    if (threat.previewData != null && threat.previewData!.isNotEmpty) {
      try {
        String raw = threat.previewData!;
        final commaIdx = raw.indexOf(',');
        if (commaIdx > 0 && commaIdx < 80) raw = raw.substring(commaIdx + 1);
        final bytes = base64Decode(raw);
        thumbnail = Image.memory(bytes, fit: BoxFit.cover, width: 44, height: 44);
      } catch (_) {}
    }

    if (isVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnail != null) thumbnail,
          Container(color: Colors.black.withValues(alpha: 0.4)),
          Center(
            child: Icon(
              Icons.play_arrow_rounded,
              color: const Color(0xFFFF7043),
              size: 26,
            ),
          ),
        ],
      );
    } else if (thumbnail != null) {
      return thumbnail;
    }

    if (cls.contains('image') || mediaType.contains('image')) {
      return const Center(
        child: Icon(Icons.image_rounded, color: Color(0xFF26D9FF), size: 22),
      );
    } else {
      return Container(
        color: const Color(0xFF26D9FF).withValues(alpha: 0.05),
        child: Center(
          child: Icon(
            Icons.article_rounded,
            color: const Color(0xFF7AA6C1).withValues(alpha: 0.8),
            size: 22,
          ),
        ),
      );
    }
  }'''

# 2. Update _buildExpandedContent
expanded_old = '''  Widget _buildExpandedContent() {
    // If we have base64 preview data, show the image
    if (threat.previewData != null && threat.previewData!.isNotEmpty) {
      try {
        String raw = threat.previewData!;
        final commaIdx = raw.indexOf(',');
        if (commaIdx > 0 && commaIdx < 80) raw = raw.substring(commaIdx + 1);
        final bytes = base64Decode(raw.trim());
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => _NoPreviewPlaceholder(
              icon: Icons.broken_image_rounded,
              label: 'Image could not be loaded',
              color: const Color(0xFF26D9FF),
            ),
          ),
        );
      } catch (_) {
        // Fall through to type-based fallback
      }
    }

    // Fallback by analysed media type
    final mediaType = threat.mediaType.toLowerCase();
    final cls = threat.threatClass.toLowerCase();
    if (cls.contains('voice') || cls.contains('clone') ||
        mediaType.contains('voice') || mediaType.contains('audio')) {
      return _ExpandedVoiceVisual(threat: threat);
    } else if (cls.contains('video') || mediaType.contains('video')) {
      return _ExpandedVideoPlaceholder(threat: threat);
    } else if (cls.contains('image') || mediaType.contains('image')) {
      return _ExpandedImagePlaceholder(threat: threat);
    }
    // Generic fallback
    return _NoPreviewPlaceholder(
      icon: Icons.analytics_rounded,
      label: 'Metadata analysis only',
      color: Colors.white.withValues(alpha: 0.3),
    );
  }'''

expanded_new = '''  Widget _buildExpandedContent() {
    final mediaType = threat.mediaType.toLowerCase();
    final cls = threat.threatClass.toLowerCase();
    final isVideo = cls.contains('video') || mediaType.contains('video');
    final isVoice = cls.contains('voice') || cls.contains('clone') || mediaType.contains('voice') || mediaType.contains('audio');
    final isImage = cls.contains('image') || mediaType.contains('image');
    final isDocument = cls.contains('text') || mediaType.contains('text') || cls.contains('document');
    
    Uint8List? imageBytes;
    if (threat.previewData != null && threat.previewData!.isNotEmpty) {
      try {
        String raw = threat.previewData!;
        final commaIdx = raw.indexOf(',');
        if (commaIdx > 0 && commaIdx < 80) raw = raw.substring(commaIdx + 1);
        imageBytes = base64Decode(raw.trim());
      } catch (_) {}
    }

    if (isVoice) {
      return _ExpandedVoiceVisual(threat: threat);
    } else if (isVideo) {
      return _ExpandedVideoPlaceholder(threat: threat, imageBytes: imageBytes);
    } else if (isImage && imageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          imageBytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => _NoPreviewPlaceholder(
            icon: Icons.broken_image_rounded,
            label: 'Image could not be loaded',
            color: const Color(0xFF26D9FF),
          ),
        ),
      );
    } else if (isImage) {
      return _ExpandedImagePlaceholder(threat: threat);
    }
    
    // Generic fallback -> Text report UI
    return _ExpandedTextPlaceholder(threat: threat);
  }'''


# 3. Add text placeholder class, and replace video/audio placeholders
placeholders_old_regex = r'class _ExpandedVideoPlaceholder(.|\n)+?class _NoPreviewPlaceholder'
placeholders_new = '''class _ExpandedVideoPlaceholder extends StatelessWidget {
  const _ExpandedVideoPlaceholder({required this.threat, this.imageBytes});
  final GlobalThreat threat;
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageBytes != null)
            Image.memory(
              imageBytes!,
              fit: BoxFit.cover,
            ),
          Container(
            color: const Color(0xFF0A0A12).withValues(alpha: imageBytes != null ? 0.6 : 1.0),
          ),
          Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: const Color(0xFFFF7043).withValues(alpha: 0.9),
              size: 56,
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                     children: [
                       Text('0:00', style: TextStyle(color: Colors.white70, fontSize: 10)),
                       const SizedBox(width: 8),
                       Expanded(
                         child: LinearProgressIndicator(
                           value: 0.0,
                           backgroundColor: Colors.white24,
                           valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF7043)),
                         )
                       ),
                       const SizedBox(width: 8),
                       Text('0:00', style: TextStyle(color: Colors.white70, fontSize: 10)),
                     ]
                   ),
                   const SizedBox(height: 10),
                   Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.skip_previous_rounded, color: Colors.white, size: 20),
                       const SizedBox(width: 24),
                       Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                       const SizedBox(width: 24),
                       Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
                       const SizedBox(width: 24),
                       Icon(Icons.volume_up_rounded, color: Colors.white70, size: 16),
                     ],
                   ),
                ]
              )
            )
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'LIVE VIDEO STREAM',
                style: TextStyle(color: const Color(0xFFFF7043), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          )
        ],
      )
    );
  }
}

class _ExpandedImagePlaceholder extends StatelessWidget {
  const _ExpandedImagePlaceholder({required this.threat});
  final GlobalThreat threat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_rounded,
            color: const Color(0xFF26D9FF).withValues(alpha: 0.4),
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            'Image analysis • ${threat.score}%',
            style: const TextStyle(color: Color(0xFF7AA6C1), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ExpandedTextPlaceholder extends StatelessWidget {
  const _ExpandedTextPlaceholder({required this.threat});
  final GlobalThreat threat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_rounded, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Text('THREAT ANALYSIS REPORT', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          _buildRow('Type:', threat.threatClass.toUpperCase()),
          _buildRow('Target:', threat.mediaName.isNotEmpty ? threat.mediaName : 'Unknown'),
          _buildRow('Region:', threat.region),
          _buildRow('City:', threat.cityOrZoneLabel),
          const SizedBox(height: 12),
          Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          Text('Analysis', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                threat.artifactSummary.isNotEmpty ? threat.artifactSummary : 'No detailed analysis provided for this threat.',
                style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NoPreviewPlaceholder'''


# Replace everything
if preview_old in content:
    content = content.replace(preview_old, preview_new)
    print("Replaced preview builder")
else:
    print("Failed to find preview builder")

if expanded_old in content:
    content = content.replace(expanded_old, expanded_new)
    print("Replaced expanded content builder")
else:
    print("Failed to find expanded content builder")

content_regexd, n = re.subn(placeholders_old_regex, placeholders_new, content)
if n > 0:
    content = content_regexd
    print("Replaced placeholders via regex")
else:
    print("Failed to find placeholders")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done")
