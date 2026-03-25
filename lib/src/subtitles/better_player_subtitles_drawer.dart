import 'dart:async';
import 'package:better_player/better_player.dart';
import 'package:better_player/src/subtitles/better_player_subtitle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class BetterPlayerSubtitlesDrawer extends StatefulWidget {
  final List<BetterPlayerSubtitle> subtitles;
  final BetterPlayerController betterPlayerController;
  final BetterPlayerSubtitlesConfiguration? betterPlayerSubtitlesConfiguration;
  final Stream<bool> playerVisibilityStream;

  const BetterPlayerSubtitlesDrawer({
    Key? key,
    required this.subtitles,
    required this.betterPlayerController,
    this.betterPlayerSubtitlesConfiguration,
    required this.playerVisibilityStream,
  }) : super(key: key);

  @override
  _BetterPlayerSubtitlesDrawerState createState() =>
      _BetterPlayerSubtitlesDrawerState();
}

class _BetterPlayerSubtitlesDrawerState
    extends State<BetterPlayerSubtitlesDrawer> {
  late TextStyle _innerTextStyle;
  late TextStyle _outerTextStyle;

  VideoPlayerValue? _latestValue;
  BetterPlayerSubtitlesConfiguration? _configuration;
  bool _playerVisible = false;

  ///Stream used to detect if play controls are visible or not
  late StreamSubscription _visibilityStreamSubscription;

  @override
  void initState() {
    _visibilityStreamSubscription =
        widget.playerVisibilityStream.listen((state) {
          setState(() {
            _playerVisible = state;
          });
        });

    if (widget.betterPlayerSubtitlesConfiguration != null) {
      _configuration = widget.betterPlayerSubtitlesConfiguration;
    } else {
      _configuration = setupDefaultConfiguration();
    }

    widget.betterPlayerController.videoPlayerController!
        .addListener(_updateState);

    _outerTextStyle = TextStyle(
        fontSize: _configuration!.fontSize,
        fontFamily: _configuration!.fontFamily,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _configuration!.outlineSize
          ..color = _configuration!.outlineColor);

    _innerTextStyle = TextStyle(
        fontFamily: _configuration!.fontFamily,
        color: _configuration!.fontColor,
        fontSize: _configuration!.fontSize);

    super.initState();
  }

  @override
  void dispose() {
    widget.betterPlayerController.videoPlayerController!
        .removeListener(_updateState);
    _visibilityStreamSubscription.cancel();
    super.dispose();
  }

  ///Called when player state has changed, i.e. new player position, etc.
  void _updateState() {
    if (mounted) {
      setState(() {
        _latestValue =
            widget.betterPlayerController.videoPlayerController!.value;
      });
    }
  }

  BetterPlayerSubtitlesConfiguration get _effectiveConfiguration =>
      widget.betterPlayerSubtitlesConfiguration ?? setupDefaultConfiguration();

  MainAxisAlignment _mainAxisAlignmentForSubtitleRow(Alignment a) {
    const t = 0.2;
    if (a.x < -t) return MainAxisAlignment.start;
    if (a.x > t) return MainAxisAlignment.end;
    return MainAxisAlignment.center;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _effectiveConfiguration;
    final BetterPlayerSubtitle? subtitle = _getSubtitleAtCurrentPosition();
    widget.betterPlayerController.renderedSubtitle = subtitle;
    final List<String> subtitles = subtitle?.texts ?? [];
    final List<Widget> textWidgets =
    subtitles.map((text) => _buildSubtitleTextWidget(text)).toList();

    return Container(
      height: double.infinity,
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: _playerVisible
              ? cfg.bottomPadding + 30
              : cfg.bottomPadding,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: textWidgets,
        ),
      ),
    );
  }

  BetterPlayerSubtitle? _getSubtitleAtCurrentPosition() {
    if (_latestValue == null) {
      return null;
    }

    final Duration position = _latestValue!.position;
    for (final BetterPlayerSubtitle subtitle
        in widget.betterPlayerController.subtitlesLines) {
      if (subtitle.start! <= position && subtitle.end! >= position) {
        return subtitle;
      }
    }
    return null;
  }

  Widget _buildSubtitleTextWidget(String subtitleText) {
    final cfg = _effectiveConfiguration;
    return Row(
      mainAxisAlignment: _mainAxisAlignmentForSubtitleRow(cfg.alignment),
      children: [
        _getTextWithStroke(subtitleText),
      ],
    );
  }

  bool _subtitleTextLooksLikeHtml(String s) =>
      s.contains('<') && s.contains('>');

  Widget _getTextWithStroke(String subtitleText) {
    final cfg = _effectiveConfiguration;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cfg.backgroundColor,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: cfg.leftPadding,
          right: cfg.rightPadding,
          top: 4,
          bottom: 4,
        ),
        child: _subtitleTextLooksLikeHtml(subtitleText)
            ? IntrinsicWidth(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (cfg.outlineEnabled)
                _buildHtmlWidget(subtitleText, _outerTextStyle)
              else
                const SizedBox(),
              _buildHtmlWidget(subtitleText, _innerTextStyle)
            ],
          ),
        )
            : _buildPlainSubtitleWithStroke(subtitleText, cfg),
      ),
    );
  }

  Widget _buildPlainSubtitleWithStroke(String text,
      BetterPlayerSubtitlesConfiguration cfg,) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (cfg.outlineEnabled)
          Text(
            text,
            style: _outerTextStyle,
            textAlign: TextAlign.center,
            softWrap: true,
          ),
        Text(
          text,
          style: _innerTextStyle,
          textAlign: TextAlign.center,
          softWrap: true,
        ),
      ],
    );
  }

  Widget _buildHtmlWidget(String text, TextStyle textStyle) {
    return HtmlWidget(
      text,
      textStyle: textStyle,
    );
  }

  BetterPlayerSubtitlesConfiguration setupDefaultConfiguration() {
    return const BetterPlayerSubtitlesConfiguration();
  }
}
