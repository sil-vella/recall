import 'package:flutter/services.dart';

class UserInput {
  static String handleUsernameChange(String currentValue, String newValue) {
    final regex = RegExp(r'^[a-zA-Z0-9]+$');
    if (newValue.isEmpty || regex.hasMatch(newValue)) {
      return newValue;
    }
    return currentValue;
  }

  static String handleNumOfOpponentsChange(
      String currentValue, String newValue) {
    const validValues = ['3', '4', '5'];
    if (validValues.contains(newValue)) {
      return newValue;
    }
    return currentValue;
  }

  static void copyTextToClipboard(String text) {
    final modifiedText = text.replaceAll('5000', '3000');
    Clipboard.setData(ClipboardData(text: modifiedText));
  }
}
