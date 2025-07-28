import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/services.dart';
import '../components/native_dialog.dart';

/// Generic User Management Widget for RevenueCat
/// Handles user login, logout, and purchase restoration
class UserScreen extends StatefulWidget {
  final Function(String)? onUserLogin;
  final Function()? onUserLogout;
  final Function()? onRestorePurchases;

  const UserScreen({
    Key? key,
    this.onUserLogin,
    this.onUserLogout,
    this.onRestorePurchases,
  }) : super(key: key);

  @override
  _UserScreenState createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  bool _isLoading = false;
  String _currentUserID = '';
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      _currentUserID = await Purchases.appUserID;
      _isLoggedIn = _currentUserID.isNotEmpty;
      setState(() {});
    } catch (e) {
      print('Error loading current user: $e');
    }
  }

  Future<void> _logIn(String newAppUserID) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Purchases.logIn(newAppUserID);
      _currentUserID = await Purchases.appUserID;
      _isLoggedIn = true;
      widget.onUserLogin?.call(_currentUserID);
    } on PlatformException catch (e) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => ShowDialogToDismiss(
          title: "Error",
          content: e.message ?? "Unknown error",
          buttonText: 'OK'
        )
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _logOut() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Purchases.logOut();
      _currentUserID = await Purchases.appUserID;
      _isLoggedIn = false;
      widget.onUserLogout?.call();
    } on PlatformException catch (e) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => ShowDialogToDismiss(
          title: "Error",
          content: e.message ?? "Unknown error",
          buttonText: 'OK'
        )
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _restore() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Purchases.restorePurchases();
      widget.onRestorePurchases?.call();
    } on PlatformException catch (e) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => ShowDialogToDismiss(
          title: "Error",
          content: e.message ?? "Unknown error",
          buttonText: 'OK'
        )
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current User',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('User ID: $_currentUserID'),
                    Text('Status: ${_isLoggedIn ? "Logged In" : "Anonymous"}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Actions',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _showLoginDialog(),
                        child: const Text('Login User'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _logOut,
                        child: const Text('Logout User'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _restore,
                        child: const Text('Restore Purchases'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Login User'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'User ID',
            hintText: 'Enter user ID',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _logIn(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
}
