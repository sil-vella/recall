import os
import json
import pytest
import gzip
import glob
from datetime import datetime, timedelta
from ..audit_logger import AuditLogger

class TestAuditLogger:
    """Test cases for AuditLogger class."""
    
    def setup_method(self):
        """Clean up audit log files before each test."""
        # Remove main log file
        if os.path.exists(AuditLogger.AUDIT_LOG_PATH):
            os.remove(AuditLogger.AUDIT_LOG_PATH)
        
        # Remove any rotated or compressed log files
        for log_file in glob.glob(f"{AuditLogger.AUDIT_LOG_PATH}.*"):
            os.remove(log_file)
    
    def test_log_rotation(self):
        """Test log file rotation when size limit is reached."""
        # Create a large log entry to trigger rotation
        large_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'transaction_id': 'test_tx_123',
            'user_id': 'user_456',
            'action_type': 'test',
            'credit_delta': 100.0,
            'source': {'test': 'data' * 10000},  # Make entry large
            'metadata': {}
        }
        
        # Write enough entries to exceed MAX_FILE_SIZE
        while os.path.getsize(AuditLogger.AUDIT_LOG_PATH) < AuditLogger.MAX_FILE_SIZE:
            AuditLogger._write_to_log(large_entry, "TEST")
        
        # Verify rotation occurred
        rotated_files = glob.glob(f"{AuditLogger.AUDIT_LOG_PATH}.*")
        assert len(rotated_files) > 0
        
        # Verify new log file was created
        assert os.path.exists(AuditLogger.AUDIT_LOG_PATH)
    
    def test_log_compression(self):
        """Test compression of old log files."""
        # Create a test log file with old timestamp
        old_timestamp = (datetime.now() - timedelta(days=AuditLogger.COMPRESS_AFTER_DAYS + 1)).strftime("%Y%m%d_%H%M%S")
        old_log_file = f"{AuditLogger.AUDIT_LOG_PATH}.{old_timestamp}"
        
        # Write some test data
        with open(old_log_file, 'w') as f:
            f.write("test log data\n")
        
        # Trigger compression
        AuditLogger.compress_old_logs()
        
        # Verify old file was compressed
        assert not os.path.exists(old_log_file)
        assert os.path.exists(f"{old_log_file}.gz")
        
        # Verify compressed content
        with gzip.open(f"{old_log_file}.gz", 'rt') as f:
            content = f.read()
            assert content == "test log data\n"
    
    def test_max_files_cleanup(self):
        """Test cleanup of old rotated files when MAX_FILES is exceeded."""
        # Create more rotated files than MAX_FILES
        for i in range(AuditLogger.MAX_FILES + 2):
            timestamp = (datetime.now() - timedelta(days=i)).strftime("%Y%m%d_%H%M%S")
            rotated_file = f"{AuditLogger.AUDIT_LOG_PATH}.{timestamp}"
            with open(rotated_file, 'w') as f:
                f.write(f"test log data {i}\n")
        
        # Trigger rotation (which should clean up old files)
        AuditLogger.rotate_log()
        
        # Verify only MAX_FILES files remain
        rotated_files = glob.glob(f"{AuditLogger.AUDIT_LOG_PATH}.*")
        assert len(rotated_files) <= AuditLogger.MAX_FILES
    
    def test_log_transaction(self):
        """Test logging a transaction."""
        # Test data
        transaction_id = "test_tx_123"
        user_id = "user_456"
        action_type = "purchase"
        credit_delta = 100.0
        source = {
            "service": "payment_service",
            "ip": "192.168.1.1",
            "client": "web_app"
        }
        metadata = {
            "item_id": "item_789",
            "quantity": 2
        }
        
        # Log the transaction
        AuditLogger.log_transaction(
            transaction_id=transaction_id,
            user_id=user_id,
            action_type=action_type,
            credit_delta=credit_delta,
            source=source,
            metadata=metadata
        )
        
        # Verify log file exists and contains the entry
        assert os.path.exists(AuditLogger.AUDIT_LOG_PATH)
        
        with open(AuditLogger.AUDIT_LOG_PATH, 'r') as f:
            log_entry = json.loads(f.readline().split('] ', 1)[1])
            
            assert log_entry['transaction_id'] == transaction_id
            assert log_entry['user_id'] == user_id
            assert log_entry['action_type'] == action_type
            assert log_entry['credit_delta'] == credit_delta
            assert log_entry['source'] == source
            assert log_entry['metadata'] == metadata
            assert 'timestamp' in log_entry
    
    def test_log_balance_change(self):
        """Test logging a balance change."""
        # Test data
        user_id = "user_456"
        old_balance = 1000.0
        new_balance = 900.0
        transaction_id = "test_tx_123"
        reason = "purchase completed"
        
        # Log the balance change
        AuditLogger.log_balance_change(
            user_id=user_id,
            old_balance=old_balance,
            new_balance=new_balance,
            transaction_id=transaction_id,
            reason=reason
        )
        
        # Verify log file exists and contains the entry
        assert os.path.exists(AuditLogger.AUDIT_LOG_PATH)
        
        with open(AuditLogger.AUDIT_LOG_PATH, 'r') as f:
            log_entry = json.loads(f.readline().split('] ', 1)[1])
            
            assert log_entry['user_id'] == user_id
            assert log_entry['old_balance'] == old_balance
            assert log_entry['new_balance'] == new_balance
            assert log_entry['transaction_id'] == transaction_id
            assert log_entry['reason'] == reason
            assert 'timestamp' in log_entry
    
    def test_log_validation_failure(self):
        """Test logging a validation failure."""
        # Test data
        transaction_id = "test_tx_123"
        user_id = "user_456"
        validation_type = "amount_validation"
        error_message = "Insufficient balance"
        context = {
            "current_balance": 100.0,
            "requested_amount": 200.0
        }
        
        # Log the validation failure
        AuditLogger.log_validation_failure(
            transaction_id=transaction_id,
            user_id=user_id,
            validation_type=validation_type,
            error_message=error_message,
            context=context
        )
        
        # Verify log file exists and contains the entry
        assert os.path.exists(AuditLogger.AUDIT_LOG_PATH)
        
        with open(AuditLogger.AUDIT_LOG_PATH, 'r') as f:
            log_entry = json.loads(f.readline().split('] ', 1)[1])
            
            assert log_entry['transaction_id'] == transaction_id
            assert log_entry['user_id'] == user_id
            assert log_entry['validation_type'] == validation_type
            assert log_entry['error_message'] == error_message
            assert log_entry['context'] == context
            assert 'timestamp' in log_entry
    
    def test_log_retention(self):
        """Test that logs are retained for the specified period."""
        # Log a test entry
        AuditLogger.log_transaction(
            transaction_id="test_tx_123",
            user_id="user_456",
            action_type="test",
            credit_delta=100.0,
            source={},
            metadata={}
        )
        
        # Verify log file exists
        assert os.path.exists(AuditLogger.AUDIT_LOG_PATH)
        
        # Check file modification time
        file_mtime = os.path.getmtime(AuditLogger.AUDIT_LOG_PATH)
        file_age_days = (datetime.now().timestamp() - file_mtime) / (24 * 3600)
        
        # File should be less than retention period old
        assert file_age_days < AuditLogger.RETENTION_DAYS 