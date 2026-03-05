// Web-only: registers AdSense view factories and provides placeholder widget.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../utils/consts/config.dart';

bool _registered = false;

/// True when AdSense client and top slot are configured.
bool get hasTopAdSlot =>
    Config.adsenseClientId.isNotEmpty && Config.adsenseTopSlot.isNotEmpty;

/// True when AdSense client and bottom slot are configured.
bool get hasBottomAdSlot =>
    Config.adsenseClientId.isNotEmpty && Config.adsenseBottomSlot.isNotEmpty;

/// Registers view factories for top and bottom AdSense slots. Call once from main() when kIsWeb.
void registerAdSenseViewFactories() {
  if (_registered) return;
  _registered = true;

  final clientId = Config.adsenseClientId;
  final topSlot = Config.adsenseTopSlot;
  final bottomSlot = Config.adsenseBottomSlot;

  if (clientId.isEmpty) return;
  if (topSlot.isNotEmpty) {
    ui_web.platformViewRegistry.registerViewFactory(
      'adsense-top',
      (int viewId) => _createAdElement(viewId, clientId, topSlot),
    );
  }
  if (bottomSlot.isNotEmpty) {
    ui_web.platformViewRegistry.registerViewFactory(
      'adsense-bottom',
      (int viewId) => _createAdElement(viewId, clientId, bottomSlot),
    );
  }
}

html.Element _createAdElement(int viewId, String clientId, String slotId) {
  final div = html.DivElement()
    ..id = 'adsense-$viewId'
    ..style.display = 'block'
    ..style.textAlign = 'center';

  final ins = html.Element.tag('ins')
    ..classes.add('adsbygoogle')
    ..style.display = 'block'
    ..attributes['data-ad-client'] = clientId
    ..attributes['data-ad-slot'] = slotId
    ..attributes['data-ad-format'] = 'auto';
  div.append(ins);

  final script = html.ScriptElement()
    ..text = '(adsbygoogle = window.adsbygoogle || []).push({});';
  div.append(script);

  return div;
}

/// Builds the AdSense placeholder for the given slot ('top' or 'bottom'). Web only.
Widget buildAdSensePlaceholder(String slot) {
  final clientId = Config.adsenseClientId;
  final slotId = slot == 'top' ? Config.adsenseTopSlot : Config.adsenseBottomSlot;
  if (clientId.isEmpty || slotId.isEmpty) return const SizedBox.shrink();

  final viewType = 'adsense-$slot';
  return SizedBox(
    height: 50,
    child: Center(
      child: HtmlElementView(viewType: viewType),
    ),
  );
}
