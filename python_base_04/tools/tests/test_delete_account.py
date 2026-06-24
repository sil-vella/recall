"""Unit tests for self-service account deletion helpers."""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

import bcrypt

from core.modules.user_management_module.user_management_main import UserManagementModule


def _password_hash(raw: str) -> str:
    return bcrypt.hashpw(raw.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


class TestDeleteAccountHelpers(unittest.TestCase):
    def setUp(self):
        self.module = UserManagementModule()

    def test_is_google_only_account(self):
        google_user = {
            "auth_providers": ["google"],
            "password": "",
        }
        email_user = {
            "auth_providers": ["email"],
            "password": _password_hash("secret"),
        }
        self.assertTrue(UserManagementModule._is_google_only_account(google_user))
        self.assertFalse(UserManagementModule._is_google_only_account(email_user))

    def test_account_requires_password_for_deletion(self):
        google_user = {"auth_providers": ["google"], "password": ""}
        guest_user = {
            "auth_providers": ["email"],
            "password": _password_hash("guest"),
            "account_type": "guest",
        }
        comp_user = {"is_comp_player": True, "password": _password_hash("x")}
        self.assertFalse(
            UserManagementModule._account_requires_password_for_deletion(google_user)
        )
        self.assertTrue(
            UserManagementModule._account_requires_password_for_deletion(guest_user)
        )
        self.assertFalse(
            UserManagementModule._account_requires_password_for_deletion(comp_user)
        )

    def test_verify_user_password(self):
        user = {"password": _password_hash("correct")}
        self.assertTrue(UserManagementModule._verify_user_password(user, "correct"))
        self.assertFalse(UserManagementModule._verify_user_password(user, "wrong"))

    def test_purge_user_data_deletes_users_and_satellite_collections(self):
        uid = "507f1f77bcf86cd799439011"
        user_doc = {
            "_id": uid,
            "profile": {"picture": "https://app.example/public/avatar-media/abc.webp"},
        }
        self.module.db_manager = MagicMock()
        self.module.db_manager.delete = MagicMock(return_value=1)
        self.module.app_manager = MagicMock()
        redis_mgr = MagicMock()
        self.module.app_manager.get_redis_manager.return_value = redis_mgr

        with patch.object(self.module, "_delete_user_avatar_file") as mock_avatar:
            self.module._purge_user_data(uid, user_doc)

        delete_calls = [c.args for c in self.module.db_manager.delete.call_args_list]
        collections = {args[0] for args in delete_calls}
        self.assertIn("users", collections)
        self.assertIn("notifications", collections)
        self.assertIn("user_events", collections)
        self.assertIn("dutch_match_win_outcomes", collections)
        mock_avatar.assert_called_once_with(user_doc)
        redis_mgr.clear_user_login_session_active.assert_called_once_with(uid)
        redis_mgr.bump_user_auth_generation.assert_called_once_with(uid)


class TestDeleteMyAccountEndpoint(unittest.TestCase):
    def setUp(self):
        from flask import Flask
        self.app = Flask(__name__)
        self.module = UserManagementModule()
        self.module.db_manager = MagicMock()
        self.module.app_manager = MagicMock()
        self.module.app_manager.jwt_manager = MagicMock()

    def _call_delete(self, user_id, body, headers=None):
        headers = headers or {}
        with self.app.test_request_context(
            '/userauth/users/delete-account',
            method='POST',
            json=body,
            headers=headers,
        ):
            from flask import request
            request.user_id = user_id
            return self.module.delete_my_account()

    def test_rejects_wrong_confirmation(self):
        resp, status = self._call_delete(
            "507f1f77bcf86cd799439011",
            {"confirmation": "delete", "password": "secret"},
        )
        self.assertEqual(status, 400)
        self.assertFalse(resp.get_json()["success"])

    def test_rejects_comp_player(self):
        self.module.db_manager.find_one.return_value = {
            "_id": "507f1f77bcf86cd799439011",
            "is_comp_player": True,
            "password": _password_hash("x"),
        }
        resp, status = self._call_delete(
            "507f1f77bcf86cd799439011",
            {"confirmation": "DELETE"},
        )
        self.assertEqual(status, 403)
        self.assertFalse(resp.get_json()["success"])

    def test_requires_password_for_email_account(self):
        self.module.db_manager.find_one.return_value = {
            "_id": "507f1f77bcf86cd799439011",
            "auth_providers": ["email"],
            "password": _password_hash("secret"),
        }
        resp, status = self._call_delete(
            "507f1f77bcf86cd799439011",
            {"confirmation": "DELETE"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(resp.get_json()["error"], "Password required")

    def test_rejects_wrong_password(self):
        self.module.db_manager.find_one.return_value = {
            "_id": "507f1f77bcf86cd799439011",
            "auth_providers": ["email"],
            "password": _password_hash("secret"),
        }
        resp, status = self._call_delete(
            "507f1f77bcf86cd799439011",
            {"confirmation": "DELETE", "password": "wrong"},
        )
        self.assertEqual(status, 401)
        self.assertEqual(resp.get_json()["error"], "Invalid password")

    def test_allows_google_only_without_password(self):
        uid = "507f1f77bcf86cd799439011"
        user = {
            "_id": uid,
            "auth_providers": ["google"],
            "password": "",
        }
        self.module.db_manager.find_one.return_value = user
        with patch.object(self.module, "_purge_user_data") as purge:
            with patch.object(self.module, "_revoke_request_tokens"):
                resp, status = self._call_delete(uid, {"confirmation": "DELETE"})
        self.assertEqual(status, 200)
        self.assertTrue(resp.get_json()["success"])
        purge.assert_called_once_with(uid, user)

    def test_deletes_with_valid_password(self):
        uid = "507f1f77bcf86cd799439011"
        user = {
            "_id": uid,
            "auth_providers": ["email"],
            "password": _password_hash("secret"),
        }
        self.module.db_manager.find_one.return_value = user
        with patch.object(self.module, "_purge_user_data") as purge:
            with patch.object(self.module, "_revoke_request_tokens") as revoke:
                resp, status = self._call_delete(
                    uid,
                    {"confirmation": "DELETE", "password": "secret"},
                    headers={"Authorization": "Bearer token"},
                )
        self.assertEqual(status, 200)
        self.assertTrue(resp.get_json()["success"])
        purge.assert_called_once_with(uid, user)
        revoke.assert_called_once()


if __name__ == "__main__":
    unittest.main()
