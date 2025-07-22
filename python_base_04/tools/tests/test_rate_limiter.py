import unittest
from unittest.mock import patch, MagicMock, Mock
from system.managers.rate_limiter_manager import RateLimiterManager
from utils.config.config import Config
import time
from redis.exceptions import RedisError

class TestRateLimiterManager(unittest.TestCase):
    def setUp(self):
        self.rate_limiter = RateLimiterManager()
        self.rate_limiter.redis_manager = Mock()
        self.test_ip = "127.0.0.1"
        self.test_user = "test_user"
        self.test_api_key = "test_api_key"
        self.test_identifiers = {
            'ip': self.test_ip,
            'user': self.test_user,
            'api_key': self.test_api_key
        }

    def test_singleton_pattern(self):
        """Test that RateLimiterManager is a singleton."""
        rate_limiter2 = RateLimiterManager()
        self.assertIs(self.rate_limiter, rate_limiter2)

    @patch('system.managers.redis_manager.RedisManager')
    def test_check_rate_limit_first_request(self, mock_redis):
        """Test rate limit check for first request."""
        mock_redis.get.return_value = None
        mock_redis.ttl.return_value = 60
        result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
        self.assertTrue(result['allowed'])
        self.assertEqual(result['remaining']['ip'], Config.RATE_LIMIT_IP_REQUESTS - 1)
        self.assertIn('ip', result['reset_time'])
        self.assertEqual(len(result['exceeded_types']), 0)
        self.assertEqual(len(result['banned_types']), 0)
        mock_redis.set.assert_called_once()

    @patch('system.managers.redis_manager.RedisManager')
    def test_check_rate_limit_exceeded(self, mock_redis):
        """Test rate limit check when limit is exceeded."""
        mock_redis.get.return_value = str(Config.RATE_LIMIT_IP_REQUESTS)
        mock_redis.ttl.return_value = 60
        result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
        self.assertFalse(result['allowed'])
        self.assertEqual(result['remaining']['ip'], 0)
        self.assertIn('ip', result['exceeded_types'])
        self.assertEqual(len(result['banned_types']), 0)
        mock_redis.incr.assert_not_called()

    @patch('system.managers.redis_manager.RedisManager')
    def test_check_rate_limit_redis_error(self, mock_redis):
        """Test rate limit check when Redis error occurs."""
        mock_redis.get.side_effect = RedisError("Connection error")
        result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
        self.assertTrue(result['allowed'])  # Should allow request on error
        self.assertEqual(result['remaining'], {})
        self.assertEqual(result['exceeded_types'], [])
        self.assertEqual(len(result['banned_types']), 0)

    @patch('system.managers.redis_manager.RedisManager')
    def test_check_multiple_rate_limits(self, mock_redis):
        """Test checking multiple rate limits simultaneously."""
        # Mock different values for different limit types
        mock_redis.get.side_effect = [
            str(Config.RATE_LIMIT_IP_REQUESTS),  # IP limit exceeded
            str(Config.RATE_LIMIT_USER_REQUESTS - 1),  # User limit not exceeded
            str(Config.RATE_LIMIT_API_KEY_REQUESTS - 2)  # API key limit not exceeded
        ]
        mock_redis.ttl.return_value = 60

        result = self.rate_limiter.check_rate_limit(
            ['ip', 'user', 'api_key'],
            self.test_identifiers
        )

        self.assertFalse(result['allowed'])
        self.assertEqual(result['remaining']['ip'], 0)
        self.assertEqual(result['remaining']['user'], 1)
        self.assertEqual(result['remaining']['api_key'], 2)
        self.assertIn('ip', result['exceeded_types'])
        self.assertNotIn('user', result['exceeded_types'])
        self.assertNotIn('api_key', result['exceeded_types'])
        self.assertEqual(len(result['banned_types']), 0)

    @patch('system.managers.redis_manager.RedisManager')
    def test_check_rate_limit_with_missing_identifier(self, mock_redis):
        """Test rate limit check when some identifiers are missing."""
        mock_redis.get.return_value = None
        result = self.rate_limiter.check_rate_limit(
            ['ip', 'user', 'api_key'],
            {'ip': self.test_ip}  # Only IP provided
        )
        self.assertTrue(result['allowed'])
        self.assertIn('ip', result['remaining'])
        self.assertNotIn('user', result['remaining'])
        self.assertNotIn('api_key', result['remaining'])
        self.assertEqual(len(result['exceeded_types']), 0)
        self.assertEqual(len(result['banned_types']), 0)

    @patch('system.managers.redis_manager.RedisManager')
    def test_get_rate_limit_status(self, mock_redis):
        """Test getting rate limit status for an identifier."""
        mock_redis.get.return_value = "5"
        mock_redis.ttl.return_value = 30
        status = self.rate_limiter.get_rate_limit_status('ip', self.test_ip)
        
        self.assertEqual(status['current'], 5)
        self.assertEqual(status['remaining'], Config.RATE_LIMIT_IP_REQUESTS - 5)
        self.assertGreater(status['reset_time'], int(time.time()))
        self.assertFalse(status['banned'])

    @patch('system.managers.redis_manager.RedisManager')
    def test_reset_rate_limit(self, mock_redis):
        """Test resetting rate limit for an identifier."""
        mock_redis.delete.return_value = True
        result = self.rate_limiter.reset_rate_limit('ip', self.test_ip)
        self.assertTrue(result)
        mock_redis.delete.assert_called_once()

    def test_config_initialization(self):
        """Test that rate limit configurations are properly initialized."""
        config = self.rate_limiter.config
        self.assertIn('ip', config)
        self.assertIn('user', config)
        self.assertIn('api_key', config)
        
        for limit_type in ['ip', 'user', 'api_key']:
            self.assertIn('requests', config[limit_type])
            self.assertIn('window', config[limit_type])
            self.assertIn('prefix', config[limit_type])
            self.assertIn('enabled', config[limit_type])
            self.assertTrue(config[limit_type]['enabled'])

    def test_auto_ban_violation_tracking(self):
        """Test auto-ban violation tracking."""
        # Setup
        self.rate_limiter.redis_manager.get.return_value = str(Config.RATE_LIMIT_IP_REQUESTS)
        self.rate_limiter.redis_manager.ttl.return_value = 30
        self.rate_limiter.redis_manager.incr.return_value = Config.AUTO_BAN_VIOLATIONS_THRESHOLD
        
        # Test
        result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
        
        # Verify
        self.assertFalse(result['allowed'])
        self.assertEqual(result['exceeded_types'], ['ip'])
        self.assertEqual(result['banned_types'], ['ip'])
        self.rate_limiter.redis_manager.set.assert_called_with(
            f"{Config.AUTO_BAN_PREFIX}:ip:{self.test_ip}",
            1,
            expire=Config.AUTO_BAN_DURATION
        )

    def test_auto_ban_check(self):
        """Test auto-ban check functionality."""
        # Setup
        self.rate_limiter.redis_manager.exists.return_value = True
        
        # Test
        result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
        
        # Verify
        self.assertFalse(result['allowed'])
        self.assertEqual(result['banned_types'], ['ip'])
        self.rate_limiter.redis_manager.get.assert_not_called()

    def test_auto_ban_disabled(self):
        """Test behavior when auto-ban is disabled."""
        # Setup
        with patch('utils.config.config.Config.AUTO_BAN_ENABLED', False):
            self.rate_limiter.redis_manager.get.return_value = str(Config.RATE_LIMIT_IP_REQUESTS)
            self.rate_limiter.redis_manager.ttl.return_value = 30
            
            # Test
            result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
            
            # Verify
            self.assertFalse(result['allowed'])
            self.assertEqual(result['exceeded_types'], ['ip'])
            self.assertEqual(len(result['banned_types']), 0)
            self.rate_limiter.redis_manager.incr.assert_not_called()

    def test_auto_ban_violation_window(self):
        """Test auto-ban violation window expiration."""
        # Setup
        self.rate_limiter.redis_manager.get.return_value = str(Config.RATE_LIMIT_IP_REQUESTS)
        self.rate_limiter.redis_manager.ttl.return_value = 30
        self.rate_limiter.redis_manager.incr.return_value = 1
        
        # Test
        result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
        
        # Verify
        self.assertFalse(result['allowed'])
        self.assertEqual(result['exceeded_types'], ['ip'])
        self.assertEqual(len(result['banned_types']), 0)
        self.rate_limiter.redis_manager.expire.assert_called_with(
            f"{Config.AUTO_BAN_VIOLATIONS_PREFIX}:ip:{self.test_ip}",
            Config.AUTO_BAN_WINDOW
        )

    def test_auto_ban_redis_error(self):
        """Test auto-ban behavior when Redis error occurs."""
        # Setup
        self.rate_limiter.redis_manager.get.return_value = str(Config.RATE_LIMIT_IP_REQUESTS)
        self.rate_limiter.redis_manager.ttl.return_value = 30
        self.rate_limiter.redis_manager.incr.side_effect = RedisError("Connection error")
        
        # Test
        result = self.rate_limiter.check_rate_limit(['ip'], {'ip': self.test_ip})
        
        # Verify
        self.assertFalse(result['allowed'])
        self.assertEqual(result['exceeded_types'], ['ip'])
        self.assertEqual(len(result['banned_types']), 0)

if __name__ == '__main__':
    unittest.main() 