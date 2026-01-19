// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
//ToDO: replace domain and port according to your server configuration

String urlWebSocket = "ws://127.0.0.1:5000"; // Connects inside Docker network
String urlWebSocketMobile = "ws://127.0.0.1:5000"; // Change for production


 IO.Socket? socket;
