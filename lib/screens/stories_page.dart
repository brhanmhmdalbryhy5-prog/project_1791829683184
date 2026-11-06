import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/colors.dart';
import '../core/helpers.dart';
import '../core/theme_manager.dart';
import '../data/app_data.dart';

// ================= شريط الستوري =================
class StoriesBar extends StatefulWidget {
  final AppData data;
  const StoriesBar({super.key, required this.data});

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  Future<void> _addStory() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;
    final ok = await widget.data.addStory(File(picked.path));
    if (mounted) showSnack(context, ok ? '✅ تمت إضافة الستوري (24 ساعة)' : 'تعذر إضافة الستوري.');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.data,
      builder: (context, _) {
        final stories = widget.data.activeStories;
        final Map<int, Map<String, dynamic>> latestByAccount = {};
        for (final s in stories) {
          final id = parseInt(s['account_id']);
          latestByAccount[id] = s;
        }

        return SizedBox(
          height: 105,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // زر إضافة ستوري
              GestureDetector(
                onTap: _addStory,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: ThemeManager.instance.getButtonGradient(),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: ThemeManager.instance.getGlowShadow(),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ClipOval(
                              child: widget.data.currentAvatar.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: widget.data.currentAvatar, width: 60, height: 60, fit: BoxFit.cover)
                                  : const Icon(Icons.person, color: Colors.white, size: 30),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: ThemeManager.instance.primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.add, size: 14, color: Colors.black),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const SizedBox(
                        width: 70,
                        child: Text('ستوري', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),

              // ستوري المستخدمين
              ...latestByAccount.entries.map((entry) {
                final s = entry.value;
                final name = widget.data.displayNameForAccount(entry.key);
                final avatar = widget.data.avatarForAccount(entry.key);
                final hasUnviewed = !widget.data.hasViewedStory(s['id']);
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => StoryViewerPage(data: widget.data, initialIndex: stories.indexOf(s)),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        // ✅ التصحيح: padding خارج BoxDecoration
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: hasUnviewed
                                ? LinearGradient(colors: [ThemeManager.instance.primaryColor, AppColors.getColor(2), AppColors.getColor(4)])
                                : null,
                            color: hasUnviewed ? null : Colors.grey.shade600,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.cardBlack,
                            backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                            child: avatar.isEmpty ? const Icon(Icons.person, color: AppColors.gold) : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 70,
                          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}

// ================= عارض الستوري =================
class StoryViewerPage extends StatefulWidget {
  final AppData data;
  final int initialIndex;
  const StoryViewerPage({super.key, required this.data, required this.initialIndex});

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressController;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _progressController = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _next();
    });
    _progressController.forward();
    widget.data.markStoryViewed(widget.data.activeStories[_current]['id']);
  }

  void _next() {
    if (_current + 1 >= widget.data.activeStories.length) {
      Navigator.pop(context);
      return;
    }
    setState(() => _current++);
    _pageController.animateToPage(_current, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    _progressController.reset();
    _progressController.forward();
    widget.data.markStoryViewed(widget.data.activeStories[_current]['id']);
  }

  void _previous() {
    if (_current == 0) return;
    setState(() => _current--);
    _pageController.animateToPage(_current, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    _progressController.reset();
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.activeStories.isEmpty) {
      return const Scaffold(body: Center(child: Text('لا توجد ستوري')));
    }
    final story = widget.data.activeStories[_current];
    final name = widget.data.displayNameForAccount(story['account_id']);
    final avatar = widget.data.avatarForAccount(story['account_id']);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTapUp: (d) {
              final x = d.localPosition.dx;
              final w = MediaQuery.of(context).size.width;
              if (x < w / 2) {
                _previous();
              } else {
                _next();
              }
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.data.activeStories.length,
              onPageChanged: (i) {
                setState(() => _current = i);
                _progressController.reset();
                _progressController.forward();
              },
              itemBuilder: (_, i) {
                final s = widget.data.activeStories[i];
                return CachedNetworkImage(
                  imageUrl: clean(s['image_url']),
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 80, color: Colors.white)),
                );
              },
            ),
          ),
          Positioned(
            top: 40,
            left: 8,
            right: 8,
            child: AnimatedBuilder(
              animation: _progressController,
              builder: (_, __) => LinearProgressIndicator(
                value: _progressController.value,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
          Positioned(
            top: 55,
            left: 12,
            right: 12,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                  child: avatar.isEmpty ? const Icon(Icons.person, size: 18) : null,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}